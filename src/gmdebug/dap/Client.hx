package gmdebug.dap;

import js.node.net.Socket;

class Client {

	public var clientID:Int;

	var gmodID:Int;
	
	final socket:FileSocket;

	var files:ClientFiles;

	var threadID:Int;

	var gmodName:String;

	public function new(fs:FileSocket,files:ClientFiles,gmodID:Int,gmodName:String) {
		socket = fs; 
		this.files = files; 
		this.gmodID = gmodID;
		this.gmodName = gmodName;
	}

	public function send() {

	}
}

private typedef FileSocket = {
	readS:Socket,
	writeS:Socket,
}

typedef ClientFiles = {
	read:String,
	write:String
}

private enum DebugeeClientType {
	SERVER;
	CLIENT(gmodPlayerID:Int);
}
