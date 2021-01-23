package gmdebug.lua;

import haxe.Exception;
import gmdebug.lua.managers.FunctionBreakpointManager;
import gmdebug.lua.handlers.HDisconnect;
import gmdebug.composer.RequestString;
import gmdebug.lua.managers.VariableManager;
import gmdebug.lua.handlers.*;
import gmdebug.lua.handlers.IHandler.HandlerResponse;
import gmdebug.lua.managers.BreakpointManager;
import gmdebug.lib.lua.Protocol;
using gmdebug.composer.ComposeTools;

import String;

using Safety;
using gmod.PairTools;
using Lambda;

class HandlerContainer {

	var handlerMap:haxe.ds.StringMap<IHandler<Request<Dynamic>>> = new haxe.ds.StringMap();

	public function new(vm:VariableManager,bm:BreakpointManager,fbm:FunctionBreakpointManager) {
		handlerMap.set("_continue", new HContinue(vm));
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
		handlerMap.set(configurationDone,new HConfigurationDone());
		handlerMap.set(scopes,new HScopes());
		handlerMap.set(loadedSources,new HLoadedSources());		
	}

	public function handlers(req:Request<Dynamic>):HandlerResponse {
		final result = if (req.command == "continue") {
			handlerMap.get("_continue");
		} else {
			handlerMap.get(req.command);
		}
		if (result == null) {
			trace('No such command ${req.command}');
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
