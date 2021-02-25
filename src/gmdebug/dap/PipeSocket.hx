package gmdebug.dap;

import sys.FileSystem;
import js.node.Fs;
import js.node.util.Promisify;
import tink.CoreApi.Noise;
import js.node.net.Socket;
using tink.CoreApi;

typedef PipeSocketLocations = {
	read:String, 
	write:String,
	ready:String
}
	
typedef ReadFunc = (buf:js.node.Buffer) -> Void;

@:await
class PipeSocket {

    var writeS:Socket;

    var readS:Socket;

	final locs:PipeSocketLocations;
    
    var aquired:Bool = false;

    final readFunc:ReadFunc;

    //no async new functions
    public function new(locs:PipeSocketLocations,readFunc:ReadFunc) {
		this.locs = locs;
        this.readFunc = readFunc;
    }

    @:async public function aquire() {
		makeFifosIfNotExist(locs.read, locs.write);
        readS = @:await aquireReadSocket(locs.read); 
		writeS = @:await aquireWriteSocket(locs.write);
		sys.io.File.saveContent(locs.ready, "");
		writeS.write("\004\r\n");
		readS.on(Data,readFunc);
        aquired = true;
		trace("Aquired socket...");
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

    @:async function aquireReadSocket(out:String) { //
		final open = Promisify.promisify(Fs.open);
		var fd = @:await open(out, cast Fs.constants.O_RDONLY | Fs.constants.O_NONBLOCK).toPromise();
		return new Socket({fd: fd, writable: false});
	}

	@:async function aquireWriteSocket(inp:String) {
		final open = Promisify.promisify(Fs.open);
		var fd = @:await open(inp, cast Fs.constants.O_RDWR | Fs.constants.O_NONBLOCK).toPromise();
		trace(fd);
		return new Socket({fd: fd, readable: false});
	}

    public function write(chunk:Dynamic) {
        writeS.write(chunk);
    }

    public function end() {
        readS.end();
        writeS.end();
        FileSystem.deleteFile(locs.read);
		FileSystem.deleteFile(locs.write);
    }

}