package gmdebug.lua.managers;

import gmod.libs.DebugLib;
import gmod.Gmod;
import lua.Lua;
import lua.NativeStringTools;
import gmdebug.lua.handlers.IHandler;
using gmod.PairTools;

class VariableManager implements IHandler<VariablesRequest> {

    var storedVariables:Array<Null<Dynamic>> = [null];

    public function resetVariables() {
	    storedVariables = [null];
    }

    public function handle(req:VariablesRequest) {
        final args = req.arguments.unsafe();
        final ref:VariableReference = args.variablesReference;
        final addVars:Array<AddVar> = [];
        switch (ref.getValue()) {
            case Child(_, ref):
	      var storedvar:Dynamic = (storedVariables[ref] : Any).unsafe();
	      if (storedvar == null) trace('Variable requested with nothing stored! $ref');
                switch Gmod.TypeID(storedvar) {
                    case TYPE_TABLE:
                        for (ind => val in (storedvar : AnyTable)) {
                            addVars.push({name : ind, value : val});
                        }
                    case TYPE_FUNCTION:
                        var info = DebugLib.getinfo(storedvar, "S");
                        addVars.push({name : "(source)", value : Gmod.tostring(info.short_src),virtual: true,noquote : true});
                        addVars.push({name : "(line)", value : info.linedefined,virtual: true});
                        for (i in 1...9999) {
                            var upv = DebugLib.getupvalue(storedvar,i);
                            if (upv.a == null) break;
                            addVars.push({name : upv.a, value :upv.b});
                        }
                    case TYPE_ENTITY:
                        var ent:Entity = cast storedvar;
                        // trace("bad?");
                        var tbl = (storedvar : Entity).GetTable();
                        addVars.push({name : "(position)", value :ent.GetPos(),virtual: true});
                        addVars.push({name : "(angle)",value : ent.GetAngles(),virtual: true});
                        addVars.push({name : "(model)", value : ent.GetModel(),virtual : true});
                        for (ind => val in tbl) {
                            addVars.push({name : ind, value : val});
                        }
                    default:
                }
                var mt = DebugLib.getmetatable(storedvar);
                if (mt != null) {
                    addVars.push({name : "(metatable)", value : mt});
                }
            case FrameLocal(_,frame,scope):
                switch (scope) {
                    case FrameLocalScope.Arguments:
                        var info = DebugLib.getinfo(frame + 1,"u");
                        for (i in 1...info.nparams + 1) {
                            var result = DebugLib.getlocal(frame + 1,i);
                            if (result.a == null) break;
                            // trace('locals ${result.a} ${result.b}');
                            addVars.push({name : result.a, value : result.b});
                        }
                        for (i in 1...9999) {
                            var result = DebugLib.getlocal(frame + 1,-i);
                            if (result.a == null) break;
                            addVars.push({name : result.a, value : result.b});
                        }
                    case FrameLocalScope.Locals:
                        for (i in 1...9999) {
                            var result = DebugLib.getlocal(frame + 1,i);
                            if (result.a == null) break;
                            // trace('locals ${result.a} ${result.b}');
                            addVars.push({name : result.a, value : result.b});
                        }
                        for (i in 1...9999) {
                            var result = DebugLib.getlocal(frame + 1,-i);
                            if (result.a == null) break;
                            addVars.push({name : result.a, value : result.b});
                        }
                    case FrameLocalScope.Upvalues:
                        var info = DebugLib.getinfo(frame + 1,"f");
                        if (info != null && info.func != null) {
                            for (i in 1...9999) {
                                var func = info.func;//otherwise _hx_bind..?
                                var upv = DebugLib.getupvalue(func,i);
                                if (upv.a == null) break;
                                addVars.push({name : upv.a, value : upv.b});
                            }
                        }
                    case FrameLocalScope.Fenv:
                        var info = DebugLib.getinfo(frame + 1,"f");
                        if (info != null && info.func != null) {
                            final func = info.func;
                            final tbl = DebugLib.getfenv(func);
                            for (i => p in tbl) {
                                addVars.push({name : i,value : p});
                            }
                        }
                }
            case Global(_,scope):
                switch (scope) {
                    case ScopeConsts.Globals:
                        var _g:AnyTable = untyped __lua__("_G");
                        var sort:Array<String> = [];
                        var enums:Array<String> = [];
                        addVars.push({name : "_G", value : ""});
                        for (i => x in _g) {
                            if (Lua.type(i) == "string") {
                                if (isEnum(i,x)) {
                                    enums.push(i);
                                } else {
                                    sort.push(i);
                                }
                            }
                        }
                        // trace("made it past compare");
                        for (index in sort) {
                            if (Lua.type(index) == "string") {
                                addVars.push({name : index, value : Reflect.field(_g,index)});
                            }
                        }
                        // trace("addedvars");
                    case ScopeConsts.Players:
                        for (i => ply in PlayerLib.GetAll()) {
                            trace('players $i $ply');
                            addVars.push({name : ply.GetName(), value : ply});
                        }
                    case ScopeConsts.Entities:
                        final ents = EntsLib.GetAll();
                        for (i in 1...EntsLib.GetCount()) {
                            var ent = ents[i];
                            addVars.push({name : ent.GetClass(), value : ent});
                        }
                }
        }
        final variablesArr = addVars.map(genvar);
        fixupNames(variablesArr);
        var resp = req.compose(variables,{variables: variablesArr});
        // final old = Gmod.SysTime();
        // trace("custom json start");
        final js = tink.Json.stringify((cast resp : VariablesResponse)); //in pratical terms they're the same
        // trace('custom json end ${Gmod.SysTime() - old}');
        resp.sendtink(js);
        return WAIT;
    }

    function isEnum(index:String,value:Dynamic) {
        return NativeStringTools.match(index, "%u", 1) != null
            && NativeStringTools.match(index, "%u", 2) != null
            && Lua.type(value) == "number";
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
        var obj:Variable =  {
            name : name,
            type : ty,
            value : switch[ty,noquote,novalue] {
                case ["table",_,_]:
                    "table";
                case ["string",null,_]:
                    '"$stringReplace"';
                case [_,_,true]:
                    "";
                default:
                    stringReplace;
            },
            variablesReference : switch id {
                case _ if (name == "_G"):
                    ScopeConsts.Globals;
                case TYPE_ENTITY if (!Gmod.IsValid(val)):
                    0;
                case TYPE_TABLE | TYPE_FUNCTION | TYPE_USERDATA | TYPE_ENTITY: 
                    VariableReference.encode(Child(Debugee.clientID,storedVariables.push(val) - 1));
                default:
                    0;
            },
        }
        switch [id,virtual] {
            case [TYPE_FUNCTION,null]:
                obj.presentationHint = {
                    kind : Method,
                    attributes : null,
                    visibility: Public
                };
            case [_,null]:
            case [_,_]:
                obj.presentationHint = {
                    kind : Virtual,
                    attributes: null,
                    visibility: Internal
                };
        }
        return obj;
    }

    public function generateVariablesReference(val:Dynamic,?name:String) {
        return switch Gmod.TypeID(val) {
            case _ if (name == "_G"):
                ScopeConsts.Globals;
            case TYPE_ENTITY if (!Gmod.IsValid(val)):
                0;
            case TYPE_TABLE | TYPE_FUNCTION | TYPE_USERDATA | TYPE_ENTITY: 
		VariableReference.encode(Child(Debugee.clientID,storedVariables.push(val) - 1));
            default:
                0;
        };
    }

    static function fixupNames(variables:Array<Variable>) {
        final varnamecount:Map<String,Int> = [];
        for (v in variables) {
            final count = varnamecount.get(v.name);
            if (count != null) {
                varnamecount.set(v.name,count + 1);
                v.name = '${v.name} ($count)';
            } else {
                varnamecount.set(v.name,1);
            }
        }
    }
}

typedef AddVar = {
    name : Dynamic, //std.string
    value : Dynamic,
    ?virtual : Bool,
    ?noquote : Bool,
    ?novalue : Bool
}