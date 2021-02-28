package gmdebug.lua;

import gmdebug.lua.managers.BreakpointManager;
import gmdebug.lua.managers.FunctionBreakpointManager;
import gmdebug.lua.managers.VariableManager;
import gmdebug.lua.io.PipeSocket;
import gmdebug.lua.handlers.IHandler.HandlerResponse;
import gmdebug.Cross;
import gmdebug.GmDebugMessage;
import gmod.libs.GameLib;
import gmdebug.lua.HandlerContainer;
import haxe.io.Input;
import gmdebug.lua.io.DebugIO;
import gmod.libs.FileLib;
import gmod.Gmod;
import haxe.Constraints.Function;
import lua.Lua;
import gmod.libs.PlayerLib;
import gmod.stringtypes.Hook.GMHook;
import gmod.libs.HookLib;
import gmod.libs.TimerLib;
import gmdebug.lib.lua.Protocol.TStoppedEvent;
import gmdebug.lib.lua.Protocol.StopReason;
import gmdebug.composer.*;
import gmod.libs.DebugLib;

using Lambda;

using StringTools;
using gmdebug.composer.ComposeTools;
using tink.CoreApi;
using Safety;
using gmod.helpers.WeakTools;

#if client
import gmod.libs.ChatLib;
import gmod.libs.GuiLib;
#end

@:keep
class Debugee {

	public static final POLL_TIME = 0.1;

	public static var clientID:Int = 0; //go

	public static var state:DebugState = WAIT; //go

	public static var active:Bool = false; //keep

	public static var inpauseloop = false; //keep

	public static var dapMode:Null<DapModeStr>;

	public static var stepHeight(get,never):Int;
	
	public static extern inline function get_stepHeight():Int {
		return stackHeight - StackConst.STEP;
	}

	public static var baseDepth:Null<Int>;

	public static var stackHeight(get, never):Int;

	@:noCompletion
	public static function get_stackHeight():Int {
		for (i in 1...999999) {
			if (DebugLib.getinfo(i + 1, "") == null) {
				return i;
			}
		}
		throw "No stack height";
	}

	public static var tracing = false;

	static var hooksActive = false;

	public static var socket(default, set):Null<DebugIO>;

	// SENT BY DEBUG CLIENT
	public static var dest = "";

	@:noCompletion
	static function set_socket(sock) {
		G.previousSocket = sock;
		return socket = sock;
	}

	public static var shouldDebug = true;

	static var outputter:Null<Outputter>;

	static var sc:Null<SourceContainer>;

	static var vm:Null<VariableManager>;

	static var hc:Null<HandlerContainer>;

	static var bm:Null<BreakpointManager>;

	static var fbm:Null<FunctionBreakpointManager>;

	static final TIMEOUT_CONNECT = 10;

	static final TIMEOUT_CONFIG = 5;

	public static function start() {
		if (active)
			return false;
		try {
			socket = new PipeSocket();
		} catch (e) {
			socket = null;
		}
		if (socket == null) {
			return false;
		}
		trace("Connected to server...");
		active = true;
		final initEvent = new ComposedEvent(initialized);
		initEvent.send();
		#if debugdump
		FileLib.CreateDir("gmdebugdump");
		Gmod.collectgarbage("collect");
		Mri.DumpMemorySnapshot("gmdebugdump", "Before", -1);
		#end
		#if server
		hookPlayer();
		new ComposedEvent(continued, {threadId: 0, allThreadsContinued: true}).send();
		#end
		if (!startLoop()) {
			trace("Failed to setup debugger after timeout");
			return false;
		}
		DebugHook.addHook(DebugLoop.debugloop, "c");
		Exceptions.tryHooks();
		hooksActive = true;

		return true;
	}

	@:access(sys.net.Socket)
	public inline static function writeJson(json:String) { // x:Dynamic
		var str:String = untyped __lua__("{0} .. {1} .. {2} .. {3}", "Content-Length: ", json.length, "\r\n\r\n", json);
		socket.output.unsafe().writeString(str); // awful perfomance with non native writing
		socket.output.unsafe().flush();
	}

	static final ignores:Map<String, Bool> = [];

	// currently only on first lines for now. can expand to tracebacks.
	static inline function checkIgnoreError(_err:String) {
		return ignores.exists(_err);
	}

	static inline function ignoreError(_err:String) {
		ignores.set(_err, true);
	}

	#if server
	static function hookPlayer() {
		HookLib.Add(PlayerInitialSpawn, "gmdebug-newplayer", (ply, _) -> {
			new ComposedGmDebugMessage(playerAdded, {
				name: ply.Name(),
				playerID: ply.UserID()
			}).send();
		});
		HookLib.Add(PlayerDisconnected, "gmdebug-byeplayer", (ply) -> {
			new ComposedGmDebugMessage(playerRemoved, {
				playerID: ply.UserID()
			}).send();
		});
		for (ply in PlayerLib.GetAll()) {
			new ComposedGmDebugMessage(playerAdded, {
				name: ply.Name(),
				playerID: ply.UserID()
			}).send();
		}
	}
	#end

	@:expose("__gmdebugTraceback")
	static function traceback(err:Dynamic) {
		final _err = err;
		if (!shouldDebug) return err;
		if (checkIgnoreError(err))
			return _err;
		if (Debugee.inpauseloop || tracing) {
			trace('traceback failed... ${Debugee.inpauseloop} $tracing');
			return _err;
		}
		#if server
		if (!active && Jit.checkCanActivateJit()) {
			final result = Jit.jitCheck(err, _err);
			if (!result)
				return _err;
		}
		#end
		if (!hooksActive || !active)
			return _err;
		tracing = true;
		#if client
		GuiLib.EnableScreenClicker(true);
		GuiLib.ActivateGameUI();
		#end
		startHaltLoop(Exception,  StackConst.EXCEPT, err);
		tracing = false;
		return DebugLib.traceback(err);
	}

	inline static function parseInput(x:Input):MessageResult {
		socket.unsafe().output.writeString("\004");
		socket.unsafe().output.flush();
		return Cross.recvMessage(x);
	}

	static function recvMessage():RecvMessageResult {
		return try {
			switch (parseInput(socket.unsafe().input)) {
				case ACK:
					ACK;
				case MESSAGE(msg):
					MESSAGE(msg);
			}
		} catch (e:String) {
			if (e == "Error : timeout") {
				RecvMessageResult.TIMEOUT;
			} else {
				ERROR(e);
			}
		}
	}

	public static function poll() {
		if (socket == null)
			return;
		try {
			final msg = switch (recvMessage()) {
				case ACK | TIMEOUT:
					return;
				case MESSAGE(msg):
					msg;		
				case ERROR(s):
					throw s;
			}
			switch (chooseHandler(msg)) {
				case DISCONNECT:
					abortDebugee();
				case WAIT | CONTINUE | CONFIG_DONE:
			}
		} catch (e:haxe.Exception) {
			trace(e.toString());
		}
		
	}

	public static function main() {
		DebugHook.addHook();
		if (G.previousSocket != null) {
			G.previousSocket.close();
		}
		vm = new VariableManager();
		sc = new SourceContainer();
		outputter = new Outputter(vm);
		bm = new BreakpointManager();
		fbm = new FunctionBreakpointManager();
		hc = new HandlerContainer(vm,bm,fbm);
		DebugLoop.init(bm,sc,fbm);
		FileLib.CreateDir("gmdebug");
		#if server
		GameLib.ConsoleCommand("sv_timeout 999999\n");
		#elseif client
		Gmod.RunConsoleCommand("cl_timeout", 999999);
		#end
		#if client
		Jit.init();
		#end
		TimerLib.Create("gmdebug-start", 3, 0, () -> {
			#if server
			Jit.jitActivate();
			#end
			try {
				start();
			} catch (ee) {
				socket.run((sock) -> sock.close());
				trace('closed socket on error ${ee.toString()}');
				throw ee;
			}
		});
		TimerLib.Create("report-profling", 3, 0, () -> {
			DebugLoopProfile.report();
		});
		var pollTime = 0.0;
		HookLib.Add(GMHook.Think, "gmdebug-poll", () -> {
			if (Gmod.CurTime() > pollTime) {
				pollTime = Gmod.CurTime() + POLL_TIME;
				shouldDebug = false;
				poll();
				shouldDebug = true;
			}
		});
	}

	public static function normalPath(x:String):String {
		if (x.charAt(0) == "@") {
			x = @:nullSafety(Off) x.substr(1);
		}
		x = '$dest$x';
		return x;
	}

	public static function startHaltLoop(reason:StopReason, bd:Int, ?txt:String) {
		if (Debugee.inpauseloop) return;
		Debugee.inpauseloop = true;
		baseDepth = bd;
		final tstop:TStoppedEvent = {
			threadId: Debugee.clientID,
			allThreadsStopped: false,
			reason: reason,
			text: txt
		}
		var e = new ComposedEvent(stopped, tstop);
		e.send();
		trace("HALT LOOP");
		haltLoop();
	}

	#if debugdump
	@:expose("stopDump")
	public static function stopDump() {
		Gmod.collectgarbage("collect");
		Mri.DumpMemorySnapshot("gmdebugdump", "after", -1);
		Mri.DumpMemorySnapshotComparedFile("gmdebugdump", "Compared", -1, "gmdebugdump/LuaMemRefInfo-All-[]-[before].txt",
			"gmdebugdump/LuaMemRefInfo-All-[]-[after].txt");
	}
	#end

	static function abortDebugee() {
		DebugHook.addHook();
		socket.run((sock) -> {
			sock.close();
			socket = null;
		});
		hooksActive = false;
		socket = null;
		active = false;
		trace("Debugging aborted");
		Exceptions.unhookGamemodeHooks();
		Exceptions.unhookEntityHooks();
	}

	static function startLoop() {
		var success = false;
		final timeoutTime = Gmod.SysTime() + TIMEOUT_CONFIG;
		while (Gmod.SysTime() < timeoutTime) {
			final msg = switch (recvMessage()) {
				case ACK | TIMEOUT:
					continue;
				case MESSAGE(msg):
					msg;		
				case ERROR(s):
					throw s;
			}
			switch (chooseHandler(msg)) {
				case WAIT | CONTINUE:
				case DISCONNECT:
					abortDebugee();
					success = false;
					break;
				case CONFIG_DONE:
					success = true;
					break;
				
			}
		}
		return success;
	}


	static function haltLoop() {
		while (true) {			
			final msg = switch (recvMessage()) {
				case ACK | TIMEOUT:
					continue;
				case MESSAGE(msg):
					msg;		
				case ERROR(s):
					throw s;
			}
			switch (chooseHandler(msg)) {
				case WAIT | CONFIG_DONE:
				case CONTINUE:
					break;
				case DISCONNECT:
					abortDebugee();
					break;
			}
		}
		Debugee.inpauseloop = false;
	}

	static function chooseHandler(incoming:{type:String}):HandlerResponse {
		return switch (incoming.type) {
			case null:
				throw "message sent to us had a null type";
			case "gmdebug":
				CustomHandlers.handle(cast incoming);
				WAIT; // this is a safe option in all scenarios.
			case MessageType.Request:
				hc.handlers(cast incoming);
			default:
				throw "message sent to us had an unknown type";
		}
	}

	public static function fullPathToGmod(fullPath:String):Option<GmodPath> {
		return if (fullPath.contains(Debugee.dest)) {
			var result = fullPath.replace(Debugee.dest, "");
			result = "@" + result;
			Some(cast result);
		} else {
			None;
		}
	}
}

typedef LineMap = Map<Int, Bool>;

// TODO
@:native("_G") private extern class G {
	static var previousSocket:Null<DebugIO>;
}

enum DebugState {
	WAIT;
	STEP(targetHeight:Null<Int>);
	OUT(outFunc:Function, lowestLine:Int,targetHeight:Int);
}

enum RecvMessageResult {
	TIMEOUT;
	ACK;
	ERROR(s:String);
	MESSAGE(msg:Dynamic);

}