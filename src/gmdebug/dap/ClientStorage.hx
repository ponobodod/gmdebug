package gmdebug.dap;

import haxe.io.Bytes;
import haxe.Json;
import js.node.Fs;
import sys.FileSystem;

import js.node.Buffer;

using Lambda;

typedef ClientID = Int;

typedef ReadWithClientID = (buf:Buffer,id:Int) -> Void;
	
//DebugeeStorage
@:await
class ClientStorage {

	static final SERVER_ID = 0;

	final clients:Array<BaseConnected> = [];

	var disconnect = false;

	var gmodIDMap:Map<Int,Client> = [];

	final readFunc:ReadWithClientID;

	public function new(readFunc:ReadWithClientID) {
		this.readFunc = readFunc;

	}

	//TODO move
	inline function composeMessage(msg:Dynamic):String {
		final json = Json.stringify(msg);
		final len = Bytes.ofString(json).length;
		return 'Content-Length: $len\r\n\r\n$json';
	}

	@:async function makePipeSocket(loc:String,id:Int) {
		final data = haxe.io.Path.join([loc, Cross.DATA]);
		final input = haxe.io.Path.join([data, Cross.INPUT]);
		final output = haxe.io.Path.join([data, Cross.OUTPUT]);
		final ready = haxe.io.Path.join([data, Cross.READY]);
		final ps = new PipeSocket({read : output, write : input, ready : ready},
			(buf:Buffer) -> readFunc(buf,id)
		);
		final gay = @:await ps.aquire();
		trace("mega aquired");
		return ps;
	}


	@:async public function newClient(clientLoc:String, gmodID:Int, gmodName:String) {
		final clID = clients.length; 
		final pipesocket = @:await makePipeSocket(clientLoc,clID);
		final client = new Client(pipesocket,clID,gmodID,gmodName);
		clients.push(client);
		trace("client created");
		gmodIDMap.set(gmodID,client);
		return client;
	}

	@:async public function newServer(serverLoc:String) {
		final clID = SERVER_ID;
		final pipesocket = @:await makePipeSocket(serverLoc,clID);
		trace("Server created");
		final server = new Server(pipesocket, clID);
		clients[SERVER_ID] = server;
		return server;
	}

	function get(id:Int) {
		return clients[id];
	}

	public function sendServer(msg:Dynamic) {
		clients[SERVER_ID].sendRaw(composeMessage(msg));
	}

	public function sendClient(id:Int,msg:Dynamic) {
		if (id == SERVER_ID) {
			throw "Attempt to send to server....";
		}
		clients[id].sendRaw(composeMessage(msg));
	}

	public function getClients():Array<Client> {
		return cast clients.slice(1);
	}

	public function sendAll(msg:Dynamic) {
		final comp = composeMessage(msg);
		clients.iter((c) -> c.sendRaw(comp));
	}

	public function sendAny(id:Int,msg:Dynamic) {
		clients[id].sendRaw(composeMessage(msg));
	}

	public function sendAnyRaw(id:Int,str:String) {
		clients[id].sendRaw(str);
	}

	public function getByGmodID(id:Int) {
		return gmodIDMap.get(id);  
	}

	public function disconnectAll() {
		disconnect = true;
		clients.iter((c) -> c.disconnect());
	}
}
