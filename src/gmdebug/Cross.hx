package gmdebug;


import haxe.display.Protocol.InitializeParams;
import haxe.io.BytesData;
import haxe.io.Bytes;
import tink.CoreApi.Ref;
#if lua
import gmdebug.lib.lua.Protocol.ProtocolMessage;
import gmod.libs.FileLib;
#elseif js
import vscode.debugProtocol.DebugProtocol.ProtocolMessage;
#end
import gmdebug.VariableReference;
import haxe.Json;
import haxe.io.Input;
import haxe.io.Path as HxPath;

class Cross {
	public static final FOLDER = "gmdebug";

	public static final INPUT = HxPath.join([FOLDER, "in.dat"]);

	public static final OUTPUT = HxPath.join([FOLDER, "out.dat"]);

	public static final READY = HxPath.join([FOLDER, "ready.dat"]);

	public static final CHECK = HxPath.join([FOLDER, "check.dat"]);

	public static final DATA = "data";

	public static final JIT = HxPath.join([FOLDER, "jitchoice.txt"]);

	@:nullSafety(Off)
	public static function readHeader(x:Input) {
		var raw_content = x.readLine();
		var skip = 0;
		var onlySkipped = true;
		for (i in 0...raw_content.length) {
			if (raw_content.charCodeAt(i) == 4) {
				skip++;
			} else {
				onlySkipped = false;
				break;
			}
		}
		#if lua
		if (onlySkipped) { // only happens on lua
			return null;
		}
		#end
		if (skip > 0) {
			// skipped x
			raw_content = raw_content.substr(skip);
		}
		var content_length = Std.parseInt(@:nullSafety(Off) raw_content.substr(15));
		
		final garbage = x.readLine();
		#if (lua && jsonDump)
		FileLib.Append(HxPath.join([FOLDER,"log.txt"]),raw_content + garbage + ';$content_length;');
		#end
		return content_length;
	}

	@:nullSafety(Off)
	public static function recvMessage(x:Input):MessageResult {
		var len = readHeader(x);
		if (len == null) {
			return ACK;
		}
		var dyn = x.readString(len, UTF8); // argh
		#if (lua && jsonDump)
		FileLib.Append(HxPath.join([FOLDER,"log.txt"]),dyn);
		#end
		return MESSAGE(Json.parse(dyn));
	}
}

enum CommMethod {
	Pipe;
	Socket;
}

enum MessageResult {
	ACK;
	MESSAGE(x:Dynamic);
}

enum abstract ExceptionBreakpointFilters(String) to String {
	// var all
	var gamemode;
	var entities;
}
