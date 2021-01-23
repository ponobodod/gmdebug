package gmdebug.lua.handlers;


import lua.Debug;
import gmod.enums.SENSORBONE;
import gmdebug.lua.handlers.HScopes.FrameLocalScope;
import lua.NativeStringTools;
import gmod.libs.PlayerLib;
import gmod.libs.EntsLib;
import gmdebug.lua.handlers.HScopes.ScopeConsts;
import gmdebug.lua.managers.VariableManager;
import gmod.gclass.Entity;
import gmod.libs.DebugLib;

class HVariables implements IHandler<VariablesRequest> {

    public var variableManager:VariableManager;

    public function new(vm:VariableManager) {
        variableManager = vm;
    }

    function realChild(storedvar:Dynamic,addVars:Array<AddVar>) {
        switch Gmod.TypeID(storedvar) {
            case TYPE_TABLE:
                for (ind => val in (storedvar : AnyTable)) {
                    addVars.push({name: ind, value: val});
                }
            case TYPE_FUNCTION:
                var info = DebugLib.getinfo(storedvar, "S");
                addVars.push({
                    name: "(source)",
                    value: Gmod.tostring(info.short_src),
                    virtual: true,
                    noquote: true
                });
                addVars.push({name: "(line)", value: info.linedefined, virtual: true});
                final fenv = DebugLib.getfenv(storedvar);
                if (fenv != null) {
                    addVars.push({name : "(fenv)",value : fenv,virtual : true});
                }
                if (Debug.getupvalue(storedvar,1) != null) {
                    addVars.push({name : "(upvalues)",value : generateFakeChild(storedvar,Upvalues),virtual : true});
                }
            case TYPE_ENTITY:
                var ent:Entity = cast storedvar;
                // trace("bad?");
                var tbl = (storedvar : Entity).GetTable();
                addVars.push({name: "(position)", value: ent.GetPos(), virtual: true});
                addVars.push({name: "(angle)", value: ent.GetAngles(), virtual: true});
                addVars.push({name: "(model)", value: ent.GetModel(), virtual: true});
                for (ind => val in tbl) {
                    addVars.push({name: ind, value: val});
                }
            default:
        }
    }

    function fakeChild(realChild:Dynamic,type:FakeChild,addVars:Array<AddVar>) {
        switch (type) {
            case Upvalues:
                for (i in 1...9999) {
                    var upv = DebugLib.getupvalue(realChild, i);
                    if (upv.a == null)
                        break;
                    addVars.push({name: upv.a, value: upv.b});
                }
        }
    }

    function generateFakeChild(child:Dynamic,type:FakeChild) {
        final tab = Table.create();
        final meta = Table.create();
        final fakechild = Table.create();
        Lua.setmetatable(tab,meta);
        meta.__gmdebugFakeChild = fakechild;
        fakechild.child = child;
        fakechild.type = type;
        return tab;
    }

    function child(ref:Int):Array<AddVar> {
        var addVars:Array<AddVar> = [];
        var storedvar:Dynamic = (variableManager.getVar(ref) : Any).unsafe();
        if (storedvar == null)
            trace('Variable requested with nothing stored! $ref');
        
        var mt = DebugLib.getmetatable(storedvar);
        if (mt != null) {
            if (mt.__gmdebugFakeChild != null) {
                var realChild = mt.__gmdebugFakeChild.child;
                var type = mt.__gmdebugFakeChild.type;
                fakeChild(realChild,type,addVars);
            } else {
                addVars.push({name: "(metatable)", value: mt,virtual : true});
                realChild(storedvar,addVars);
            }
        } else {
            realChild(storedvar,addVars);
        }
        return addVars;

    }

    function frameLocal(frame:Int,scope:FrameLocalScope) {
        var addVars:Array<AddVar> = [];
        switch (scope) {
            case Arguments:
                var info = DebugLib.getinfo(frame + 2, "u");
                for (i in 1...info.nparams + 1) {
                    var result = DebugLib.getlocal(frame + 2, i);
                    if (result.a == null)
                        break;
                    // trace('locals ${result.a} ${result.b}');
                    addVars.push({name: result.a, value: result.b});
                }
                for (i in 1...9999) {
                    var result = DebugLib.getlocal(frame + 2, -i);
                    if (result.a == null)
                        break;
                    addVars.push({name: result.a, value: result.b});
                }
            case Locals:
                for (i in 1...9999) {
                    var result = DebugLib.getlocal(frame + 2, i);
                    if (result.a == null)
                        break;
                    // trace('locals ${result.a} ${result.b}');
                    addVars.push({name: result.a, value: result.b});
                }
                for (i in 1...9999) {
                    var result = DebugLib.getlocal(frame + 2, -i);
                    if (result.a == null)
                        break;
                    addVars.push({name: result.a, value: result.b});
                }
            case Upvalues:
                var info = DebugLib.getinfo(frame + 2, "f");
                if (info != null && info.func != null) {
                    for (i in 1...9999) {
                        var func = info.func; // otherwise _hx_bind..?
                        var upv = DebugLib.getupvalue(func, i);
                        if (upv.a == null)
                            break;
                        addVars.push({name: upv.a, value: upv.b});
                    }
                }
            case Fenv:
                var info = DebugLib.getinfo(frame + 2, "f");
                if (info != null && info.func != null) {
                    final func = info.func;
                    final tbl = DebugLib.getfenv(func);
                    for (i => p in tbl) {
                        addVars.push({name: i, value: p});
                    }
                }
        }
        return addVars;
    }

    function global(scope:ScopeConsts) {
        var addVars:Array<AddVar> = [];
        switch (scope) {
            case Globals:
                var _g:AnyTable = untyped __lua__("_G");
                var sort:Array<String> = [];
                var enums:Array<String> = [];
                addVars.push({name: "_G", value: ""});
                for (i => x in _g) {
                    if (Lua.type(i) == "string") {
                        if (isEnum(i, x)) {
                            enums.push(i);
                        } else {
                            sort.push(i);
                        }
                    }
                }
                // trace("made it past compare");
                for (index in sort) {
                    if (Lua.type(index) == "string") {
                        addVars.push({name: index, value: Reflect.field(_g, index)});
                    }
                }
            // trace("addedvars");
            case Players:
                for (i => ply in PlayerLib.GetAll()) {
                    trace('players $i $ply');
                    addVars.push({name: ply.GetName(), value: ply});
                }
            case Entities:
                final ents = EntsLib.GetAll();
                for (i in 1...EntsLib.GetCount()) {
                    var ent = ents[i];
                    addVars.push({name: ent.GetClass(), value: ent});
                }
            default:
                throw "Unhandled scope";
        }
        return addVars;
    }

    function isEnum(index:String, value:Dynamic) {
		return NativeStringTools.match(index, "%u", 1) != null
			&& NativeStringTools.match(index, "%u", 2) != null
			&& Lua.type(value) == "number";
    }

    function fixupNames(variables:Array<Variable>) {
        final varnamecount:Map<String, Int> = [];
        for (v in variables) {
            final count = varnamecount.get(v.name);
            if (count != null) {
                varnamecount.set(v.name, count + 1);
                v.name = '${v.name} ($count)';
            } else {
                varnamecount.set(v.name, 1);
            }
        }
    }

    public function handle(req:VariablesRequest) {
		final args = req.arguments.unsafe();
		final ref:VariableReference = args.variablesReference;
		final addVars = switch (ref.getValue()) {
			case Child(_, ref):
                child(ref);
			case FrameLocal(_, frame, scope):
				frameLocal(frame,scope);
			case Global(_, scope):
				global(scope);
		}
		final variablesArr = addVars.map(variableManager.genvar);
		fixupNames(variablesArr);
		var resp = req.compose(variables, {variables: variablesArr});
		// final old = Gmod.SysTime();
		// trace("custom json start");
		final js = tink.Json.stringify((cast resp : VariablesResponse)); // in pratical terms they're the same
		// trace('custom json end ${Gmod.SysTime() - old}');
		resp.sendtink(js);
		return WAIT;
	}

    
}

enum FakeChild {
    Upvalues;

}