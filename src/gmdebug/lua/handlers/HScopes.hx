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
			variablesReference: VariableReference.encode(FrameLocal(Debugee.clientID.unsafe(), frameInfo.actualFrame, Arguments)),
			expensive: false
		}
		var locals:Scope = switch (info) {
			case null:
				null;
			case {linedefined : null, lastlinedefined : null}:
				{
					name: "Locals",
					presentationHint: Locals,
					variablesReference: VariableReference.encode(FrameLocal(Debugee.clientID.unsafe(), frameInfo.actualFrame, Locals)),
					expensive: false,
				};
			case {linedefined : ld, lastlinedefined : lld}:
				{
					name: "Locals",
					presentationHint: Locals,
					variablesReference: VariableReference.encode(FrameLocal(Debugee.clientID.unsafe(), frameInfo.actualFrame, Locals)),
					expensive: false,
					line: ld,
					endLine: lld,
					column: 1,
					endColumn: 99999
				};
		};
		
		var upvalues:Scope = {
			name: "Upvalues",
			variablesReference: VariableReference.encode(FrameLocal(Debugee.clientID.unsafe(), frameInfo.actualFrame, Upvalues)),
			expensive: false,
		};
		var globals:Scope = {
			name: "Globals",
			variablesReference: VariableReference.encode(Global(Debugee.clientID.unsafe(), Globals)),
			expensive: true,
		}
		var players:Scope = {
			name: "Players",
			variablesReference: VariableReference.encode(Global(Debugee.clientID.unsafe(), Players)),
			expensive: true
		}
		var entities:Scope = {
			name: "Entities",
			variablesReference: VariableReference.encode(Global(Debugee.clientID.unsafe(), Entities)),
			expensive: true,
		}
		var enums:Scope = {
			name: "Enums",
			variablesReference: VariableReference.encode(Global(Debugee.clientID.unsafe(), Enums)),
			expensive: true
		}

		var env:Scope = {
			name: "Function Environment",
			variablesReference: VariableReference.encode(FrameLocal(Debugee.clientID.unsafe(), frameInfo.actualFrame, Fenv)),
			expensive: true
		}
		var hasFenv:Bool = if (info != null && info.func != null) {
			final func = info.func;
			DebugLib.getfenv(func) != untyped __lua__("_G");
		} else {
			false;
		}
		var resp = scopeReq.compose(scopes, {
			scopes: switch info {
				case null:
					Lua.print("No info?!", frameInfo.actualFrame + 1);
					[globals, entities, players, enums];
				case {what : C}:
					[arguments, locals, globals, entities, players, enums];
				case {what : Lua}:
					if (hasFenv) {
						[arguments, locals, upvalues, env, globals, entities, players, enums];
					} else {
						[arguments, locals, upvalues, globals, entities, players, enums];
					}
				case {what : main}:
					[locals, upvalues, env, globals, entities, players, enums];
				default:
					Lua.print("OH GOD",info.what);
					[globals, entities, players, enums];
			}
		});
		final js = tink.Json.stringify((cast resp : ScopesResponse)); // in pratical terms they're the same
		resp.sendtink(js);
		return WAIT;
	}
}




