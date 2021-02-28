package gmdebug.lua;

import lua.Debug;
import gmod.stringtypes.Hook.GMHook;
import lua.Lua;
import haxe.Constraints.Function;
import gmod.libs.HookLib;
import gmod.libs.Scripted_entsLib;
import gmod.Gmod;
import haxe.ds.ObjectMap;

using Safety;

class Exceptions {
	public static final exceptFuncs = getexceptFuncs();

	public static final debugNames:ObjectMap<Dynamic, String> = new ObjectMap<Dynamic,String>();

	static final oldFuncs = getoldFuncs();

	static function getexceptFuncs():ObjectMap<Dynamic, Int> {
		if (G.exceptFuncs == null) {
			G.exceptFuncs = new ObjectMap<Dynamic, Int>();
		}
		return G.exceptFuncs;
	}

	static function getoldFuncs():Array<Function> {
		if (G.oldFuncs == null) {
			G.oldFuncs = new Array<Function>();
		}
		return G.oldFuncs;
	}

	static var hookTime:Float = 0;

	public static function tryHooks() {
		// if (Gmod.CurTime() > hookTime) {
		// 	hookTime = Gmod.CurTime() + 0.5;
			hookGamemodeHooks();
			hookEntityHooks();
		// }
	}

	public static function hookOnChange() {
		// HookLib.Add(GMHook.Think, "gmdebug-enable-hooks", hookContinously);
	}

	public static inline function isExcepted(x:Function):Bool {
		return exceptFuncs.exists(x);
	}

	static function addExcept(x:Function):Function {
		var i = oldFuncs.push(x);
		var func = untyped __lua__("function (...) local success,vargs = xpcall(_G.__oldFuncs[{0}],{1},...) if success then return vargs else print(\"baddy bad!\", {2}) error(vargs,99) end end",
			i - 1,
			G.__gmdebugTraceback,
			debugNames.get(oldFuncs[i - 1])
			);
		// var func2 = (vargs:haxe.Rest<Dynamic>) -> {
		// 	final result = Lua.xpcall(G.oldFuncs[i - 1],G.__gmdebugTraceback,vargs.toArray());
		// 	return if (result.status) {
		// 		result.value;
		// 	} else {
		// 		Lua.print("Baddy bad! ",debugNames.get(G.oldFuncs[i - 1]));
		// 		Lua.error(result.value,99);
		// 		throw "lel";
		// 	}
		// }
		// func2;
		exceptFuncs.set(func, i - 1);
		return func;
	}

	static function getOldFunc(hook:Function) {
		var i = exceptFuncs.get(hook).unsafe();
		return oldFuncs[i];
	}

	public static function hookGamemodeHooks() {
		for (hookname => hook in HookLib.GetTable()) {
			for (ident => hooks in hook) {
				if (shouldExcept(hooks)) {
					debugNames.set(hooks,ident);
					HookLib.Add(hookname, ident, addExcept(hooks));
				}
			}
		}
		for (ind => gm in Gmod.GAMEMODE) {
			if (shouldExcept(gm)) {
				debugNames.set(gm,ind);
				Gmod.GAMEMODE[cast ind] = addExcept(gm);
			}
			
		}
		// untyped Gmod.GAMEMODE = createWrapperTable(Gmod.GAMEMODE);
	}

	// public static function 
	
	public static function createWrapperTable(target:AnyTable) {
		final wrapper:AnyTable = lua.Table.create();
		final meta:AnyTable = lua.Table.create();
		meta.__index = target;
		meta.__newindex = (_,ind,val) -> {
			final newVal:Dynamic = if (Gmod.TypeID(val) == TYPE_FUNCTION && shouldExcept(val)) {
				Lua.print("update ",ind);
				addExcept(val);
			} else {
				val;
			}
			target[ind] = newVal;
		}
		Lua.setmetatable(wrapper,meta);
		return wrapper;
	}

	public static function hookEntityHooks() {
		for (entName in Scripted_entsLib.GetList().keys()) {
			final entTbl = Scripted_entsLib.GetStored(entName);
			for (ind => val in entTbl.t) {
				if (shouldExcept(val)) {
					debugNames.set(val,ind);
					// trace(entTbl);
					entTbl.t[ind] = addExcept(val);
				}
			}
			// entTbl.t = cast createWrapperTable(entTbl.t);
		}
	}

	public static function hookPanels() {
		// TODO
	}

	static inline function shouldExcept(x:Dynamic) {
		return Lua.type(x) == "function" && !isExcepted(x);
	}

	static inline function shouldUnExcept(x:Dynamic) {
		return Lua.type(x) == "function" && isExcepted(x);
	}

	public static function unhookGamemodeHooks() {
		for (hookname => hook in HookLib.GetTable()) {
			for (ident => hooks in hook) {
				if (shouldUnExcept(hooks)) {
					HookLib.Add(hookname, ident, getOldFunc(hooks));
				}
			}
		}
		for (ind => gm in Gmod.GAMEMODE) {
			if (shouldUnExcept(gm)) {
				Gmod.GAMEMODE[ind] = getOldFunc(gm);
			}
		}
	}

	public static function unhookEntityHooks() {
		for (entName in Scripted_entsLib.GetList().keys()) {
			final entTbl = Scripted_entsLib.GetStored(entName);
			for (ind => val in entTbl.t) {
				if (shouldUnExcept(val)) {
					entTbl.t[ind] = getOldFunc(val);
				}
			}
		}
	}
}

@:native("_G")
private extern class G {
	@:native("__exceptFuncs")
	static var exceptFuncs:haxe.ds.ObjectMap<Dynamic, Int>;

	@:native("__oldFuncs")
	static var oldFuncs:Array<Function>;

	static function __gmdebugTraceback():Void;
}