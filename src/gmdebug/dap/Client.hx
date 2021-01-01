package gmdebug.dap;

import js.node.net.Socket;

class Client {
	var socket:FileSocket;

	var files:ClientFiles;

	var threadName:Int;

	var clientName:String;

	public var debugeeID:Int;
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
