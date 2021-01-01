package gmdebug.lua;

import gmdebug.lua.managers.VariableManager;
import gmdebug.lua.handlers.HNext.HStepIn;
import gmdebug.lua.handlers.HStackTrace;
import gmdebug.RequestString.AnyRequest;
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
	static var breakpointM:BreakpointManager = new BreakpointManager();

	var handlerMap:HashMap<AnyRequest, IHandler<Request<Dynamic>>> = [];

	public function new(vm:VariableManager) {
		handlerMap.set(_continue, new HContinue());
		handlerMap.set(disconnect, new HDisconnect());
		handlerMap.set(stackTrace, new HStackTrace());
		handlerMap.set(next, new HNext());
		handlerMap.set(pause, new HPause());
		handlerMap.set(stepIn, new HStepIn());
		handlerMap.set(stepOut, new HStepOut());
	}

	public function handlers(req:Request<Dynamic>):HandlerResponse {
		return handlers.get(req.command).handle();
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
