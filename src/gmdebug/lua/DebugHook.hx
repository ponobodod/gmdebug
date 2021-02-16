package gmdebug.lua;

import lua.Debug;
import gmod.libs.DebugLib;
import haxe.Constraints.Function;
using gmod.helpers.macros.CallStatic;

#if !gmddebug
extern class DebugHook {

    static inline final DEBUG_OFFSET = 2;

    static inline final HOOK_USED = 0;

    static inline function addHook(?fun:Function,?str:String=""):Void {
        Debug.sethook(fun,str);
    }

}

#else
@:native("_G.DebugHook")
extern class DebugHook {

    static inline final DEBUG_OFFSET = 3;

    static inline final HOOK_USED = 1;

    static final hooks:Map<String,FunctionHook>;

    @:native("addHook")
    static function _addHook(ident:String,?fun:Function,str:String):Void;

    static inline function addHook(?fun:Function,?str:String):Void {
        _addHook("gmdebug",fun,str);
    }

}

@:expose("DebugHook")
@:keep
private class DDebugHook {

    static final hooks:Map<String,FunctionHook> = getHooks();

    static function getHooks() {
        return DebugHook.hooks.or([]);
    }

    public static function addHook(ident:String,?fun:Function,?str="") {
        if (fun == null) {
            fun = (a,b) -> {};
        }
        if (!hooks.exists(ident)) {

            hooks.set(ident,{flagsMap: [],fun : cast fun});
        }
        hooks.get(ident).fun = fun;
        var flagMap = hooks.get(ident).flagsMap;
        if (str.indexOf("l") != -1) {
            flagMap.set(line,true);
        } else {
            flagMap.set(line,false);
        }
        if (str.indexOf("c") != -1) {
            flagMap.set(call,true);
        } else {
            flagMap.set(call,false);
        }
        var lineSet = false;
        var callSet = false;
        for (map in hooks) {
            if (map.flagsMap.get(line)) {
                lineSet = true;
            }
            if (map.flagsMap.get(call)) {
                callSet = true;
            }
        }
        switch [lineSet,callSet] {
            case [true,true]:
                Debug.sethook(hookFun,"cl");
            case [true,false]:
                Debug.sethook(hookFun,"l");
            case [false,true]:
                Debug.sethook(hookFun,"c");
            case [false,false]:
                Debug.sethook();
        }

    }

    static function hookFun(cur:HookState,currentLine:Int) {
        for (funHook in hooks) {
            final map = funHook.flagsMap;
            if (cur == Line && map.get(line)) {
                funHook.fun.callStatic(cur,currentLine);
                
            } else if (cur == Call && map.get(call)) {
                funHook.fun.callStatic(cur,currentLine);
                
            }
        }
    }

}

typedef FunctionHook = {
    flagsMap : Map<FlagsIndex,Bool>,
    fun : Dynamic
}

enum abstract FlagsIndex(Int) {
    var line;
    var call;
}

#end