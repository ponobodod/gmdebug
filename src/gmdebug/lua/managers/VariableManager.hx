package gmdebug.lua.managers;

import gmdebug.lua.handlers.HScopes;
import gmod.gclass.Entity;
import gmod.libs.DebugLib;
import gmod.Gmod;
import lua.Lua;
import lua.NativeStringTools;
import gmdebug.VariableReference;
import gmdebug.lua.handlers.IHandler;

using gmod.PairTools;

class VariableManager {
    
	var storedVariables:Array<Null<Dynamic>> = [null];
	
	public function new() {
		
	}

	public function resetVariables() {
		storedVariables = [null];
	}
    
    public function getVar(ind:Int) {
        return storedVariables[ind];
    }

	public function genvar(addv:AddVar):Variable {
		final name = Std.string(addv.name);
		final val = addv.value;
		var virtual = addv.virtual;
		var noquote = addv.noquote;
		var novalue = addv.novalue;
		var ty = Gmod.type(val);
		var id = Gmod.TypeID(val);
		var stringReplace = switch (Lua.type(val)) {
			case "table":
				"table";
			case "string":
				val;
			case "number":
				Std.string(val);
			default:
				Gmod.tostring(val);
		};
		var obj:Variable = {
			name: name,
			type: ty,
			value: switch [ty, noquote, novalue] {
				case ["table", _, _]:
					"table";
				case ["string", null, _]:
					'"$stringReplace"';
				case [_, _, true]:
					"";
				default:
					stringReplace;
			},
			variablesReference: switch id {
				case _ if (name == "_G"):
					ScopeConsts.Globals; //TODO update
				case TYPE_ENTITY if (!Gmod.IsValid(val)):
					0;
				case TYPE_TABLE | TYPE_FUNCTION | TYPE_USERDATA | TYPE_ENTITY:
					VariableReference.encode(Child(Debugee.clientID, storedVariables.push(val) - 1));
				default:
					0;
			},
		}
		switch [id, virtual] {
			case [TYPE_FUNCTION, null]:
				obj.presentationHint = {
					kind: Method,
					attributes: null,
					visibility: Public
				};
			case [_, null]:
			case [_, _]:
				obj.presentationHint = {
					kind: Virtual,
					attributes: null,
					visibility: Internal
				};
		}
		return obj;
	}

	public function generateVariablesReference(val:Dynamic, ?name:String):Int {
		return switch Gmod.TypeID(val) {
			case _ if (name == "_G"):
				ScopeConsts.Globals;
			case TYPE_ENTITY if (!Gmod.IsValid(val)):
				0;
			case TYPE_TABLE | TYPE_FUNCTION | TYPE_USERDATA | TYPE_ENTITY:
				VariableReference.encode(Child(Debugee.clientID, storedVariables.push(val) - 1));
			default:
				0;
		};
	}

	
}

typedef AddVar = {
	name:Dynamic,
	// std.string
	value:Dynamic,
	?virtual:Bool,
	?noquote:Bool,
	?novalue:Bool
}
