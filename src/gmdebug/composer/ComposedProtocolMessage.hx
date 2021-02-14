package gmdebug.composer;

#if lua
import gmdebug.lua.Debugee;
#end
import haxe.Json;

class ComposedProtocolMessage {

	public var seq:Int = 0;

	public var type:MessageType;

	public function new(_type:MessageType) {
		type = _type;
	}

	#if lua
	public inline function send() {
		// final old = Gmod.SysTime();
		// trace("json start");
		var js = Json.stringify(this);
		// trace('json end ${Gmod.SysTime() - old}');
		// Debugee.writeJson(this);
		Debugee.writeJson(js);
	}

	public inline function sendtink(x:String) {
		Debugee.writeJson(x);
	}
	#end
}
