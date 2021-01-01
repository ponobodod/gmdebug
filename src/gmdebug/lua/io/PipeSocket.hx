package gmdebug.lua;

import gmdebug.lua.LuaSocket.DebugIO;
import haxe.io.Encoding;
import lua.lib.luasocket.socket.TcpClient;
import haxe.io.Bytes;
import gmod.libs.FileLib;
import gmod.gclass.File;
import haxe.io.BytesInput;
import haxe.io.Input;
import haxe.io.Output;
import sys.net.Socket;

class PipeSocket implements DebugIO {
	public final input:PipeInput;

	public final output:PipeOutput;

	public function close() {
		input.close();
		output.close();
	}

	public function new() {
		if (!FileLib.Exists(Cross.READY, DATA)) {
			throw "Other process is not ready.";
		}
		FileLib.Delete(Cross.READY);
		input = new PipeInput();
		output = new PipeOutput();
	}
}

class PipeInput extends Input {
	final file:File;

	public function new() {
		if (!FileLib.Exists(Cross.INPUT, DATA)) {
			throw "Input pipe does not exist";
		}
		final f = FileLib.Open(Cross.INPUT, FileOpenMode.read, DATA);
		if (f == null)
			throw "Cannot open Input pipe for reading";
		file = f;
	}

	override function readByte():Int {
		return file.ReadByte();
	}
}

class PipeOutput extends Output {
	final file:File;

	public function new() {
		// if (!FileLib.Exists(Cross.OUTPUT,DATA)) { IT HANGS HERE :)
		//     throw "Output pipe does not exist";
		// }
		final f = FileLib.Open(Cross.OUTPUT, FileOpenMode.write, DATA);
		if (f == null)
			throw "Cannot open output pipe for reading";
		file = f;
	}

	override function close() {
		file.Close();
	}

	override function flush() {
		file.Flush();
	}

	override function writeString(s:String, ?encoding:Encoding) {
		file.Write(s);
	}

	// override function writeByte(c:Int) {
	//     file.WriteByte(c);
	// }
	// override function write(s:Bytes) {
	//     super.write(s);
	// }
}
