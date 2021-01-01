package gmdebug.lua;

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

class Handlers {

    static var breakpointM:BreakpointManager = new BreakpointManager();

    static var storedVariables:Array<Null<Dynamic>> = [null];

    public static function handlers(req:Request<Dynamic>):HandlerResponse {
	if (req.command == "continue") {
	    storedVariables = [null];
	    return h_continue(req);
	}
	switch (req.command) {
	    case setBreakpoints:
		return breakpointM.handle(req);
	    case functionBreakpoints:
	    default: 
	}
        var h = handlerMap.get(req.command);
        if (h != null) {
	    final result = h(req);
	    if (result == CONTINUE) storedVariables = [null]; 
            return result;
        } else {
            throw new UnhandledResponse('Unhandled... ${req.command}');
        }
    }

}



typedef Item = {
    name : String,
    type : String,
    ?value : String,
    ?variablesReference : Int
}


typedef AddVar = {
    name : Dynamic, //std.string
    value : Dynamic,
    ?virtual : Bool,
    ?noquote : Bool,
    ?novalue : Bool
}

enum abstract EvalCommand(String) from String {
    var profile;
}
