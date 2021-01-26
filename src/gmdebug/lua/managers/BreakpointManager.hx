package gmdebug.lua.managers;

import gmdebug.lua.handlers.IHandler;
import haxe.Constraints.Function;

using gmdebug.lua.GmodPath;

class BreakpointManager {

	var breakLocsCache:Map<GmodPath, Map<Int, Bool>> = [];

	var breakpoints(default, null):Map<GmodPath, Map<Int, Breakpoint>> = [];

	var bpID:Int = 0;

	public function new() {
		
	}

	public function clearBreakpoints(source:String) {
		breakpoints.set(getRealPath(source),[]);
	}

	inline function getRealPath(source:String):GmodPath {
		return switch (Debugee.fullPathToGmod(source)) {
			case Some(v):
				v;
			case None:
				cast source;
		}
	}

	public function retrieveSourceLineInfo(source:GmodPath):Map<Int, Bool> {
		return switch (breakLocsCache.get(source)) {
			case null:
				var map:Map<Int, Bool> = [];
				breakLocsCache.set(source, map);
				map;
			case x:
				x.unsafe();
		}
	}

	function retrieveBreakpointTable(source:GmodPath):Map<Int,Breakpoint> {
		return switch (breakpoints.get(source)) {
			case null:
				var map:Map<Int, Breakpoint> = [];
				breakpoints.set(source, map);
				map;
			case x:
				x.unsafe();
		}
	}

	public function valid() {
		return breakpoints != null;
	}
	
	public function breakpointWithinRange(source:GmodPath,min:Int,max:Int) {
		final bpTable = breakpoints.get(source);
		if (bpTable == null) return false;
		for (k in bpTable.keys()) {
			if (k >= min && k <= max) {
				return true;
			}
		}
		return false;
	}

	public function getBreakpointForLine(source:GmodPath,line:Int):Null<Breakpoint> {
		final bp = breakpoints.get(source);
		return if (bp == null)
			null;
		else 
			bp.get(line);
	}

	public function newBreakpoint(source:Source,bp:SourceBreakpoint):Breakpoint {
		final status = switch (Debugee.fullPathToGmod(source.path)) { 
			case Some(v):
				breakpointStatus(v,bp.line);
			case None:
				NOT_VISITED;
		}
		final breakpoint = new Breakpoint(bpID++,source,bp,status);
		if (breakpoint.breakpointType != INACTIVE) {
			final map = retrieveBreakpointTable(getRealPath(source.path));
			map.set(breakpoint.line,breakpoint);
		}
		return breakpoint;
	}

	function breakpointStatus(path:GmodPath,line:Int):LineStatus {
		final possibles = breakLocsCache.get(path);
		return switch (possibles) {
			case null:
				NOT_VISITED;
			case _.get(line) => null:
				UNKNOWN;
			case _.get(line) => false:
				NOT_ACTIVE;
			case _.get(line) => true:
				CONFIRMED;
		}

	}
	
}

enum LineStatus {
	UNKNOWN;
	NOT_ACTIVE;
	NOT_VISITED;
	CONFIRMED;

}

class Breakpoint {

	public final breakpointType:BreakpointType;

	public final id:Int;

	public final line:Int;

	public final path:String;

	public var verified(default,null):Bool = false;

	public var message(default,null):String = "";

	public function new(id:Int,source:Source,bp:SourceBreakpoint,ls:LineStatus) {
		this.id = id;
		path = source.path;
		line = bp.line;
		switch (ls) {
			case NOT_VISITED:
				verified = true;
				message = "This file has not been visited by running code yet.";
			case UNKNOWN:
				verified = true;
				message = "This breakpoint could not be confirmed.";
			case NOT_ACTIVE:
				verified = false;
				message = "Lua does not consider this an active line.";
			case CONFIRMED:
				verified = true;
			
		}

		breakpointType = if (bp.condition == null) {
			NORMAL;
		} else {
			final eval = Util.processReturnable(bp.condition);
			switch (Util.compileString(eval, "Gmdebug Conditional BP: ")) {
				case Error(err):
					verified = false;
					message = 'Failed to compile condition $err';
					INACTIVE;
				case Success(compiledFunc):
					CONDITIONAL(compiledFunc);
			}
		}
	}
}

enum BreakpointType {
	INACTIVE;
	NORMAL;
	CONDITIONAL(condition:Function);
}
