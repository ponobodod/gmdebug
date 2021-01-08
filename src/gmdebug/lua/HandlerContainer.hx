package gmdebug.lua;

import haxe.Exception;
import gmdebug.lua.managers.FunctionBreakpointManager;
import gmdebug.lua.handlers.HDisconnect;
import gmdebug.composer.RequestString;
import gmdebug.lua.managers.VariableManager;
import gmdebug.lua.handlers.*;
import haxe.ds.HashMap;
import gmdebug.lua.handlers.IHandler.HandlerResponse;
import gmdebug.composer.*;
import gmod.LuaArray;
import tink.Json;
import gmdebug.composer.*;
import haxe.ds.Option;
import lua.Table;
import lua.NativeStringTools;
import haxe.ds.ArraySort;
import gmod.libs.CoroutineLib;
import haxe.ds.BalancedTree;
import lua.Lua;
import haxe.Constraints.Function;
import gmod.gclass.Entity;
import lua.Table.AnyTable;
import gmod.libs.EntsLib;
import gmod.Gmod;
import lua.Debug;
import gmdebug.lua.managers.BreakpointManager;
import gmod.gclass.Player;
import gmod.libs.PlayerLib;
import gmdebug.lua.DebugLoop;
import gmod.libs.DebugLib;
import gmdebug.lib.lua.Protocol;

using gmdebug.composer.ComposeTools;

import String;

using Safety;
using gmod.PairTools;
using Lambda;

class HandlerContainer {

	var handlerMap:haxe.ds.StringMap<IHandler<Request<Dynamic>>> = new haxe.ds.StringMap();

	public function new(vm:VariableManager,bm:BreakpointManager,fbm:FunctionBreakpointManager) {
		handlerMap.set(_continue, new HContinue(vm));
		handlerMap.set(disconnect, new HDisconnect());
		handlerMap.set(stackTrace, new HStackTrace());
		handlerMap.set(next, new HNext());
		handlerMap.set(pause, new HPause());
		handlerMap.set(stepIn, new HStepIn());
		handlerMap.set(stepOut, new HStepOut());
		handlerMap.set(variables, new HVariables(vm));
		handlerMap.set(setBreakpoints,new HSetBreakpoints(bm));
		handlerMap.set(setFunctionBreakpoints,new HSetFunctionBreakpoints(fbm));
		handlerMap.set(setExceptionBreakpoints,new HSetExceptionBreakpoints());
		handlerMap.set(evaluate,new HEvaluate(vm));
		
	}

	public function handlers(req:Request<Dynamic>):HandlerResponse {
		final result = handlerMap.get(req.command);
		if (result == null) {
			throw new Exception('No such command ${req.command}');
		}
		return result.handle(req);
	}
}

typedef Item = {
	name:String,
	type:String,
	?value:String,
	?variablesReference:Int
}

enum abstract EvalCommand(String) from String {
	var profile;
}
