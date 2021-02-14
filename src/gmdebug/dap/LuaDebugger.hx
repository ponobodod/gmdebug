package gmdebug.dap;

import js.Node;
import js.Syntax;
import js.node.Process;
import haxe.ValueException;
import sys.FileSystem;
import js.node.ChildProcess;
import gmdebug.composer.*;
import js.node.util.Promisify;
import js.node.Fs;
import vscode.debugProtocol.DebugProtocol;
import js.node.net.Server;
import haxe.io.Output;
import haxe.io.BytesInput;
import haxe.io.BufferInput;
import js.node.Buffer;
import haxe.io.Bytes;
import haxe.Json;
import js.node.net.Socket;
import js.node.Net;
import vscode.debugAdapter.DebugSession;
import gmdebug.Cross;

using tink.CoreApi;
using gmdebug.composer.ComposeTools;

import gmdebug.GmDebugMessage;
import haxe.io.Path;
import js.node.child_process.ChildProcess;

using Lambda;

@:keep @:await class LuaDebugger extends DebugSession {

	public final commMethod:CommMethod;

	public var clients:Array<FileSocket>; // 0 = server.

	public var clientFiles:Array<ClientFiles>;

	public var dapMode:DapMode;

	var autoLaunch:Bool;

	public var mapClientName:Map<Int, String>;

	var mapClientID:Map<Int, Int>;

	public var serverFolder:String;

	public var clientLocations:Array<String>;

	public var clientsTaken:Map<Int, Bool>;

	var requestRouter:RequestRouter;

	var bytesProcessor:BytesProcessor;

	var prevRequests:PreviousRequests;

	public function new(?x, ?y) {
		super(x, y);
		clientLocations = [];
		serverFolder = null;
		clientsTaken = [];
		mapClientID = [];
		mapClientName = [];
		dapMode = ATTACH;
		autoLaunch = true;
		clientFiles = [];
		clients = [];
		commMethod = Pipe;
		bytesProcessor = new BytesProcessor();
		prevRequests = new PreviousRequests();
		requestRouter = new RequestRouter(this,prevRequests);
		
		Node.process.on("uncaughtException", uncaughtException);
	}

	function uncaughtException(err:js.lib.Error, origin) {
		trace(err.message);
		trace(err.stack);
		this.shutdown();
	}

	function playerAddedMessage(x:GMPlayerAddedMessage) {
		for (ind => loc in clientLocations) {
			if (!clientsTaken.exists(ind)) {
				try {
					playerTry(loc, x.playerID, x.name);
					clientsTaken.set(ind, true);
					break;
				} catch (e) {
					trace('can\'t aquire in $loc');
				}
			}
		}
	}

	@:await function playerTry(clientLoc:String, clientNo:Int, playerName:String) {
		final data = haxe.io.Path.join([clientLoc, Cross.DATA]);
		final input = haxe.io.Path.join([data, Cross.INPUT]);
		final out = haxe.io.Path.join([data, Cross.OUTPUT]);
		makeFifosIfNotExist(input, out);
		final ready = haxe.io.Path.join([data, Cross.READY]);
		final read = @:await aquireReadSocket(out);
		final write = @:await aquireWriteSocket(input);
		final clientID = clients.length;
		read.on(Data, (x:Buffer) -> {
			readGmodBuffer(x, clientID);
		});
		clients.push({
			readS: read,
			writeS: write,
		});
		clientFiles[clientID] = {write: input, read: out};
		sys.io.File.saveContent(ready, "");
		write.write("\004\r\n");
		new ComposedEvent(thread, {
			threadId: clientID,
			reason: Started
		}).send(this);
		mapClientName.set(clientID, playerName);
		mapClientID.set(clientID, clientNo);
		setupPlayer(clientID);
	}

	function setupPlayer(clientID:Int) {
		sendToClient(clientID, new ComposedGmDebugMessage(intialInfo, {location: serverFolder,dapMode : Launch}));
		sendToClient(clientID, new ComposedGmDebugMessage(GmMsgType.clientID, {id: clientID}));
		prevRequests.get(setBreakpoints).run((msg) -> sendToClient(clientID,msg));
		prevRequests.get(setExceptionBreakpoints).run((msg) -> sendToClient(clientID,msg));
		prevRequests.get(setFunctionBreakpoints).run((msg) -> sendToClient(clientID,msg));
		sendToClient(clientID, new ComposedRequest(configurationDone, {}));
	}

	// todo
	function playerRemovedMessage(x:GMPlayerRemovedMessage) {
		new ComposedEvent(thread, {
			threadId: mapClientID.get(x.playerID),
			reason: Exited
		}).send(this);
		clientsTaken.remove(mapClientID.get(x.playerID));
	}

	function serverInfoMessage(x:GMServerInfoMessage) {
		final sp = x.ip.split(":");
		final ip = if (x.isLan) {
			gmdebug.lib.js.Ip.address();
		} else {
			sp[0];
		}
		final port = sp[1];
		js.node.ChildProcess.spawn('xdg-open steam://connect/$ip:$port', {shell: true});
	}

	function processCustomMessages(x:GmDebugMessage<Dynamic>) {
		trace("custom message");
		switch (x.msg) {
			case playerAdded:
				playerAddedMessage(cast x.body);
			case playerRemoved:
				playerRemovedMessage(cast x.body);
			case serverInfo:
				serverInfoMessage(cast x.body);
			case clientID | intialInfo:
				throw "dur";
		}
	}

	@:async function aquireReadSocket(out:String) { //
		final open = Promisify.promisify(Fs.open);
		var fd = @:await open(out, cast Fs.constants.O_RDONLY | Fs.constants.O_NONBLOCK).toPromise();
		return new Socket({fd: fd, writable: false});
	}

	@:async function aquireWriteSocket(inp:String) {
		final open = Promisify.promisify(Fs.open);
		var fd = @:await open(inp, cast Fs.constants.O_RDWR | Fs.constants.O_NONBLOCK).toPromise();
		trace(fd);
		return new Socket({fd: fd, readable: false});
	}

	@:async function pokeServerNamedPipes(attachReq:AttachRequest) {
		// if (!FileSystem.exists(haxe.io.Path.join([serverFolder, Cross.DATA]))) {
		// 	throw "GmDebug is not running on given server";
		// }
		final ready = haxe.io.Path.join([serverFolder, Cross.DATA, Cross.READY]);
		final input = haxe.io.Path.join([serverFolder, Cross.DATA, Cross.INPUT]);
		final output = haxe.io.Path.join([serverFolder, Cross.DATA, Cross.OUTPUT]);
		makeFifosIfNotExist(input, output);
		final gmodInput = @:await aquireWriteSocket(input);
		// clientFileDescriptors[0] = gmodInput.writeFd;
		final gmodOutput = @:await aquireReadSocket(output);
		clients[0] = {
			writeS: gmodInput,
			readS: gmodOutput
		};
		clientFiles[0] = {write: input, read: output};
		gmodOutput.on(Data, (x:Buffer) -> {
			readGmodBuffer(x, 0);
		});
		sendToServer(new ComposedGmDebugMessage(clientID, {id: 0}));
		switch (dapMode) {
			case ATTACH:
				sendToServer(new ComposedGmDebugMessage(intialInfo, {location: serverFolder, dapMode: Attach}));
			case LAUNCH(_):
				sendToServer(new ComposedGmDebugMessage(intialInfo, {location: serverFolder, dapMode: Launch}));
		}
		sys.io.File.saveContent(ready, "");
		return null;
	}

	function makeFifosIfNotExist(input:String, output:String) {
		if (!FileSystem.exists(input) && !FileSystem.exists(output)) {
			js.node.ChildProcess.execSync('mkfifo $input');
			js.node.ChildProcess.execSync('mkfifo $output');
			Fs.chmodSync(input, "744");
			Fs.chmodSync(output, "722");
		};
	}

	function readGmodBuffer(jsBuf:Buffer, clientNo:Int) {
		final messages = bytesProcessor.process(jsBuf, clientNo);
		for (msg in messages) {
			processDebugeeMessage(msg, clientNo);
		}
		// messages.iter(processDebugeeMessage);
		if (bytesProcessor.fillRequested) {
			clients[clientNo].writeS.write("\004\r\n");
		}
	}

	function processDebugeeMessage(debugeeMessage:ProtocolMessage, threadId:Int) {
		debugeeMessage.seq = 0; // must be done, or implementation has a fit
		switch (debugeeMessage.type) {
			case Event:
				final cmd = (cast debugeeMessage : Event<Dynamic>).event;
				trace('recieved event from debugee, $cmd');
				EventIntercepter.event(cast debugeeMessage, threadId);
				sendEvent(cast debugeeMessage);
			case Response:
				final cmd = (cast debugeeMessage : Response<Dynamic>).command;
				trace('recieved response from debugee, $cmd');
				sendResponse(cast debugeeMessage);
			case "gmdebug":
				final cmd = (cast debugeeMessage : GmDebugMessage<Dynamic>).msg;
				trace('recieved gmdebug from debugee, $cmd');
				processCustomMessages(cast debugeeMessage);
			default:
				throw "unhandled";
		}
	}

	override public function shutdown() {
		switch (dapMode) {
			case LAUNCH(child):
				child.write("quit\n");
				child.kill();
			default:
		}
		for (ind => client in clients) {
			client.writeS.write(composeMessage(new ComposedRequest(disconnect, {})));
			client.readS.end();
			client.writeS.end();
			FileSystem.deleteFile(clientFiles[ind].read);
			FileSystem.deleteFile(clientFiles[ind].write);
		}
		clients.resize(0);

		super.shutdown();
	}

	/**
	 * Async start server. Respond to attach request when attached.
	**/
	public function startServer(attachReq:Request<Dynamic>) {
		
		pokeServerNamedPipes(attachReq).handle((out) -> {
			switch (out) {
				case Success(_):
					final resp = attachReq.compose(attach);
					resp.send(this);
				case Failure(fail):
					trace(fail);
					final resp = attachReq.composeFail('attach fail ${fail.message}', {
						id: 1,
						format: 'Failed to attach to server ${fail.message}',
					});
					resp.send(this);
			}
		});
		
	}

	inline function composeMessage(msg:Dynamic):String {
		final json = Json.stringify(msg);
		final len = Bytes.ofString(json).length;
		return 'Content-Length: $len\r\n\r\n$json';
	}

	public inline function sendToAll(msg:Dynamic) {
		final msg = composeMessage(msg);
		for (client in clients) {
			client.writeS.write(msg);
		}
	}

	public inline function sendToServer(msg:Dynamic) {
		clients[0].writeS.write(composeMessage(msg));
	}

	public inline function sendToClient(client:Int, msg:Dynamic) {
		clients[client].writeS.write(composeMessage(msg));
	}

	public override function handleMessage(message:ProtocolMessage) {
		switch (message.type) {
			case Request:
				untyped trace('recieved request from client ${message.command}');
				requestRouter.route(cast message);
			default:
				trace("not a request from client");
		}
	}
}

typedef FileSocket = {
	readS:Socket,
	writeS:Socket,
}

typedef ClientFiles = {
	read:String,
	write:String
}

enum DapMode {
	ATTACH;
	LAUNCH(child:LaunchProcess);
}
