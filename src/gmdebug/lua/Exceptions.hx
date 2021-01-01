package gmdebug.lua;

import gmod.Hook.GMHook;
import lua.Lua;
import haxe.Constraints.Function;
import gmod.libs.HookLib;
import gmod.libs.Scripted_entsLib;
import gmod.Gmod;

using Safety;
using gmod.PairTools;

class Exceptions {
	public static final exceptFuncs = getexceptFuncs();

	static final oldFuncs = getoldFuncs();

	static function getexceptFuncs():haxe.ds.ObjectMap<Dynamic, Int> {
		if (G.exceptFuncs == null) {
			G.exceptFuncs = new haxe.ds.ObjectMap<Dynamic, Int>();
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

	static function hookContinously() {
		if (Gmod.CurTime() > hookTime) {
			hookTime = Gmod.CurTime() + 0.5;
			hookGamemodeHooks();
			hookEntityHooks();
		}
	}

	public static function hookOnChange() {
		HookLib.Add(GMHook.Think, "enable-hooks", hookContinously);
	}

	public static inline function isExcepted(x:Function):Bool {
		return exceptFuncs.exists(x);
	}

	static function addExcept(x:Function):Function {
		var i = oldFuncs.push(x);
		var func = untyped __lua__("function (...) local success,vargs = xpcall(_G.__oldFuncs[{0}],{1},...) if success then return vargs else error(vargs,99) end end",
			i
			- 1,
			G.__gmdebugTraceback);
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
					HookLib.Add(hookname, ident, addExcept(hooks));
				}
			}
		}
		for (ind => gm in Gmod.GAMEMODE) {
			if (shouldExcept(gm)) {
				Gmod.GAMEMODE[ind] = addExcept(gm);
			}
		}
	}

	public static function hookEntityHooks() {
		for (entName in Scripted_entsLib.GetList().keys()) {
			final entTbl = Scripted_entsLib.GetStored(entName);
			for (ind => val in entTbl.t) {
				if (shouldExcept(val)) {
					// trace(entTbl);
					entTbl.t[ind] = addExcept(val);
				}
			}
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

// static function getoldinclude() {
//     final _g = untyped __lua__("_G");
//     _g.__oldinclude = (_g.__oldinclude : Any).or(_g.include);
//     return _g.__oldinclude;
// }
// static var __oldinclude:Function = getoldinclude();
// public static function hookInclude() {
//     final _g =  untyped __lua__("_G");
//     _g.include = @:nullSafety(Off) function (file:String) {
//         //test all places relative to file. ugh
//         return if (FileLib.Exists(file,DATA)) {
//             final result = Lua.xpcall(Gmod.CompileFile,traceback,file);
//             if (result.status) {
//                 Gmod.include(file);
//             } else {
//                 Lua.error(result.value,99);
//                 null; //never hit
//             }
//         } else {
//             null;
//         }
//     }
// }
