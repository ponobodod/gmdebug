package gmdebug.dap;

import haxe.io.Bytes;
import haxe.Json;
import js.node.Fs;
import sys.FileSystem;

import js.node.Buffer;


using Lambda;



typedef ClientID = Int;

typedef ReadWithClientID = (buf:Buffer,id:Int) -> Void;
	
@:async
class ClientStorage {

	static final SERVER_ID = 0;

	final clients:Array<Client> = [];

	final clientGmodNameMap:Map<ClientID,String> = [];

	var disconnect = false;

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


	@:await public function newClient(clientID:Int) {
		final data = haxe.io.Path.join([clientLoc, Cross.DATA]);
		final input = haxe.io.Path.join([data, Cross.INPUT]);
		final output = haxe.io.Path.join([data, Cross.OUTPUT]);
		final ready = haxe.io.Path.join([data, Cross.READY]);
		final ps = new PipeSocket({read : input, write : output, ready : ready},(buf:Buffer) -> {
				readFunc(buf,id);
		});
		@:await ps.aquire();
		final client = new Client();
		clients.push(client);
		new ComposedEvent(thread, {
			threadId: clientID,
			reason: Started
		}).send();
		
	}

	public function get(id:Int) {
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

	public function disconnectAll() {
		disconnect = true;
		clients.iter((c) -> c.disconnect());
	}
}
