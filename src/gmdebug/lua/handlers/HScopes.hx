package gmdebug.lua.handlers;

import gmod.libs.DebugLib;

class HScopes implements IHandler<ScopesRequest> {
	public function new() {}

	public function handle(scopeReq:ScopesRequest):HandlerResponse {
		var args = scopeReq.arguments.sure();
		final frameInfo = (args.frameId : FrameID).getValue();
		var info = DebugLib.getinfo(frameInfo.actualFrame + 1, "fuS");
		var arguments:Scope = {
			name: "Arguments",
			presentationHint: Arguments,
			variablesReference: VariableReference.encode(FrameLocal(Debugee.clientID.unsafe(), frameInfo.actualFrame, FrameLocalScope.Arguments)),
			expensive: false
		}
		var locals:Scope = {
			name: "Locals",
			presentationHint: Locals,
			variablesReference: VariableReference.encode(FrameLocal(Debugee.clientID.unsafe(), frameInfo.actualFrame, FrameLocalScope.Locals)),
			expensive: false,
			line: info.linedefined,
			endLine: info.lastlinedefined
		};
		var upvalues:Scope = {
			name: "Upvalues",
			variablesReference: VariableReference.encode(FrameLocal(Debugee.clientID.unsafe(), frameInfo.actualFrame, FrameLocalScope.Upvalues)),
			expensive: false,
		};
		var globals:Scope = {
			name: "Globals",
			variablesReference: VariableReference.encode(Global(Debugee.clientID.unsafe(), ScopeConsts.Globals)),
			expensive: true,
		}
		var players:Scope = {
			name: "Players",
			variablesReference: VariableReference.encode(Global(Debugee.clientID.unsafe(), ScopeConsts.Players)),
			expensive: true
		}
		var entities:Scope = {
			name: "Entities",
			variablesReference: VariableReference.encode(Global(Debugee.clientID.unsafe(), ScopeConsts.Entities)),
			expensive: true,
		}
		var enums:Scope = {
			name: "Enums",
			variablesReference: VariableReference.encode(Global(Debugee.clientID.unsafe(), ScopeConsts.Enums)),
			expensive: true
		}

		var env:Scope = {
			name: "Function Environment",
			variablesReference: VariableReference.encode(FrameLocal(Debugee.clientID.unsafe(), frameInfo.actualFrame, FrameLocalScope.Fenv)),
			expensive: true
		}
		var hasFenv:Bool = if (info != null && info.func != null) {
			final func = info.func;
			DebugLib.getfenv(func) != untyped __lua__("_G");
		} else {
			false;
		}
		var resp = scopeReq.compose(scopes, {
			scopes: switch (info.what) {
				case C:
					[arguments, locals, entities, players, globals, enums];
				case Lua:
					if (hasFenv) {
						[arguments, locals, upvalues, entities, players, globals, enums, env];
					} else {
						[arguments, locals, upvalues, entities, players, globals, enums];
					}
			}
		});
		final js = tink.Json.stringify((cast resp : ScopesResponse)); // in pratical terms they're the same
		resp.sendtink(js);
		return WAIT;
	}
}

enum abstract FrameLocalScope(Int) to Int from Int {
	var Arguments;
	var Locals;
	var Upvalues;
	var Fenv;
}

enum abstract ScopeConsts(Int) to Int from Int {
	var Globals;
	var Players;
	var Entities;
	var Enums;
}
