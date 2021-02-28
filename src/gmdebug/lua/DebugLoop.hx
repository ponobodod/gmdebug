package gmdebug.lua;

import gmod.libs.JitLib;
import gmdebug.lua.managers.FunctionBreakpointManager;
import gmdebug.lua.handlers.HEvaluate;
import gmdebug.composer.*;
import lua.Debug;
import haxe.Constraints.Function;
import lua.Lua;
import gmod.libs.DebugLib;
import gmod.Gmod;
import gmdebug.lua.managers.BreakpointManager;
import gmdebug.lua.util.PrintTimer.print_time;

using gmod.helpers.WeakTools;
using Safety;
using tink.CoreApi;
using gmdebug.lua.GmodPath;

class DebugLoop {
	static var lineInfoFuncCache:haxe.ds.ObjectMap<Function, Bool> = new haxe.ds.ObjectMap();

	static var currentFunc:Null<haxe.Constraints.Function> = null;

	static var highestStackHeight:Float = Math.POSITIVE_INFINITY;

	static var escapeHatch:CatchOut = NONE;

	static var prevFunc:Null<Function> = null;

	static var prevStackHeight:Int = 0;

	static var lineSteppin:Bool = false;

	static var previousLength = null;

	static var lastLocalCount = 0;

	static var nextCheckStack = 1;

	static var curCheckStack = 0;

	static var tailLength = 0;

	static var tailLocals = 0;

	static var supressCheckStack:Option<Int> = None;

	static final STACK_LIMIT_PER_FUNC = 200;

	static final STACK_LIMIT = 65450; //could dynamically check this..

	static final STACK_DEBUG_TAIL = 500; //the stack can change up to this.. if not problems

	static final STACK_DEBUG_RELIEF_OURFUNCS = STACK_LIMIT_PER_FUNC * 2;

	static final STACK_DEBUG_RELIEF_TOLERANCE = STACK_LIMIT_PER_FUNC * 4;

	static final STACK_DEBUG_LIMIT = STACK_LIMIT - STACK_DEBUG_RELIEF_OURFUNCS - STACK_DEBUG_RELIEF_TOLERANCE;
	
	static final STACK_DEBUG_RESET_TOLERANCE = STACK_LIMIT_PER_FUNC * 10;

	static var bm:Null<BreakpointManager>;

	static var sc:Null<SourceContainer>;

	static var fbm:Null<FunctionBreakpointManager>;


	public static function init(bm:BreakpointManager,sc:SourceContainer,fbm:FunctionBreakpointManager) {
		DebugLoop.bm = bm;
		DebugLoop.sc = sc;
		DebugLoop.fbm = fbm;
	}

	inline static function nextCallStop(sinfo:SourceInfo, bp:Map<Int, Dynamic>) {
		var stop = false;
		for (k in bp.keys()) {
			if (k >= sinfo.linedefined && k <= sinfo.lastlinedefined) {
				stop = true;
				break;
			}
		}
		return stop;
	}

	public static extern inline function enableLineStep() {
		DebugHook.addHook(debugloop, "cl");
		lineSteppin = true;
	}

	public static extern inline function disableLineStep() {
		DebugHook.addHook(debugloop,"c");
		lineSteppin = false;
	}

	static inline function shouldStopLine(curFunc:Function, sh:Int) {
		final stackHeight = (sh < highestStackHeight);
		final isEscape = switch (escapeHatch) {
			case OUT(outFunc) if (outFunc != curFunc):
				true;
			default:
				false;
		}
		return stackHeight || isEscape;
	}

	static inline extern function currentStackHeight(func:Function) {
		return if (func != prevFunc) {
			prevStackHeight = Debugee.stackHeight;
			prevStackHeight;
		} else {
			prevStackHeight;
		}
	}

	static extern inline function debug_switchHookState(cur:HookState, func:Function, ?sinfo:SourceInfo) {
		if (sinfo != null && highestStackHeight != null && escapeHatch != null) {
			if (!lineSteppin && bm.unsafe().breakpointWithinRange(sinfo.source.gPath(), sinfo.linedefined,sinfo.lastlinedefined)) {
				final sh = currentStackHeight(func);
				if (sh <= highestStackHeight) {
					enableLineStep();
					highestStackHeight = sh;
				}
			} else if (cur == Line && currentStackHeight(func) == StackConst.MIN_HEIGHT_OUT && escapeHatch == NONE) {
				escapeHatch = OUT(func);
			} else if (cur == Line && shouldStopLine(func, currentStackHeight(func))) {
				escapeHatch = NONE;
				disableLineStep();
				highestStackHeight = Math.POSITIVE_INFINITY;
			}
		}
	}

	static extern inline function debug_checkBreakpoints(sinfo:SourceInfo, line:Int) {
		switch (bm.getBreakpointForLine(sinfo.source.gPath(),line)) {
			case null | {breakpointType : INACTIVE}:
			case {breakpointType : NORMAL}:
				Debugee.startHaltLoop(Breakpoint, StackConst.STEP_DEBUG_LOOP);
			case {breakpointType : CONDITIONAL(condFunc), id : bpID}:
				Gmod.setfenv(condFunc, HEvaluate.createEvalEnvironment(3 + DebugHook.HOOK_USED));
				switch (Util.runCompiledFunction(condFunc)) {
					case Error(err):
						final message = HEvaluate.translateEvalError(err);
						final resp = new ComposedEvent(breakpoint, {
							reason: Changed,
							breakpoint: {
								id: bpID,
								verified: false,
								message: 'Errored on run: $message'
							}
						});
						Lua.print('Conditional breakpoint in file ${sinfo.short_src}:${line} failed!');
						Lua.print('Error: $message');
						resp.send();
					case Success(val):
						if (val) {
							Debugee.startHaltLoop(Breakpoint,  StackConst.STEP_DEBUG_LOOP);
						}
				}
		}
		
	}

	static extern inline function debug_step(cur:HookState, func:Function, ?curLine:Int):Bool {
		return switch Debugee.state {
			case null: // otherwise lua dump. not good
				false;
			case WAIT:
				false;
			case STEP(target) if (target == null || Debugee.stackHeight <= target):
				trace('stepped $target ${Debugee.stackHeight}');
				Debugee.state = WAIT;
				disableLineStep();
				Debugee.startHaltLoop(Step,  StackConst.STEP_DEBUG_LOOP);
				true;
			case STEP(x):
				true;
			case OUT(outFunc, lowest,_) if (outFunc == func && curLine.unsafe() == lowest):
				Debugee.state = WAIT;
				Lua.print(outFunc, func);
				disableLineStep();
				Debugee.startHaltLoop(Step,  StackConst.STEP_DEBUG_LOOP);
				true;
			case OUT(outFunc, _,tarHeight) if (outFunc != func && Debugee.stackHeight <= tarHeight):
				Debugee.state = WAIT;
				Lua.print(outFunc, func);
				disableLineStep();
				Debugee.startHaltLoop(Step,  StackConst.STEP_DEBUG_LOOP);
				true;
			case OUT(outFunc, _):
				Lua.print(outFunc, func, curLine);
				true;
			default:
				false;
		}
	}

	static extern inline function debug_functionalBP(func:Function, cur:HookState) {
		if (cur == Call) {
			currentFunc = null;
		}
		// TODO make function breakpoints update when target changes.
		// RUns on entry and exit
		if (func != null && fbm != null && currentFunc == null) {
			if (fbm.functionBP.exists(func)) {
				Debugee.startHaltLoop(FunctionBreakpoint,  StackConst.STEP_DEBUG_LOOP);
			}
			currentFunc = func;
		}
	}

	public static extern inline function debug_stack_len() {
		var min:Int = 0;
		var max:Int = STACK_LIMIT;
		var middle:Int = Math.floor((max - min) / 2);
		while (true) {
			final stack = DebugLib.getinfo(middle);
			if (stack == null) {
				max = middle;
				middle = Math.floor((max - min) / 2) + min;
			} else {
				min = middle;
				middle = Math.floor((max - min) / 2) + min;
			}
			if (middle == min) {
				break;
			}
		}
		return middle;
	}

	static extern inline function debug_local_len(stack:Int) {
		var min:Int = 0;
		var max:Int = STACK_LIMIT_PER_FUNC;
		var middle:Int = Math.floor((max - min) / 2);
		while (true) {
			final local = DebugLib.getlocal(stack,middle);
			if (local.a == null) {
				max = middle;
				middle = Math.floor((max - min) / 2) + min;
			} else {
				min = middle;
				middle = Math.floor((max - min) / 2) + min;
			}
			if (middle == min) {
				break;
			}
		}
		return middle;
	}

	static extern inline function debug_local_len2(stack:Int) {
		var locals = 0;
		for (lindex in 1...STACK_LIMIT_PER_FUNC) {
			final local = DebugLib.getlocal(stack,lindex);
			if (local.a == null) {
				break;
			} else if (local.a.charAt(0) != '(') { //temporary variables do not count
				locals++;
			}
		}
		return locals;
	}
	
	static extern inline function debug_countLocals(start:Int,end:Int) {
		var locals = 0;
		for (sindex in start...end) {
			final stack = DebugLib.getinfo(sindex);
			if (stack == null) {
				break;
			}
			locals += debug_local_len2(sindex);
			locals++; //off by one :)
		}
		return locals;
	}

	static extern inline function debug_above500(len:Int) {
		final locals = if (previousLength != null) {
			if (len < previousLength) {
				//decrease tail size
				var stackDiff = previousLength - len;
				var localDiff = debug_countLocals(STACK_DEBUG_TAIL - stackDiff,STACK_DEBUG_TAIL);
				tailLength -= stackDiff;
				tailLocals -= localDiff;
				tailLocals;
			} else {
				//increase tail size
				var stackDiff = len - previousLength;
				var localDiff = debug_countLocals(STACK_DEBUG_TAIL,STACK_DEBUG_TAIL + stackDiff);
				tailLength += stackDiff;
				tailLocals += localDiff;
				tailLocals;
				
			}
		} else {
			var stackDiff = len - STACK_DEBUG_TAIL;
			var localDiff = debug_countLocals(STACK_DEBUG_TAIL,STACK_DEBUG_TAIL + stackDiff);
			tailLength = stackDiff;
			tailLocals = localDiff;
		}
		previousLength = len;
		return locals;
	}

	static extern inline function debug_checkBlownStack(cur:HookState) { 
		if (cur == Call) {
			
			if (curCheckStack >= nextCheckStack) {
				final len = debug_stack_len();
				final locals = if (len > STACK_DEBUG_TAIL) {
					debug_above500(len);
				} else { 
					previousLength = null;
					debug_countLocals(1,STACK_DEBUG_TAIL);
				}
				nextCheckStack = cast Math.max(Math.floor((STACK_DEBUG_LIMIT - locals) / STACK_LIMIT_PER_FUNC) - 1, 0);
				if (nextCheckStack <= 5 && supressCheckStack == None) {
					Debugee.startHaltLoop(Exception,  StackConst.STEP_DEBUG_LOOP, "Possible stack overflow detected...");
					supressCheckStack = Some(6);
				}
				switch (supressCheckStack) {
					case Some(x) if (nextCheckStack > x):
						supressCheckStack = None;
					default:
				}
				curCheckStack = 0;
			} else {
				curCheckStack++;
			}
		}
	}

	// TODO if having inline breakpoints, only use instruction count when necessary (i.e when running the line to step through) also granuality ect.
	public static function debugloop(cur:HookState, currentLine:Int) {
		if (!Debugee.shouldDebug || Debugee.tracing)
			return;
		debug_checkBlownStack(cur);
		DebugLoopProfile.profile("getinfo", true);
		final func = DebugLib.getinfo(DebugHook.DEBUG_OFFSET, 'f').func;
		final result = sc.sourceCache.get(func);
		final sinfo = if (result != null) {
			result;
		} else {
			final tmp = DebugLib.getinfo(DebugHook.DEBUG_OFFSET, 'S');
			sc.sourceCache.set(func, tmp);
			tmp;
		}
		DebugLoopProfile.profile("step");
		if (Exceptions.exceptFuncs != null && func != null && Exceptions.exceptFuncs.exists(func))
			return;
		final stepping = debug_step(cur, func, currentLine);
		DebugLoopProfile.profile("getbptable");
		final bpValid = if (bm != null && bm.valid())
				true;
			else
				false;
		DebugLoopProfile.profile("switchhookstate");
		if (!stepping && bpValid)
			debug_switchHookState(cur, func, sinfo);
		DebugLoopProfile.profile("checkBreakpoints");
		@:nullSafety(Off) if (cur == Line && bpValid)
			debug_checkBreakpoints(sinfo, currentLine);
		DebugLoopProfile.profile("functionalbp");
		debug_functionalBP(func, cur);
		DebugLoopProfile.resetprofile();
	}
}

private enum abstract HookState(String) {
	var Call = "call";
	var Line = "line";
	var _Return = "return";
}

typedef SourceInfo = {
	/**
		The line where the function definiton starts (where "function" is located).

		Option: S
	**/
	var linedefined:Int;

	/**
		The line the function definition ended (where "end" is located).

		Option: S
	**/
	var lastlinedefined:Int;

	/**
		The path to the file where the passed function is defined prepended by an @ (ex. "@lua/autorun/mytestfile.lua"). This will be the CompileString or RunString identifier if the function wasn't defined in a file, also prepended by an @.

		Option: S
	**/
	var source:String;

	/**
		The language used. Either "Lua" or "C".

		Option: S
	**/
	var what:gmod.structs.DebugInfo.What;

	/**
		The shortened name of the source (without the @). May be truncated if the source path is long.

		Option: S
	**/
	var short_src:String;
}

typedef FuncInfo = {
	/**
		Reference to the function that was passed in. If a stack level was specified, this will be the function at that stack level. 0 = debug.getinfo, 1 = function that called debug.getinfo, etc.

		Option: f
	**/
	var func:Function;
}

typedef SourceAndFuncInfo = FuncInfo & SourceInfo;

enum CatchOut {
	NONE;
	OUT(outFunc:Function);
}
