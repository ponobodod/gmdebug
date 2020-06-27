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
import gmdebug.Cross.recvMessage;
import gmdebug.Cross;
using tink.CoreApi;
using gmdebug.ComposeTools;
import haxe.io.Path;

typedef FileSocket = {
    readS : Socket,
    writeS : Socket,
}

typedef ClientFiles = {
    read : String,
    write : String

}

@:keep @:await class LuaDebugger extends DebugSession {

    public static final commMethod:CommMethod = Pipe;

    public static var inst(default,null):LuaDebugger;

    public static var luaServer:Null<Server>;

    public static var clients:Array<FileSocket> = []; //0 = server.

    public static var clientFiles:Array<ClientFiles> = [];
    
    public static var mapClientName:Map<Int,String> = [];

    static var mapClientID:Map<Int,Int> = [];
    

    public var serverFolder:String;

    public var clientLocations:Array<String>; 

    public var clientsTaken:Map<Int,Bool>;

    public function new(?x,?y) {
	super(x,y);
	inst = this;
	clientLocations = [];
	serverFolder = null;
	clientsTaken = [];
	Node.process.on("uncaughtException", stoopidCompiler);
    }

    function stoopidCompiler(err:js.lib.Error,origin) {
	trace(err.message);
	trace(err.stack);
	 
	this.shutdown();
    }

    function recvMussage(input:BytesInput,?remaining:Int):RecvMessageResponse {
        //need to conjoin and parse here, lol....
        if (remaining == null) {remaining = Cross.readHeader(input);}
        var bufRemaining = input.length - input.position;
        if (remaining > bufRemaining) { 
            var str = input.readString(bufRemaining,UTF8);
            remaining -= bufRemaining;
            return Unfinished(str,remaining);
        } else {
            var str = input.readString(remaining,UTF8);
            return Completed(str);
        }   
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
	read.sock.on(Data,(x:Buffer) -> {
	    readGmodBuffer(x,number);
	});
	clients.push({
	    readS: read.sock,
	    writeS: write.sock,
	});
	
	clientFiles[number] = {write : write.file,read : read.file}; 
	sys.io.File.saveContent(ready,"");
	write.sock.write("\004\r\n");
	new ComposedEvent(thread,{
	    threadId : number,
	    reason : Started
	}).send();
	mapClientName.set(number,playerName);
	mapClientID.set(number,clientNo);
	sendToClient(number,new ComposedGmDebugMessage(intialInfo,{location : clientLoc})); 
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
    
    
    function processCustomMessages(x:GmDebugMessage<Dynamic>) {
        trace("custom message");
        switch (x.msg) {
            case playerAdded:

                playerAddedMessage(cast x.body);
            case playerRemoved:
                playerRemovedMessage(cast x.body);
            case clientID | intialInfo:
                throw "dur";
        }
    }

    @:async function aquireReadSocket(out:String) { //
        final open = Promisify.promisify(Fs.open);
        var fd = @:await open(out,cast Fs.constants.O_RDONLY | Fs.constants.O_NONBLOCK).toPromise();
        return {sock : new Socket({fd : fd,writable: false}),file : out};
    }

    static var clientFileDescriptors:Array<Int> = [];



    @:async function aquireWriteSocket(inp:String):{sock : Socket, file : String } {
        final open = Promisify.promisify(Fs.open);
        var fd = @:await open(inp,cast Fs.constants.O_RDWR | Fs.constants.O_NONBLOCK).toPromise();
        trace(fd);
        return {sock : new Socket({fd : fd,readable: false}),file : inp};
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
            writeS : gmodInput.sock,
            readS : gmodOutput.sock
        };
	clientFiles[0] = {write : gmodInput.file,read : gmodOutput.file}; 
        gmodOutput.sock.on(Data,(x:Buffer) -> {
            readGmodBuffer(x,0);
        });
        sendToServer(new ComposedGmDebugMessage(clientID,{id : 0}));
	sendToServer(new ComposedGmDebugMessage(intialInfo,{location : serverFolder})); 
        sys.io.File.saveContent(ready,"");
        trace("beforre suceed");
        return null;
    }

    static var oldbuffers:Array<ConjoinedPacket> = [];

    static var prevResults:Array<Null<RecvMessageResponse>> = [];

    static var requestFill = false;

    //Todo : see if skipacks or the cross actually skips bad data
    function skipAcks(x:BytesInput):Bool {
        for (_ in x.position...x.length) {
            final byt = x.readByte();
            if (byt != 4) {
                x.position--;
                return true;
            } else {
                requestFill = true;
            }
        }
        return false;
        
    }

    function makeFifosIfNotExist(input:String,output:String) {
        if (!FileSystem.exists(input) && !FileSystem.exists(output)) {
            ChildProcess.execSync('mkfifo $input');
            ChildProcess.execSync('mkfifo $output');
	    Fs.chmodSync(input,"744");
	    Fs.chmodSync(output,"722");
        };
    }

    function readGmodBuffer(buf:Buffer,clientNo:Int) {
        requestFill = false;
        final messages:Array<ProtocolMessage> = [];
        final bytes = switch oldbuffers[clientNo] {
            case null:
                oldbuffers[clientNo] = NONE;
                buf.hxToBytes();
            case CONJOIN(old):
                final curbytes = buf.hxToBytes();
                final conjoin = Bytes.alloc(old.length + curbytes.length);
                conjoin.blit(0,old,0,old.length);
                conjoin.blit(old.length,curbytes,0,curbytes.length);
                oldbuffers[clientNo] = NONE;
                conjoin;
            case NONE:
                buf.hxToBytes();
        }
        final inp:BytesInput = new BytesInput(bytes);
        var lastgoodpos = 0;
        final prevResult = prevResults[clientNo];
        try {
            while (inp.position != inp.length
                && skipAcks(inp)) {
                final result = switch (prevResult) {
                    case null | Completed(_):
                        recvMussage(inp);
                    case Unfinished(_, remaining):
                        recvMussage(inp,remaining);
                }
                prevResults[clientNo] = switch [prevResult,result] {
                    case [Unfinished(prevString,_), x = Completed(curString)]:

                        trace(prevString + curString);
                        messages.push(Json.parse(prevString + curString));
                        x;
                    case [_,x = Completed(str)]:
                        trace(str);
                        messages.push(Json.parse(str));
                        x;
                    case [Unfinished(prevString,_),Unfinished(curString,remain)]:
                        Unfinished(prevString + curString,remain);
                    case [_,x = Unfinished(_,_)]:
                        x; 
                }
            }
        } catch (e:haxe.io.Eof) { 
            lastgoodpos = inp.position; 
            prevResults[clientNo] = null;
            oldbuffers[clientNo] = CONJOIN(bytes.sub(lastgoodpos,bytes.length - lastgoodpos));
            trace("conjoining");
        } catch (e:String) {
            lastgoodpos = inp.position; 
            prevResults[clientNo] = null;
            oldbuffers[clientNo] = CONJOIN(bytes.sub(lastgoodpos,bytes.length - lastgoodpos));
            trace(e);
            trace("conjoining"); 
        } catch (e) {
            trace(e.details());
            trace("could not recieve packet");
            shutdown();
            throw e;
        }
        if (messages.length > 1) trace("BIG PACKET");
        for (msg in messages) {
            msg.seq = 0; //must be done, or implementation has a fit
            // trace(msg);
            switch (msg.type) {
                case Event:
                    sendEvent(cast msg);
                case Response:
                    sendResponse(cast msg);
                case "gmdebug":
                    processCustomMessages(cast msg);
                default:
                    trace("bad...");
                    throw "unhandled";
            }
        }
        if (requestFill) {
            clients[clientNo].writeS.write("\004\r\n");
        }
    }

    /**
       Kill all clients
    **/
    function endAll() {
        for (client in clients) {
            client.readS.end();
            client.writeS.end();
        }
	
        clients.resize(0);
    }

    override public function shutdown() {
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
    public function startServer(commMethod:CommMethod,attachReq:AttachRequest) {
        switch (commMethod) {
            case Socket:
                luaServer = Net.createServer((sock) -> {
                    final luaDebug = sock;
                    sock.setKeepAlive(true);
                    clients[0] = {
                        writeS : luaDebug,
                        readS : luaDebug
                    }
                    var aresp = attachReq.compose(RequestString.attach);
                    aresp.send();
                    luaDebug.addListener(Error,(list:js.lib.Error) -> {trace(list); trace(list.message); throw "no..";});
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
        trace(clients);
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

enum RecvMessageResponse {
    Completed(x:String);
    Unfinished(x:String,remaining:Int);
}

enum ConjoinedPacket {
    NONE;
    CONJOIN(old:haxe.io.Bytes);
    // FINISH(remaininglen:Int,prev:String);
}

