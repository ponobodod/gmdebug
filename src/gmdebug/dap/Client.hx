package gmdebug.dap;

import js.node.net.Socket;

class Client {

	public var clientID:Int;

	var gmodID:Int;
	
	final socket:FileSocket;

	var threadID:Int;

	var gmodName:String;

	public function new(fs:FileSocket,gmodID:Int,gmodName:String) {
		socket = fs; 
		this.gmodID = gmodID;
		this.gmodName = gmodName;
	}

	public function sendRaw(x:String) {
		socket.write(x);
	}

	public function disconnect() {
			
		
	}

	
}


private enum DebugeeClientType {
	SERVER;
	CLIENT(gmodPlayerID:Int);
}
