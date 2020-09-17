package gmdebug.lua;

import gmod.libs.GameLib;
import gmdebug.Cross.MessageResult;
import gmod.libs.MathLib;
import gmdebug.lua.Handlers;
import gmdebug.ComposedMessage.ComposedGmDebugMessage;
import gmod.libs.Scripted_entsLib;
import haxe.io.Input;
import gmdebug.lua.LuaSocket.DebugIO;
import gmdebug.Cross.CommMethod;
import gmdebug.lua.Protocol.TOutputEvent;
import gmdebug.lua.Protocol.OutputEventCategory;
import gmdebug.RequestString;
import lua.Table;
import lua.Table.AnyTable;
import haxe.Log;
import lua.NativeStringTools;
import gmod.libs.FileLib;
import gmod.Gmod;
import haxe.Constraints.Function;
import lua.Lua;
import gmod.libs.PlayerLib;
import gmod.gclass.Player;
import lua.lib.luasocket.socket.TcpClient;
import gmod.Hook.GMHook;
import gmod.libs.HookLib;
import gmod.libs.TimerLib;
import gmdebug.lua.Protocol.TStoppedEvent;
import gmdebug.lua.Protocol.StopReason;
import gmdebug.ComposedMessage.ComposedEvent;
import lua.Debug;
import gmdebug.lua.Protocol.Request;
import haxe.Json;
import gmod.libs.DebugLib;
using Lambda;
import gmod.gclass.Entity;
using StringTools;
using gmdebug.ComposeTools;
using gmod.PairTools;
using tink.CoreApi;
using Safety;
using gmod.WeakTools;

@:keep
class Debugee {

    
    public static var clientID:Int = 0;

    public static var state:DebugState = WAIT;

    public static var active:Bool = false;

    public static var inpauseloop = false;


    public static var playerThreads:Array<Null<Player>> = [];

    public static var stackOffset = {
        step : 4, // was 5
        stepDebugLoop : 5, // was 6
        except : 5,
        pause : 5 //was 9
    };

    public static var minheight:Int = 3;

    public static var baseDepth:Null<Int>;

    public static var stackHeight(get,never):Int;

    @:noCompletion
    public static function get_stackHeight():Int {
        for (i in 1...999999) {
            if (DebugLib.getinfo(i + 1,"") == null) {
                return i;
            }
        }
        throw "No stack height";
    }
    
    public static var tracing = false;

    static var hooksActive = false;

    //SENT BY DAP
    static var methodsPossible:Map<CommMethod,Bool> = [
        Pipe => true
    ];

    static var socket(default,set):Null<DebugIO>;

    //SENT BY DEBUG CLIENT
    public static var dest = "";

    @:noCompletion
    static function set_socket(sock) {
	G.previousSocket = sock;
	return socket = sock;
    }
    

    public static var measure = true;

    public static var shouldDebug = true;

    static var ignoreTrace = false;
    
    @:access(sys.net.Socket)
    public static function start() {
        if (active) return false;
        for (comMethod in methodsPossible.keys()) {
            try {
                socket = switch (comMethod) {
                    case Pipe:
                        new PipeSocket();
                    case Socket:
                        final sock = new LuaSocket();
                        sock.setTimeout(0);
                        sock.connect(cast {ip : "127.0.0.1",host : "localhost"},56789);
                        final s_:TcpClient = cast sock._socket;
                        s_.setoption(KeepAlive,true);
                        s_.setoption(TcpNoDelay,true);
			sock;
                }
            } catch (e) {
                trace('failed to start $e');
                socket = null;
            }
        }
        if (socket == null) {
            return false;
        }
        trace("attached to server");
        active = true;
        var ce = new ComposedEvent(initialized);
        ce.send();
	#if debugdump
	FileLib.CreateDir("gmdebugdump");
	Gmod.collectgarbage("collect");
	Mri.DumpMemorySnapshot("gmdebugdump","Before",-1);
	#end
        #if server
        hookPlayer();
        new ComposedEvent(continued,{threadId : 0,allThreadsContinued : true}).send();
        #end
        hookprint();
        getAllBpLines();
        Debug.sethook(DebugLoop.debugloop,"c");
        // debugLoopState |= Call;
        hooksActive = true;
        return true;
    }

    static function getAllBpLines(?_searchTable:AnyTable,?_depth:Int) {
        final searchTable:AnyTable = _searchTable.or(untyped __lua__("_G"));
        final depth = _depth.or(0);
        if (depth > 3) {return;}
        for (_ => p in searchTable) {
            switch (Lua.type(p)) {
                case "function":
                    DebugLoop.addLineInfo(cast p);
                case "table":
                    getAllBpLines(cast p,depth + 1);
                case "entity":
                    if (Gmod.IsValid(p)) {
                        getAllBpLines((cast p : Entity).GetTable(),depth + 1);
                    }
            }
        }
    }
    
    static function hookprint() {
        if (G.__oldprint == null) {
            G.__oldprint = G.print;
        }
        G.print = untyped __lua__("function (...) local succ,err = pcall({0},{1},true,...) if not succ then _G.__oldprint(\"Debug output failed: \",err) end _G.__oldprint(...) end",output,OutputEventCategory.Console);
    }

    static function output(cat:OutputEventCategory,print:Bool,vargs:Table<Int,Dynamic>) {
        if (ignoreTrace || socket == null) return;
        ignoreTrace = true;
        var out:String = "";
        final arr:Array<Dynamic> = [];
        for (dyn in vargs) {
            out += dyn + "\t";
            final varref = Handlers.generateVariablesReference(dyn);
            if (varref > -1) {
                arr.push(dyn);
            }
        }
        out += "\n";
        final body:TOutputEvent = {
            category: Stdout,
            output: out,
            variablesReference: switch (arr.length) {
                case 0:
                    null;
                default:
                    Handlers.generateVariablesReference(arr);
            },
        }
        var lineInfo = DebugLib.getinfo(4,"Slf"); //+ 1 for handler functions ect.
        if (print && lineInfo != null) {
            final meta = DebugLib.getmetatable(untyped __lua__("lineInfo.func"));
            if (meta != null) {
                if (meta.printHandler != null) {
                    lineInfo = DebugLib.getinfo(6,"Slf");
                }
            }
            if (lineInfo != null && lineInfo.source != "") {
                final pth = @:nullSafety(Off) lineInfo.source.split("/");
                body.source = {
                    name: pth[pth.length - 1],
                    path: normalPath(lineInfo.source),
                };
                body.line = lineInfo.currentline;
            }
        }
        final event = new ComposedEvent(EventString.output,body);
        event.send();
        ignoreTrace = false;
    }

    @:access(sys.net.Socket)
    public inline static function writeJson(json:String) { //x:Dynamic
        var str:String = untyped __lua__("{0} .. {1} .. {2} .. {3}","Content-Length: ",json.length,"\r\n\r\n",json);
        socket.output.unsafe().writeString(str); //awful perfomance with non native writing
        socket.output.unsafe().flush();
    }

    static final ignores:Map<String,Bool> = [];

    //currently only on first lines for now. can expand to tracebacks.
    static inline function checkIgnoreError(_err:String) {
        return ignores.exists(_err);
    }

    static inline function ignoreError(_err:String) {
        ignores.set(_err,true);
    }

    #if server
    static function hookPlayer() {
        playerThreads = [];
        HookLib.Add(PlayerInitialSpawn,"debugee-newplayer",(ply,_) -> {
            new ComposedGmDebugMessage(playerAdded,{
		name : ply.Name(),
		playerID : ply.UserID()
	    }).send();
        });
        HookLib.Add(PlayerDisconnected,"debugee-byeplayer",(ply) -> {
            new ComposedGmDebugMessage(playerRemoved,{
		playerID : ply.UserID()
	    }).send();
        });
        for (ply in PlayerLib.GetAll()) {
            new ComposedGmDebugMessage(playerAdded,{
		name : ply.Name(),
		playerID : ply.UserID()
	    }).send();
        }
    }
    #end

    @:expose("__gmdebugTraceback")
    static function traceback(err:String) {
        var _err = DebugLib.traceback(err,3);
        var arr = @:nullSafety(Off) _err.split("\n");
        //getting rid of error handling trace lines
        arr.splice(-3,2);
        _err = arr.join("\n");
        if (checkIgnoreError(err)) return _err;
        if (Debugee.inpauseloop || tracing) {trace("no..."); return _err;}
        #if server
        if (!active && Jit.checkCanActivateJit()) {
            final result = Jit.jitCheck(err,_err);
            if (!result) return _err;
        }
        #end
        if (!hooksActive) return _err;
        if (!active) return _err;
        tracing = true;
        startHaltLoop(Exception,stackOffset.except,err);
        tracing = false;
        return DebugLib.traceback(err);
    }
    


    inline static function recvMessage(x:Input):MessageResult {
        // trace("reading...");
        socket.unsafe().output.writeString("\004");
        socket.unsafe().output.flush();
        // trace('reading took ${Gmod.SysTime() - start}');
        return Cross.recvMessage(x);
    }

    public static function poll() {
        if (socket == null) return;
        // if (Debugee.inpauseloop) return;
        var data:Request<Dynamic> ;
        try {
            data = switch ((recvMessage(socket.unsafe().input)) : MessageResult ) {
                case ACK:
                    return;
                case MESSAGE(msg):
                    msg;
            };
        } catch (e:String) {
            if (e == "Error : timeout") {
                return;
            } else {
                throw e;
            }
        } catch (e:haxe.io.Eof) {
            trace("eof");
            abortDebugee();
            return;
        }
        trace(data.command);
        if (chooseHandler(data) == DISCONNECT) {
            abortDebugee();
        }
    }

    static var mapcache:Map<String,Option<String>> = [];

    static function readMap(x:String):Option<String> {
        if (mapcache == null) return None;
        var map = mapcache.get(x);
        if (map != null) return map;
        var mapfile = FileLib.Read('${NativeStringTools.sub(x,2)}.map',GAME);
        if (mapfile == null) {
            var val = None;
            mapcache.set(x,val);
            return val;
        } 
        var tbl = Json.parse(mapfile);
        var newfile = Some('${tbl.sourceroot}${tbl.source[1]}');
        mapcache.set(x,newfile);
        return newfile;
    }


    public static function main() {
        Debug.sethook();
	if (G.previousSocket != null) {
	    G.previousSocket.close();
	}
        Log.trace = function(v,?infos) {
            var str = Log.formatOutput(v,infos.unsafe());
            untyped __lua__("_hx_print_2({0})",str);
        }
        trace(NativeStringTools.rep("abcdefghijklmnopqrstuvwxyz",45));
        trace("Hello from debugee");
        if (methodsPossible.exists(Pipe)) {
            FileLib.CreateDir("gmdebug");
        }
	#if server
	GameLib.ConsoleCommand("sv_timeout 99999\n");
	// GameLib.ConsoleCommand("sv_timeout_signon 99999\n");
	#elseif client
	Gmod.RunConsoleCommand("cl_timeout",99999);
	#end
	#if client
	Jit.init();
	#end
        TimerLib.Create("debugee-start",3,0,() -> {
            #if server
	    Jit.jitActivate();
	   
            #end
	    
	    
            try {start();

	    }
            catch (ee:String) {
                socket.run((sock) -> sock.close());
                trace("closed socket on error");
		
                throw ee;
            }
        });
        TimerLib.Create("report-profling",3,0,() -> {
            DebugLoopProfile.report();
        });
        TimerLib.Create("debugee-poll",0.1,0,() -> {
            shouldDebug = false;
	    poll();
            // Lua.xpcall(,
            //     (err) -> trace(Debug.traceback(err,3))
            // );
            shouldDebug = true;
        });
	HookLib.Remove(GMHook.Think,"woopee");
        // var timer = Gmod.CurTime() + 30;
        // HookLib.Add(GMHook.Think,"woopee",() -> {
        //     if (Gmod.CurTime() > timer) {
        //         timer = Gmod.CurTime() + 30;
        //         var x:Null<Int> = null;
        //         untyped __lua__("print(x + 5)");
        //     }
        // });
        var timer2 = 0.0;
        HookLib.Add(GMHook.Think,"execute-order", () -> {
            if (Gmod.CurTime() > timer2) {
                timer2 = Gmod.CurTime() + 4;
                final x = MathLib.random(1,10);
                trace(x);
            }
        });
    }

    public static function normalPath(x:String):String {
        if (x.charAt(0) == "@") {
            x = @:nullSafety(Off) x.substr(1);
        }
        x = '$dest$x';
        return x;
    }

    public static function startHaltLoop(reason:StopReason,bd:Int,?txt:String) {
        Debugee.inpauseloop = true;
        baseDepth = bd;
        final tstop:TStoppedEvent = {
            threadId : Debugee.clientID,
            allThreadsStopped: false,
            reason : reason,
            text: txt
        }
        trace("sending stopped");
        var e = new ComposedEvent(stopped,tstop);
        e.send();
        haltLoop();
    }

    #if debugdump

    @:expose("stopDump")
    public static function stopDump() {
	Gmod.collectgarbage("collect");
	Mri.DumpMemorySnapshot("gmdebugdump","after",-1);
	Mri.DumpMemorySnapshotComparedFile("gmdebugdump","Compared",-1,"gmdebugdump/LuaMemRefInfo-All-[]-[before].txt","gmdebugdump/LuaMemRefInfo-All-[]-[after].txt");
    }

    #end
    
    public static function abortDebugee() {
        Debug.sethook();
        socket.run((sock) -> {
            sock.close();
            socket = null;
        });
        hooksActive = false;
        socket = null;
        active = false;
        trace("Debugging aborted");
        Exceptions.unhookGamemodeHooks();
	Exceptions.unhookEntityHooks();

    }

    public static function haltLoop() {
        while (true) {
            var msg;
            try {
                msg = switch(recvMessage(socket.unsafe().input)) {
                case ACK: //CLEANUP maybe change to thrown exception for consistency
                    continue;
                case MESSAGE(msg):
                    msg;
                };
            } catch (s:String) {
                if (s != "Error : timeout") {
                    abortDebugee();
                    throw s;
                } else {
                    continue;
                }
            }
            switch (chooseHandler(msg)) {
                case WAIT:
                case CONTINUE:
                    break;
                case DISCONNECT:
                    abortDebugee();
                    break;
            }
        }
        // trace("halt loop exited");
        Debugee.inpauseloop = false;
    }

    static function chooseHandler(incoming:{type : String}):HandlerResponse {
        return switch (incoming.type) {
            case null:
                throw "message sent to us had a null type";
            case "gmdebug":
                CustomHandlers.handle(cast incoming);
                WAIT; //this is a safe option in all scenarios.
            case MessageType.Request:
                Handlers.handlers(cast incoming);
            default:
                throw "message sent to us had an unknown type";
        }
    }



    public static function fullPathToGmod(fullPath:String):Null<String> {
        if (fullPath.contains(Debugee.dest)) {
            var result = fullPath.replace(Debugee.dest,"");
            result = "@" + result;
            return result;
        } else {
            return null;
        }
    }



}

enum OutputType {
    Console;
    Stdout;
    Stderr;
}

typedef LineMap = Map<Int,Bool>;

//TODO
@:native("_G") private extern class G {

    static var __oldprint:Null<Function>;

    static var print:Function;

    static var previousSocket:Null<DebugIO>;
}

enum DebugState {
    WAIT;
    STEP(targetHeight:Null<Int>);
    OUT(outFunc:Function,lowestLine:Int);
}


#if debugdump
@:native("_G.mri.m_cMethods")
extern class Mri {

    static function DumpMemorySnapshot(prefix:String,name:String,dunno:Int):Void;

    static function DumpMemorySnapshotComparedFile(prefix:String,name:String,dunno:Int,before:String,after:String):Void;
}
#end