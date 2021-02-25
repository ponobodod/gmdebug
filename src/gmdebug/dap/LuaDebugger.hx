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

	public var clientFiles:Array<ClientFiles>;

	public var dapMode:DapMode;

	public var serverFolder:String;

	public var clientsTaken:Map<Int, Bool>;

	var requestRouter:RequestRouter;

	var clientLocations:Array<String>;

	var bytesProcessor:BytesProcessor;

	var prevRequests:PreviousRequests;

	var clients:ClientStorage;

	public function new(?x, ?y) {
		super(x, y);
		clientLocations = [];
		serverFolder = null;
		clientsTaken = [];
		dapMode = ATTACH;
		commMethod = Pipe;
		bytesProcessor = new BytesProcessor();
		prevRequests = new PreviousRequests();
		clients = new ClientStorage(readGmodBuffer);
		requestRouter = new RequestRouter(this,clients,prevRequests);
		Node.process.on("uncaughtException", uncaughtException);
	}

	function uncaughtException(err:js.lib.Error, origin) {
		trace(err.message);
		trace(err.stack);
		this.shutdown();
	}

	@:async function playerAddedMessage(x:GMPlayerAddedMessage) {
		var success = false;
		for (ind => loc in clientLocations) {
			if (!clientsTaken.exists(ind)) {
				try {
					@:await playerTry(loc, x.playerID, x.name).eager();
					
					success = true;
					break;
				} catch (e) {
					trace('could not aquire in $loc');
				}	
			}
		}
		return success;
	}

	@:async function playerTry(clientLoc:String, gmodID:Int, playerName:String) {
		final cl = @:await clients.newClient(clientLoc,gmodID,playerName);
		// clients.sendClient(cl.clID,new ComposedGmDebugMessage(clientID, {id: cl.clID}));
		new ComposedEvent(thread, {
			threadId: cl.clID,
			reason: Started
		}).send(this);
		setupPlayer(cl.clID);
		return Noise;
		
	}

	function setupPlayer(clientID:Int) {
		clients.sendClient(clientID, new ComposedGmDebugMessage(intialInfo, {location: serverFolder,dapMode : Launch}));
		clients.sendClient(clientID, new ComposedGmDebugMessage(GmMsgType.clientID, {id: clientID}));
		prevRequests.get(setBreakpoints).run((msg) -> clients.sendClient(clientID,msg));
		prevRequests.get(setExceptionBreakpoints).run((msg) -> clients.sendClient(clientID,msg));
		prevRequests.get(setFunctionBreakpoints).run((msg) -> clients.sendClient(clientID,msg));
		clients.sendClient(clientID, new ComposedRequest(configurationDone, {}));
	}

	// todo
	function playerRemovedMessage(x:GMPlayerRemovedMessage) {
		new ComposedEvent(thread, {
			threadId: clients.getByGmodID(x.playerID).clID,
			reason: Exited
		}).send(this);
		clientsTaken.remove(clients.getByGmodID(x.playerID).clID);
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
				playerAddedMessage(cast x.body).handle((out) -> {
					switch (out) {
						case Success(true):
							trace("Whater a sucess");
						case Success(false):
							trace("Could not add a new player...");
						case Failure(fail):
							throw fail;
					}
				});
			case playerRemoved:
				playerRemovedMessage(cast x.body);
			case serverInfo:
				serverInfoMessage(cast x.body);
			case clientID | intialInfo:
				throw "dur";
		}
	}


	@:async function pokeServerNamedPipes(attachReq:GmDebugAttachRequest) {
		@:await clients.newServer(attachReq.arguments.serverFolder);
		clients.sendServer(new ComposedGmDebugMessage(clientID, {id: 0}));
		switch (dapMode) {
			case ATTACH:
				clients.sendServer(new ComposedGmDebugMessage(intialInfo, {location: serverFolder, dapMode: Attach}));
			case LAUNCH(_):
				clients.sendServer(new ComposedGmDebugMessage(intialInfo, {location: serverFolder, dapMode: Launch}));
		}
		return Noise;
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
			clients.sendAnyRaw(clientNo,"\004\r\n");
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
		clients.disconnectAll();
		super.shutdown();
	}

	/**
	 * Async start server. Respond to attach request when attached.
	**/
	public function startServer(attachReq:Request<Dynamic>) {
		
		pokeServerNamedPipes(attachReq).handle((out) -> {
			switch (out) {
				case Success(_):
					trace("Attatch success");
					final resp = attachReq.compose(attach);
					resp.send(this);
				case Failure(fail):
					trace(fail.message);
					final resp = attachReq.composeFail('attach fail ${fail.message}', {
						id: 1,
						format: 'Failed to attach to server ${fail.message}',
					});
					resp.send(this);
			}
		});
		
	}

	public function setClientLocations(a:Array<String>) {
		return clientLocations = a;
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
