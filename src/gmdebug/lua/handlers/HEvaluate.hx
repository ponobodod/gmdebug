package gmdebug.lua.handlers;

import gmdebug.lua.managers.VariableManager;
import lua.Lua;
import lua.Table;
import gmod.libs.DebugLib;
import lua.Table.AnyTable;
import gmod.Gmod;
import gmdebug.composer.ComposedProtocolMessage;
import lua.NativeStringTools;
import gmdebug.lua.handlers.IHandler;

class HEvaluate implements IHandler<EvaluateRequest> {
    
    public function new(vm:VariableManager) {
        variableManager = vm;
    }

	var variableManager:VariableManager;

	public static inline function translateEvalError(err:String) {
		return NativeStringTools.gsub(err, '^%[string %"X%"%]%:%d+%: ', "");
	}

	public static function createEvalEnvironment(stackLevel:Int):AnyTable {
		final env = Table.create();
		final unsettables:AnyTable = Table.create();
		final set = function(k, v) {
			Reflect.setField(unsettables, k, v);
		}
		var info = DebugLib.getinfo(stackLevel, "f"); // used to be 1
		var fenv:Null<AnyTable> = untyped __lua__("_G");
		if (info != null && info.func != null) {
			for (i in 1...9999) {
				final func = info.func; // otherwise _hx_bind..?
				final upv = DebugLib.getupvalue(func, i);
				if (upv.a == null)
					break;
				set(upv.a, upv.b);
			}
			final func = info.func; // otherwise _hx_bind..?
			fenv = DebugLib.getfenv(func).or(untyped __lua__("_G"));
			// Gmod.print(fenv);
		}
		for (i in 1...9999) {
			final lcl = DebugLib.getlocal(stackLevel, i); // used to be 1 :)
			if (lcl.a == null)
				break;
			set(lcl.a, lcl.b);
		}
		var metatable:AnyTable = Table.create();
		metatable.__newindex = (t, k, v) -> {
			if (Lua.rawget(unsettables, k) != null)
				Gmod.error("Cannot alter upvalues and locals", 2);
			else
				fenv[k] = v;
		}
		metatable.__index = unsettables;
		var unsetmeta:AnyTable = Table.create();
		unsetmeta.__index = (t,k) -> {
			return if (k == "_G") {
				untyped __lua__("_G"); //_G is always avaliable, for convience
			} else {
				fenv[cast k];
			}
		};
		Gmod.setmetatable(env, metatable);
		Gmod.setmetatable(unsettables, unsetmeta);
		return env;
	}

	function processCommands(x:EvalCommand) {
		switch (x) {
			case profile:
				DebugLoopProfile.beginProfiling();
		}
	}

	public function handle(evalReq:EvaluateRequest):HandlerResponse {
		final args = evalReq.arguments.unsafe();
		final fid:Null<FrameID> = args.frameId;
		if (args.expression.charAt(0) == "#") {
			processCommands(args.expression.substr(1));
		}
		var expr = Util.processReturnable(args.expression);
		if (args.context == Hover) {
			expr = NativeStringTools.gsub(expr, ":", "."); // a function call is probably not intended from a hover.
		}
		trace('expr : $expr');
		final resp:ComposedProtocolMessage = switch (Util.compileString(expr, "GmDebug")) {
			case Error(err):
				evalReq.composeFail(translateEvalError(err));
			case Success(func):
				if (fid != null) {
					final eval = createEvalEnvironment(fid.getValue().actualFrame + 2);
					Gmod.setfenv(func, eval);
				}
				switch (Util.runCompiledFunction(func)) {
					case Error(err):
						evalReq.composeFail(translateEvalError(err));
					case Success(result):
						final item = variableManager.genvar({
							name: "",
							value: result
						});
						evalReq.compose(evaluate, {
							result: item.value,
							type: item.type,
							variablesReference: item.variablesReference,
						});
				}
		}
		resp.send();
		return WAIT;
	}
}

enum abstract EvalCommand(String) from String {
	var profile;
}
