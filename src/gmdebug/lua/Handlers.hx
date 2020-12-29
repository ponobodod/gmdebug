package gmdebug.lua;

import gmdebug.ComposedMessage;
import gmod.LuaArray;
import tink.Json;
import gmdebug.ComposedMessage.ComposedProtocolMessage;
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
import gmod.gclass.Player;
import gmod.libs.PlayerLib;
import gmdebug.lua.DebugLoop.BreakPoint;
import gmod.libs.DebugLib;
import gmdebug.lua.Protocol;
using gmdebug.ComposeTools;
import String;
using Safety;
using gmod.PairTools;
using Lambda;

class Handlers {

    static var handlerMap:Map<RequestString<Dynamic,Dynamic>,(req:Request<Dynamic>) -> HandlerResponse> = [
        pause => h_pause,
        stackTrace => h_stackTrace,
        stepIn => h_stepIn,
        stepOut => h_stepOut,
        threads => h_threads,
        scopes => h_scopes,
        next => h_next,
        variables => h_variables,
        loadedSources => h_sources,
        // setBreakpoints => h_setBreakpoints,
        configurationDone => h_configurationDone,
        modules => h_modules,
        disconnect => h_disconnect,
        setExceptionBreakpoints => h_setExceptionBreakpoints,
        // setFunctionBreakpoints => h_setFunctionBreakpoints,
        evaluate => h_evaluate,
        breakpointLocations => h_breakpointLocations
    ];

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

    static function h_pause(req:PauseRequest) {
        if (Debugee.inpauseloop) return WAIT;
        var rep = req.compose(pause,{});
        rep.send();
        Debugee.startHaltLoop(Pause,Debugee.stackOffset.pause);
        return WAIT;
    }

    static function h_configurationDone(req:ConfigurationDoneRequest) {
        var rep = req.compose(configurationDone);
        rep.send();
        return WAIT;
    }

    //TODO cleanup - does not work with vscode (which is the only debugger if you think about it)
    static function h_modules(req:ModulesRequest) {
        var mod = req.compose(modules,{
            modules: [{
                id: 0,
                name: "test",
            }, {
                id: 1,
                name : "test2"
            }],
            totalModules: 2
        });
        mod.send();
        return WAIT;
    }

    static function h_sources(req:LoadedSourcesRequest) {
        var resp = req.compose(loadedSources,{
            sources: Sources.sources,
        });
        resp.send();
        return WAIT;
    }

    static function h_continue(req:ContinueRequest) {
        var resp = req.compose(_continue,{allThreadsContinued: false});
        resp.send();
        return CONTINUE;
    }

    static function h_stepIn(x:StepInRequest) {
        Debugee.state = STEP(null);
        var rep = x.compose(stepIn);
        rep.send();
        DebugLoop.activateLineStepping();
        return CONTINUE;
    }

    static function h_stepOut(x:StepOutRequest) {
        var tarheight = Debugee.stackHeight - (Debugee.stackOffset.step + 1);
        trace('stepOut $tarheight ${Debugee.minheight}');
        if (tarheight < Debugee.minheight) {
            final info = DebugLib.getinfo(Debugee.baseDepth.unsafe() + 1,"fLSl");
            final func = info.func;
            trace('${info.source}');
            final activeLines = info.activelines;
            final lowest = activeLines.keys().fold(
                (line,res) -> {
                    return if (line < res) {
                        line;
                    } else {
                        res;
                    }
                },cast Math.POSITIVE_INFINITY);
            trace('lowest $lowest');
            Debugee.state = OUT(func,lowest);
        } else {
            Debugee.state = STEP(tarheight);
        }
        DebugLoop.activateLineStepping();
        final stepout = x.compose(stepOut);
        stepout.send();
        return CONTINUE;
    }

    static function h_threads(x:ThreadsRequest) {
        var threadarr:Array<Thread> = [{id: 0,name : "Server"}];
        // for (i => ply in Debugee.playerThreads) {
        //     if (ply != null) {
        //         threadarr.push({
        //             id: i + 1,
        //             name: ply.Name()
        //         });
        //     }
        // }
        var threads = x.compose(threads,{
            threads : threadarr
        });
        threads.send();
        return WAIT;
    }

    public static inline function translateEvalError(err:String) {
        return NativeStringTools.gsub(err,'^%[string %"X%"%]%:%d+%: ',"");
    }

    public static function createEvalEnvironment(stackLevel:Int):AnyTable {
        final env = Table.create();
        final unsettables:AnyTable = Table.create();
        final set = function(k,v) {
            Reflect.setField(unsettables,k,v);
        }
        var info = DebugLib.getinfo(stackLevel + 2,"f"); //used to be 1
        var fenv:Null<AnyTable> = null;
        if (info != null && info.func != null) {
            for (i in 1...9999) {
                final func = info.func;//otherwise _hx_bind..?
                final upv = DebugLib.getupvalue(func,i);
                if (upv.a == null) break;
                set(upv.a,upv.b);
            }
            final func = info.func;//otherwise _hx_bind..?
            fenv = DebugLib.getfenv(func);
            // Gmod.print(fenv);
        }
        for (i in 1...9999) {
            final lcl = DebugLib.getlocal(stackLevel + 2,i); //used to be 1 :)
            if (lcl.a == null) break;
            set(lcl.a,lcl.b);
        }
        var metatable:AnyTable = Table.create();
        metatable.__newindex = (t,k,v) -> {
            if (Lua.rawget(unsettables,k) != null) Gmod.error("Cannot alter upvalues and locals",2);
            else untyped __lua__("_G")[k] = v;
        }
        metatable.__index = unsettables;
        var unsetmeta:AnyTable = Table.create();
        unsetmeta.__index = fenv.or(untyped __lua__("_G"));
        Gmod.setmetatable(env,metatable);
        Gmod.setmetatable(unsettables,unsetmeta);
        // Gmod.print(env);
        return env;
    }

    static function processCommands(x:EvalCommand) {
        switch (x) {
            case profile:
                DebugLoopProfile.beginProfiling();
        }
    }

    public static function h_evaluate(x:EvaluateRequest) {
        final args = x.arguments.unsafe();
        final fid:Null<FrameID> = args.frameId;
        if (args.expression.charAt(0) == "#") {
            processCommands(args.expression.substr(1));
        }
        var expr = Util.processReturnable(args.expression);
        if (args.context == Hover) {
            expr = NativeStringTools.gsub(expr,":","."); //a function call is probably not intended from a hover.
        }
        trace('expr : $expr');
        final resp:ComposedProtocolMessage = switch (Util.compileString(expr,"GmDebug")) {
            case Error(err):
                x.composeFail(translateEvalError(err));
            case Success(func):
                if (fid != null) {
                    final eval = createEvalEnvironment(fid.getValue().actualFrame);
                    Gmod.setfenv(func,eval);
                }
                switch (Util.runCompiledFunction(func)) {
                    case Error(err):
                        x.composeFail(translateEvalError(err));
                    case Success(result):
                        final item = genvar({
                            name : "",
                            value : result
                        });
                        x.compose(evaluate,{
                            result: item.value,
                            type: item.type,
                            variablesReference: item.variablesReference,
                        });
                }
        }
        resp.send();
        return WAIT;
    }

    public static function h_setExceptionBreakpoints(x:SetExceptionBreakpointsRequest) {
        var rep = x.compose(setExceptionBreakpoints);
        var gamemodeSet = false;
        var entitiesSet = false;
        for (filter in x.arguments.unsafe().filters) {
            switch (filter) {
                case gamemode:
                    Exceptions.hookGamemodeHooks();
		    gamemodeSet = true;
                case entities:
                    Exceptions.hookEntityHooks();
		    entitiesSet = true;
            }
        }
        if (!gamemodeSet) Exceptions.unhookGamemodeHooks();
	if (!entitiesSet) Exceptions.unhookEntityHooks();
        rep.send();
        return WAIT;
    }

    // public static function h_setFunctionBreakpoints(x:SetFunctionBreakpointsRequest) {
    //     final args = x.arguments.unsafe();
    //     DebugLoop.functionBP.clear();
    //     //candidate for map and yucky functional ect.
    //     final bpResponse:Array<Breakpoint> = [];
    //     for (fbp in args.breakpoints) {
    //         final eval = Util.processReturnable(fbp.name);
    //         final resp:Breakpoint = switch (Util.compileString(eval,"gmdebug FuncBp:")) {
    //             case Error(err):
    //                 {
    //                     verified : false,
    //                     message : "Failed to compile" 
    //                 };
    //             case Success(Util.runCompiledFunction(_) => Error(err)):
    //                 {
    //                     verified : false,
    //                     message : "Failed to run" 
    //                 };
    //             case Success(Util.runCompiledFunction(_) => Success(result))
    //                 if (Lua.type(result) != "function"):
    //                 {
    //                     verified : false,
    //                     message : "Result is not a function" //TODO add error message 
    //                 };
    //             case Success(Util.runCompiledFunction(_) => Success(func)):
    //                 DebugLoop.functionBP.set(func,true);
    //                 {
    //                     verified : true
    //                 }
    //         }
    //         bpResponse.push(resp);
    //     }
    //     final resp = x.compose(setFunctionBreakpoints, {
    //         breakpoints : bpResponse
    //     });
    //     resp.send();
    //     return WAIT;
    // }

    public static function h_scopes(x:ScopesRequest) {
        var args = x.arguments.sure();
        final frameInfo = (args.frameId : FrameID).getValue();
        var info = DebugLib.getinfo(frameInfo.actualFrame + 1,"fuS");
        var arguments:Scope = {
            name: "Arguments",
            presentationHint: Arguments,
            variablesReference: VariableReference.encode(
                FrameLocal(Debugee.clientID.unsafe(),frameInfo.actualFrame,FrameLocalScope.Arguments)),
            expensive : false
        }
        var locals:Scope = {
            name: "Locals",
            presentationHint: Locals,
            variablesReference: VariableReference.encode(
                FrameLocal(Debugee.clientID.unsafe(),frameInfo.actualFrame,FrameLocalScope.Locals)),
            expensive: false,
            line: info.linedefined,
            endLine: info.lastlinedefined
        };
        var upvalues:Scope = {
            name: "Upvalues",
            variablesReference: VariableReference.encode(
                FrameLocal(Debugee.clientID.unsafe(),frameInfo.actualFrame,FrameLocalScope.Upvalues)),
            expensive: false,
        };
        var globals:Scope = {
            name: "Globals",
            variablesReference: VariableReference.encode(
                Global(Debugee.clientID.unsafe(),ScopeConsts.Globals)),
            expensive: true,
        }
        var players:Scope = {
            name: "Players",
            variablesReference: VariableReference.encode(
                Global(Debugee.clientID.unsafe(),ScopeConsts.Players)),
            expensive : true
        }
        var entities:Scope = {
            name: "Entities",
            variablesReference: VariableReference.encode(
                Global(Debugee.clientID.unsafe(),ScopeConsts.Entities)),
            expensive : true,
        }
        var enums:Scope = {
            name: "Enums",
            variablesReference: VariableReference.encode(
                Global(Debugee.clientID.unsafe(),ScopeConsts.Enums)),
            expensive: true
        }

        var env:Scope = {
            name: "Function Environment",
            variablesReference: VariableReference.encode(
                FrameLocal(Debugee.clientID.unsafe(),frameInfo.actualFrame,FrameLocalScope.Fenv)),
            expensive : true
        }
        var hasFenv:Bool =
            if (info != null && info.func != null) {
                final func = info.func;
                DebugLib.getfenv(func) != untyped __lua__("_G");
            } else {
                false;
            }
        var resp = x.compose(scopes,{
            scopes : switch (info.what) {
                case C:
                    [arguments,locals,entities,players,globals,enums];
                case Lua:
                    if (hasFenv) {
                        [arguments,locals,upvalues,entities,players,globals,enums,env];
                    } else {
                        [arguments,locals,upvalues,entities,players,globals,enums];
                    }
            }
        });
        final js = tink.Json.stringify((cast resp : ScopesResponse)); //in pratical terms they're the same
        resp.sendtink(js) ;
        return WAIT;
    }

    static function h_next(x:NextRequest) {
        var resp = x.compose(next);
        trace('our stack height ${Debugee.stackHeight} ${Debugee.stackOffset.step}');
        var tarheight = Debugee.stackHeight - Debugee.stackOffset.step;
        Debugee.state = STEP(tarheight);
        resp.send();
        DebugLoop.activateLineStepping();
        return CONTINUE;
    }


    static function h_disconnect(x:DisconnectRequest) {
        return DISCONNECT;
    }

    // public static function generateVariablesReference(val:Dynamic,?name:String):Int {
        // return switch Gmod.TypeID(val) {
        //     case _ if (name == "_G"):
        //         ScopeConsts.Globals;
        //     case TYPE_ENTITY if (!Gmod.IsValid(val)):
        //         0;
        //     case TYPE_TABLE | TYPE_FUNCTION | TYPE_USERDATA | TYPE_ENTITY: 
	// 	VariableReference.encode(Child(Debugee.clientID,storedVariables.push(val) - 1));
        //     default:
        //         0;
        // };
    // }

    // static function genvar(addv:AddVar):Variable {
    //     final name = Std.string(addv.name);
    //     final val = addv.value;
    //     var virtual = addv.virtual;
    //     var noquote = addv.noquote;
    //     var novalue = addv.novalue;
    //     var ty = Gmod.type(val);
    //     var id = Gmod.TypeID(val);
    //     var stringReplace = switch (Lua.type(val)) { 
    //         case "table":
    //             "table";
    //         case "string":
    //             val;
    //         case "number":
    //             Std.string(val);
    //         default:
    //             Gmod.tostring(val);
    //     };
    //     var obj:Variable =  {
    //         name : name,
    //         type : ty,
    //         value : switch[ty,noquote,novalue] {
    //             case ["table",_,_]:
    //                 "table";
    //             case ["string",null,_]:
    //                 '"$stringReplace"';
    //             case [_,_,true]:
    //                 "";
    //             default:
    //                 stringReplace;
    //         },
    //         variablesReference : switch id {
    //             case _ if (name == "_G"):
    //                 ScopeConsts.Globals;
    //             case TYPE_ENTITY if (!Gmod.IsValid(val)):
    //                 0;
    //             case TYPE_TABLE | TYPE_FUNCTION | TYPE_USERDATA | TYPE_ENTITY: 
    //                 VariableReference.encode(Child(Debugee.clientID,storedVariables.push(val) - 1));
    //             default:
    //                 0;
    //         },
    //     }
    //     switch [id,virtual] {
    //         case [TYPE_FUNCTION,null]:
    //             obj.presentationHint = {
    //                 kind : Method,
    //                 attributes : null,
    //                 visibility: Public
    //             };
    //         case [_,null]:
    //         case [_,_]:
    //             obj.presentationHint = {
    //                 kind : Virtual,
    //                 attributes: null,
    //                 visibility: Internal
    //             };
    //     }
    //     return obj;
    // }

    // static function fixupNames(variables:Array<Variable>) {
    //     final varnamecount:Map<String,Int> = [];
    //     for (v in variables) {
    //         final count = varnamecount.get(v.name);
    //         if (count != null) {
    //             varnamecount.set(v.name,count + 1);
    //             v.name = '${v.name} ($count)';
    //         } else {
    //             varnamecount.set(v.name,1);
    //         }
    //     }
    // }

    // static function h_variables(req:VariablesRequest) {
    //     final args = req.arguments.unsafe();
    //     final ref:VariableReference = args.variablesReference;
    //     final addVars:Array<AddVar> = [];
    //     switch (ref.getValue()) {
    //         case Child(_, ref):
    // 	      var storedvar:Dynamic = (storedVariables[ref] : Any).unsafe();
    // 	      if (storedvar == null) trace('Variable requested with nothing stored! $ref');
    //             switch Gmod.TypeID(storedvar) {
    //                 case TYPE_TABLE:
    //                     for (ind => val in (storedvar : AnyTable)) {
    //                         addVars.push({name : ind, value : val});
    //                     }
    //                 case TYPE_FUNCTION:
    //                     var info = DebugLib.getinfo(storedvar, "S");
    //                     addVars.push({name : "(source)", value : Gmod.tostring(info.short_src),virtual: true,noquote : true});
    //                     addVars.push({name : "(line)", value : info.linedefined,virtual: true});
    //                     for (i in 1...9999) {
    //                         var upv = DebugLib.getupvalue(storedvar,i);
    //                         if (upv.a == null) break;
    //                         addVars.push({name : upv.a, value :upv.b});
    //                     }
    //                 case TYPE_ENTITY:
    //                     var ent:Entity = cast storedvar;
    //                     // trace("bad?");
    //                     var tbl = (storedvar : Entity).GetTable();
    //                     addVars.push({name : "(position)", value :ent.GetPos(),virtual: true});
    //                     addVars.push({name : "(angle)",value : ent.GetAngles(),virtual: true});
    //                     addVars.push({name : "(model)", value : ent.GetModel(),virtual : true});
    //                     for (ind => val in tbl) {
    //                         addVars.push({name : ind, value : val});
    //                     }
    //                 default:
    //             }
    //             var mt = DebugLib.getmetatable(storedvar);
    //             if (mt != null) {
    //                 addVars.push({name : "(metatable)", value : mt});
    //             }
    // 		// storedVariables[ref] = null; ???
    //         case FrameLocal(_,frame,scope):
    //             switch (scope) {
    //                 case FrameLocalScope.Arguments:
    //                     var info = DebugLib.getinfo(frame + 1,"u");
    //                     for (i in 1...info.nparams + 1) {
    //                         var result = DebugLib.getlocal(frame + 1,i);
    //                         if (result.a == null) break;
    //                         // trace('locals ${result.a} ${result.b}');
    //                         addVars.push({name : result.a, value : result.b});
    //                     }
    //                     for (i in 1...9999) {
    //                         var result = DebugLib.getlocal(frame + 1,-i);
    //                         if (result.a == null) break;
    //                         addVars.push({name : result.a, value : result.b});
    //                     }
    //                 case FrameLocalScope.Locals:
    //                     for (i in 1...9999) {
    //                         var result = DebugLib.getlocal(frame + 1,i);
    //                         if (result.a == null) break;
    //                         // trace('locals ${result.a} ${result.b}');
    //                         addVars.push({name : result.a, value : result.b});
    //                     }
    //                     for (i in 1...9999) {
    //                         var result = DebugLib.getlocal(frame + 1,-i);
    //                         if (result.a == null) break;
    //                         addVars.push({name : result.a, value : result.b});
    //                     }
    //                 case FrameLocalScope.Upvalues:
    //                     var info = DebugLib.getinfo(frame + 1,"f");
    //                     if (info != null && info.func != null) {
    //                         for (i in 1...9999) {
    //                             var func = info.func;//otherwise _hx_bind..?
    //                             var upv = DebugLib.getupvalue(func,i);
    //                             if (upv.a == null) break;
    //                             addVars.push({name : upv.a, value : upv.b});
    //                         }
    //                     }
    //                 case FrameLocalScope.Fenv:
    //                     var info = DebugLib.getinfo(frame + 1,"f");
    //                     if (info != null && info.func != null) {
    //                         final func = info.func;
    //                         final tbl = DebugLib.getfenv(func);
    //                         for (i => p in tbl) {
    //                             addVars.push({name : i,value : p});
    //                         }
    //                     }
    //             }
    //         case Global(_,scope):
    //             switch (scope) {
    //                 case ScopeConsts.Globals:
    //                     var _g:AnyTable = untyped __lua__("_G");
    //                     var sort:Array<String> = [];
    //                     var isEnum = function (index:String,value:Dynamic) {
    //                         return NativeStringTools.match(index,"%u",1) != null
    //                         && NativeStringTools.match(index,"%u",2) != null
    //                         && Lua.type(value) == "number";
    //                     }
    //                     var enums:Array<String> = [];
    //                     addVars.push({name : "_G", value : ""});
    //                     for (i => x in _g) {
    //                         if (Lua.type(i) == "string") {
    //                             if (isEnum(i,x)) {
    //                                 enums.push(i);
    //                             } else {
    //                                 sort.push(i);
    //                             }
    //                         }
    //                     }
    //                     // trace("made it past compare");
    //                     for (index in sort) {
    //                         if (Lua.type(index) == "string") {
    //                             addVars.push({name : index, value : Reflect.field(_g,index)});
    //                         }
    //                     }
    //                     // trace("addedvars");
    //                 case ScopeConsts.Players:
    //                     for (i => ply in PlayerLib.GetAll()) {
    //                         trace('players $i $ply');
    //                         addVars.push({name : ply.GetName(), value : ply});
    //                     }
    //                 case ScopeConsts.Entities:
    //                     final ents = EntsLib.GetAll();
    //                     for (i in 1...EntsLib.GetCount()) {
    //                         var ent = ents[i];
    //                         addVars.push({name : ent.GetClass(), value : ent});
    //                     }
    //             }
    //     }
    //     final variablesArr = addVars.map(genvar);
    //     fixupNames(variablesArr);
    //     var resp = req.compose(variables,{variables: variablesArr});
    //     // final old = Gmod.SysTime();
    //     // trace("custom json start");
    //     final js = tink.Json.stringify((cast resp : VariablesResponse)); //in pratical terms they're the same
    //     // trace('custom json end ${Gmod.SysTime() - old}');
    //     resp.sendtink(js);
    //     return WAIT;
    // }

    // static var bpID:Int = 0;

    // static function h_setBreakpoints(x:SetBreakpointsRequest) {
    //     final args = x.arguments.unsafe();
    //     final bpResponse:Array<Breakpoint> = [];
    //     if (args.breakpoints != null) {
    //         final nmpath = args.source.path.sure();
    //         final pathBreakpoints:Map<Int,BreakPoint> = [];
    //         for (bp in args.breakpoints) {
    //             final possibleLocs = DebugLoop.breakLocsCache[Debugee.fullPathToGmod(nmpath).or("")];
    //             var verified = false;
    //             var message:Null<String> = null;
    //             var bpType =
    //                 if (bp.condition == null) {
    //                     NORMAL(bpID++);
    //                 } else {
    //                     final eval = Util.processReturnable(bp.condition);
    //                     switch (Util.compileString(eval,"Gmdebug Conditional BP: ")) {
    //                         case Error(err):
    //                             verified = false;
    //                             message = 'Failed to compile condition $err';
    //                             null;
    //                         case Success(compiledFunc):
    //                             CONDITIONAL(bpID++,compiledFunc);
    //                     }
    //                 }

    //             if (possibleLocs != null) {
    //                 final activeLineStatus = possibleLocs.get(bp.line);
    //                 switch (activeLineStatus) {
    //                     case null:
    //                         verified = true;
    //                         message = "This breakpoint could not be confirmed.";
    //                     case false:
    //                         verified = false;
    //                         message = "Lua does not consider this an active line.";
    //                         bpType = null;
    //                     case true:
    //                         verified = true;
    //                 }
    //             } else {
    //                 verified = true;
    //                 message = "This file has not been visited by running code yet.";
    //             }
    //             bpResponse.push({
    //                 verified : verified,
    //                 message : message,
    //                 line : bp.line
    //             });
    //             if (bpType != null) {
    //                 pathBreakpoints.set(bp.line,bpType);
    //             }
    //         }
    //         final fixpath = Debugee.fullPathToGmod(nmpath).or(nmpath);
    //         DebugLoop.breakpoints.set(fixpath,pathBreakpoints);
    //     }
    //     var resp = x.compose(setBreakpoints,{breakpoints: bpResponse});
    //     final js = tink.Json.stringify((cast resp : SetBreakpointsResponse)); //in pratical terms they're the same
    //     resp.sendtink(js) ;
    //     return WAIT;
    // }

    static function h_stackTrace(x:StackTraceRequest) {
        final args = x.arguments.unsafe();
	if (!Debugee.inpauseloop) {
	    var response = x.compose(stackTrace,{
		stackFrames : [],
		totalFrames : 0 
	    });
	    final js = tink.Json.stringify((cast response : StackTraceResponse)); //in pratical terms they're the same
	    response.sendtink(js);
	    new ComposedEvent(continued,{
		threadId : Debugee.clientID,
		allThreadsContinued : false
	    }).send();
	    return WAIT;
	}
        final firstFrame = switch (args.startFrame) {
            case null:
                Debugee.baseDepth.sure();
            case x:
                x + Debugee.baseDepth.sure();
        }
        final lastFrame = switch (args.levels) {
            case null | 0:
                9999;
            case x:
                firstFrame + (x - 1);
        }
        final stackFrames:Array<StackFrame> = [];
        trace('levels ${args.startFrame} ${args.levels}');
        trace('first ${firstFrame - 1} last $lastFrame stackheight ${Debugee.stackHeight}');
        for (i in firstFrame...lastFrame) {
            trace(i);
            var info = DebugLib.getinfo((i + 1),"lnSfu");
            if (info == null) break;
            var src = switch (info.source.charAt(0)) {
                case "@":
                    @:nullSafety(Off) info.source.substr(1);
                default:
                    info.source;
            }
            var args:String = "";
            if (info.nparams > 0) {
                args = "(";
                for (p in 0...info.nparams) {
                    final lcl = DebugLib.getlocal(i + 1,p + 1);
                    final val = switch (Lua.type(lcl.b)) {
                        case "table":
                            "table";
                        case "string":
                            '"${lcl.b}"';
                        default:
                            Gmod.tostring(lcl.b);
                    }
                    args += '${lcl.a}=$val,'; //${Lua.type(lcl.b)}
                }
                //vargs
                for (p in 1...9999) {
                    final lcl = DebugLib.getlocal(i + 1,-p);
                    if (lcl.a == null) break;
                    final val = switch (Lua.type(lcl.b)) {
                        case "table":
                            "table";
                        case "string":
                            '"${lcl.b}"';
                        default:
                            Gmod.tostring(lcl.b);
                    }
                    args += '${lcl.a}=$val,';
                }
                args = args.substr(0,args.length - 1) + ")";
            }
            var name = switch[info.name,info.namewhat] {
                case [null,NOT_FOUND]:
                    'anonymous function $args';
                // case [null,what]:
                //     'anonymous function ';
                case [name,what]:
                    '[$what] $name $args';
            }
            var path:Null<String>;
            var hint:Null<SourcePresentationHint>;
            var line;
            var column;
            var endLine:Null<Int> = null;
            var endColumn:Null<Int> = null;
            switch (src) {
                case "=[C]":
                    hint = Deemphasize;
                    path = null;
                    line = 0;
                    column = 0;
                case x:
                    path = Debugee.normalPath(x);
                    hint = null;
                    line = info.currentline;
                    column = 1;
                    endLine = info.lastlinedefined;
                    endColumn = 99999;
            }
            hint = Normal;
            if (info.func != null && Exceptions.isExcepted(info.func)) {
                line = 0;
                path = null;
                column = 0;
                hint = Deemphasize;
                name = "Exception catcher";
            } else {
                hint = Normal;
            }
            var target:StackFrame = {
                id: gmdebug.FrameID.encode(Debugee.clientID.sure(),i),
                name: name,
                source: switch path {
                    case null:
                        null;
                    case path:
                        trace(path);
                        var pth = @:nullSafety(Off) path.split("/");
                        {
                        name: pth[pth.length - 1],
                        path: path,
                        presentationHint: hint
                        };
                    },
                line: line,
                column: column,
                endLine: endLine,
                endColumn: endColumn,
                // presentationHint:
            }
            if (path != null) {
                target.source.unsafe().path = path;
            }
            stackFrames.push(target);
        }
        var response = x.compose(stackTrace,{
            stackFrames : stackFrames,
            totalFrames : stackFrames.length
        });
        final js = tink.Json.stringify((cast response : StackTraceResponse)); //in pratical terms they're the same
        response.sendtink(js);
        return WAIT;
    }
}

enum HandlerResponse {
    WAIT;
    CONTINUE;
    DISCONNECT;
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


class UnhandledResponse extends haxe.Exception {

}

enum abstract EvalCommand(String) from String {
    var profile;
}
