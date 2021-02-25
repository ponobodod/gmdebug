package gmdebug.dap;

import js.node.net.Socket;
class Client extends BaseConnected {
	
	public final gmodID:Int;

	public final gmodName:String;

	public function new(fs:PipeSocket, clientID:Int, gmodID:Int, gmodName:String) {
		super(fs,clientID);
		this.gmodID = gmodID;
		this.gmodName = gmodName;
	}
	
}


