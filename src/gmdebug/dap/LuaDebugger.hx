package gmdebug.dap;

import js.Node;
import js.Syntax;
import js.node.Process;
import haxe.ValueException;
import sys.FileSystem;
import js.node.ChildProcess;
import gmdebug.ComposedMessage;
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
using gmdebug.ComposeTools;
import gmdebug.GmDebugMessage;
import haxe.io.Path;
import js.node.child_process.ChildProcess;
using Lambda;

@:keep @:await class LuaDebugger extends DebugSession {

    public static final commMethod:CommMethod = Pipe;

    public static var inst(default,null):LuaDebugger;

    public static var clients:Array<FileSocket> = []; //0 = server.

    public static var clientFiles:Array<ClientFiles> = [];
    
    public static var dapMode:DapMode = ATTACH;

    static var autoLaunch:Bool = false;
    
    public static var mapClientName:Map<Int,String> = [];

    static var mapClientID:Map<Int,Int> = [];
    
    public var serverFolder:String;

    public var clientLocations:Array<String>; 

    public var clientsTaken:Map<Int,Bool>;

    var bytesProcessor:BytesProcessor;

    public function new(?x,?y) {
	super(x,y);
	inst = this;
	clientLocations = [];
	serverFolder = null;
	clientsTaken = [];
	bytesProcessor = new BytesProcessor();
	Node.process.on("uncaughtException", uncaughtException);
    }

    function uncaughtException(err:js.lib.Error,origin) {
	trace(err.message);
	trace(err.stack);
	this.shutdown();
    }


    function playerAddedMessage(x:GMPlayerAddedMessage) {
        for (ind => loc in clientLocations) {
	    if (!clientsTaken.exists(ind)) {
		try {
		    playerTry(loc,x.playerID,x.name);
		    clientsTaken.set(ind,true);
		    break;
		} catch (e) {
		    trace('can\'t aquire in $loc');
		}
	    }
        }
    }

    @:await function playerTry(clientLoc:String,clientNo:Int,playerName:String) {
	final data = haxe.io.Path.join([clientLoc,Cross.DATA]);
	final input = haxe.io.Path.join([data,Cross.INPUT]);
	final out = haxe.io.Path.join([data,Cross.OUTPUT]);
        makeFifosIfNotExist(input,out);
	final ready = haxe.io.Path.join([data,Cross.READY]);
	final read = @:await aquireReadSocket(out);
	final write = @:await aquireWriteSocket(input);
	final number = clients.length;
	// clientFileDescriptors[number] = write.writeFd;
	read.on(Data,(x:Buffer) -> {
	    readGmodBuffer(x,number);
	});
	clients.push({
	    readS: read,
	    writeS: write,
	});
	
	clientFiles[number] = {write : input,read : out}; 
	sys.io.File.saveContent(ready,"");
	write.write("\004\r\n");
	new ComposedEvent(thread,{
	    threadId : number,
	    reason : Started
	}).send();
	mapClientName.set(number,playerName);
	mapClientID.set(number,clientNo);
	sendToClient(number,new ComposedGmDebugMessage(intialInfo,{location : serverFolder})); 
	sendToClient(number,new ComposedGmDebugMessage(clientID,{id : number}));
    }


    //todo
    function playerRemovedMessage(x:GMPlayerRemovedMessage) {
	new ComposedEvent(thread,{
	    threadId : mapClientID.get(x.playerID) ,
	    reason : Exited
	}).send();
	clientsTaken.remove(mapClientID.get(x.playerID));
    }

    function serverInfoMessage(x:GMServerInfoMessage) {
	final sp = x.ip.split(":");
	final ip = if (x.isLan) {
	    js.Ip.address();
	} else {
	    sp[0];
	}
	final port = sp[1];
	js.node.ChildProcess.spawn('xdg-open steam://connect/$ip:$port',{shell : true});
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
        var fd = @:await open(out,cast Fs.constants.O_RDONLY | Fs.constants.O_NONBLOCK).toPromise();
        return new Socket({fd : fd,writable: false});
    }

    @:async function aquireWriteSocket(inp:String) {
        final open = Promisify.promisify(Fs.open);
        var fd = @:await open(inp,cast Fs.constants.O_RDWR | Fs.constants.O_NONBLOCK).toPromise();
        trace(fd);
        return new Socket({fd : fd,readable: false});
    }

    @:async function pokeServerNamedPipes(attachReq:AttachRequest) {
        if (!FileSystem.exists(haxe.io.Path.join([serverFolder,Cross.DATA]))) {
           throw "GmDebug is not running on given server";
        }
        final ready = haxe.io.Path.join([serverFolder,Cross.DATA,Cross.READY]);
        final input = haxe.io.Path.join([serverFolder,Cross.DATA,Cross.INPUT]);
        final output = haxe.io.Path.join([serverFolder,Cross.DATA,Cross.OUTPUT]);
        makeFifosIfNotExist(input,output);
        final gmodInput = @:await aquireWriteSocket(input);
        // clientFileDescriptors[0] = gmodInput.writeFd;
        final gmodOutput = @:await aquireReadSocket(output);
        clients[0] = {
            writeS : gmodInput,
            readS : gmodOutput
        };
	clientFiles[0] = {write : input,read : output}; 
        gmodOutput.on(Data,(x:Buffer) -> {
            readGmodBuffer(x,0);
        });
	sendToServer(new ComposedGmDebugMessage(clientID,{id : 0}));
	switch (dapMode) {
	    case ATTACH:
		sendToServer(new ComposedGmDebugMessage(intialInfo,{location : serverFolder,dapMode : Attach})); 
	    case LAUNCH(_):
		sendToServer(new ComposedGmDebugMessage(intialInfo,{location : serverFolder,dapMode : Launch})); 
	}
        sys.io.File.saveContent(ready,"");
        return null;
    }


    function makeFifosIfNotExist(input:String,output:String) {
        if (!FileSystem.exists(input) && !FileSystem.exists(output)) {
            js.node.ChildProcess.execSync('mkfifo $input');
            js.node.ChildProcess.execSync('mkfifo $output');
	    Fs.chmodSync(input,"744");
	    Fs.chmodSync(output,"722");
        };
    }

    
    function readGmodBuffer(jsBuf:Buffer,clientNo:Int) {
	final messages = bytesProcessor.process(jsBuf,clientNo);
	for (msg in messages) {
	    processDebugeeMessage(msg,clientNo);
	}
	// messages.iter(processDebugeeMessage);
        if (bytesProcessor.fillRequested) {
            clients[clientNo].writeS.write("\004\r\n");
        }
    }

    function processDebugeeMessage(debugeeMessage:ProtocolMessage,threadId:Int) {
	debugeeMessage.seq = 0; //must be done, or implementation has a fit
	// trace(debugeeMessage);
	switch (debugeeMessage.type) {
	    case Event:
		final event:Event<Dynamic> = cast debugeeMessage;
		final cmd = event.event;
		trace('evented, $cmd');
		Intercepter.event(event,threadId);
		sendEvent(event);
	    case Response:
		final cmd = (cast debugeeMessage : Response<Dynamic>).command;
		trace('responded, $cmd');
		sendResponse(cast debugeeMessage);
	    case "gmdebug":
		processCustomMessages(cast debugeeMessage);
	    default:
		trace("bad...");
		throw "unhandled";
	}
    }

    override public function shutdown() {
	switch (dapMode) {
	    case LAUNCH(child):
		child.stdin.write("quit\n");
		child.kill();
	    default:
	}
        for (ind => client in clients) {
	    client.writeS.write(composeMessage(new ComposedRequest(disconnect,{})));
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
    public function startServer(commMethod:CommMethod,attachReq:Request<Dynamic>) {
        switch (commMethod) {
            case Socket:
                final luaServer = Net.createServer((sock) -> {
                    final luaDebug = sock;
                    sock.setKeepAlive(true);
                    clients[0] = {
                        writeS : luaDebug,
                        readS : luaDebug
                    }
                    var aresp = attachReq.compose(RequestString.attach);
                    aresp.send();
                    luaDebug.addListener(Error,(list:js.lib.Error) -> {
			trace(list);
			trace(list.message);
			throw "Socket error";
		    });
                    sock.addListener(Error,(x) -> {
                        trace("could not recieve packet");
                        trace(x);
                        shutdown();
                        throw x;
                    });
                    sock.addListener(Data,(x) -> readGmodBuffer(x,0)); //TODO will not work....
                });
                luaServer.listen({
                    port: 56789,
                    host: "localhost",
                },() -> trace(luaServer.address()));
            case Pipe:
                pokeServerNamedPipes(attachReq).handle((out) -> {
                    switch (out) {
                        case Success(_):
                            trace("suceed");
                            final resp = attachReq.compose(attach);
                            resp.send();
                        case Failure(fail):
                            trace(fail);
                            final resp = attachReq.composeFail("attach fail",{
                                id: 1,
                                format: 'Failed to attach to server ${fail.message}',
                            });
                            resp.send();
                    }
                });

        }
    }

    inline function composeMessage(msg:Dynamic):String {
        trace("composing message");
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

    public inline function sendToClient(client:Int,msg:Dynamic) {
        clients[client].writeS.write(composeMessage(msg));
    }

    override function handleMessage(message:ProtocolMessage) {
        if (LuaDebugger.inst == null) LuaDebugger.inst = this;
        try {
            switch (message.type) {
                case Request:
                    untyped trace ('recieved message from client ${message.command}');
                    Handlers.handle(cast message);
                default:
                    trace("unhandled message from client");
            }
        } catch (e) {
            trace(e.details());
            shutdown();
        }
    }
}



typedef FileSocket = {
    readS : Socket,
    writeS : Socket,
}

typedef ClientFiles = {
    read : String,
    write : String

}

enum DapMode {
    ATTACH;
    LAUNCH(child:ChildProcess);
}