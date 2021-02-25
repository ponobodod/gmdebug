package gmdebug.dap;

//BaseDebugee
abstract class BaseConnected {
    
    final socket:PipeSocket;

	var threadID:Int;

	public final clID:Int;

	public function new(fs:PipeSocket,clID:Int) {
		socket = fs;
		this.clID = clID;
	}

	

	public function sendRaw(x:String) {
		socket.write(x);
	}

	public function disconnect() {
		socket.end();
	}
    
}