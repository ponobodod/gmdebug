package gmdebug.lua;

import gmod.Gmod;
import gmod.libs.FileLib;

using StringTools;

@:native("_G") private extern class G {
	static var gmdebugJit:Bool;
}

class Jit {
	public static var netJit = new gmod.net.NET_Server<"gmdebug_netJit", {}>();

	public static var jitActive = false;

	static final JIT_MESSAGE = "// To choose an option, type a choice below from the following, and then save this file.\n// (Y) - Begin debugging this error and wait for a connection (N) - Skip this error. (S) - Disable for this session (re-enable by typing gmdebugjit) \n// Delete this file to permenatley disable this feature, and create a file with this name, or type in gmdebugjit to reenable.";

	static var gmdebugJit(get, set):Bool;

	static inline function get_gmdebugJit():Bool {
		return switch (G.gmdebugJit) {
			case null:
				G.gmdebugJit = true;
				true;
			case x:
				x;
		}
	}

	static inline function set_gmdebugJit(x:Bool):Bool {
		return G.gmdebugJit = x;
	}

	public static var autostart = true;

	#if client
	public static function init() {
		netJit.signal.listen(() -> {
			jitActive = true;
			Exceptions.hookGamemodeHooks();
			Exceptions.hookEntityHooks();
		});
	}
	#end

	public static function jitCheck(err:String, traceback:String) {
		trace('Jit activated due to: $err');
		trace("To make a choice, open garrysmod/data/jitchoice.txt and type it in or remove this file to permenantley disable this feature and continue execution.");
		trace("Waiting for choice...");
		final msg = JIT_MESSAGE + "\n//Current error: \n//" + traceback.replace("\n", "\n//") + "\n";
		FileLib.Write(Cross.JIT, msg);
		var wait = Gmod.SysTime() + 1;
		while (FileLib.Exists(Cross.JIT, DATA)) {
			if (Gmod.SysTime() < wait)
				continue;
			wait = Gmod.SysTime() + 1;
			// trace("check");
			final jitFile = FileLib.Open(Cross.JIT, read, DATA);
			if (jitFile == null) {
				trace("cannot open");
				continue;
			}
			jitFile.Seek(msg.length);
			final str = jitFile.Read(2);
			if (str == null) {
				if (autostart && Debugee.start())
					return true;
			} else {
				final choice:JitChoices = str.replace("\n", "").replace("\r", "").toLowerCase();
				switch (choice) {
					case Yes:
						trace("YES!");
						if (Debugee.start())
							return true; // TODO cleanup the file handle on exit, moron
					case Skip:
						trace("NO.");
						return false;
					case Disable:
						gmdebugJit = false;
						return false;
					case x if (autostart):
						trace('invalid choice $x');
						FileLib.Write(Cross.JIT, msg);
						if (Debugee.start())
							return true; // TODO cleanup the file handle on exit, moron
					case x:
						trace('invalid choice $x');
						FileLib.Write(Cross.JIT, msg);
						// jitFile.Seek(1);
						// jitFile.Write(msg);
				}
			}
			jitFile.Close();
		}
		trace("file left plane of existence");
		return false;
	}

	public static inline function checkCanActivateJit() {
		return !jitActive && gmdebugJit && FileLib.Exists(Cross.JIT, DATA);
	}

	public static function jitActivate() {
		if (checkCanActivateJit()) {
			trace("activating jit");
			jitActive = true;
			Exceptions.hookGamemodeHooks();
			Exceptions.hookEntityHooks();
			#if server
			netJit.broadcast({});
			#end
		}
	}
}

enum abstract JitChoices(String) from String {
	var Yes = "y";
	var Skip = "n";
	var Disable = "s";
}
