package gmdebug.lua;

import gmod.Gmod;
import gmdebug.RequestString;
import gmdebug.ComposedMessage;
import haxe.Constraints.Function;
import lua.Table;
import gmod.libs.DebugLib;
using gmod.PairTools;

class Outputter {

    var ignoreTrace:Bool = false;
    
    public function new() {

    }
    public function hookprint() {
        if (G.__oldprint == null) {
            G.__oldprint = G.print;
        }
        G.print = untyped __lua__("function (...) local succ,err = pcall({0},{1},true,{...}) if not succ then _G.__oldprint(\"Debug output failed: \",err) end if {2}() then _G.__oldprint(...) end end",output,OutputEventCategory.Console,shouldForward);
    }

    function shouldForward() {
	return Debugee.dapMode == Attach;
    }

    function output(cat:OutputEventCategory,print:Bool,vargs:Table<Int,Dynamic>) {
        if (ignoreTrace || Debugee.socket == null) return;
        ignoreTrace = true;
        var out:String = "";
        final arr:Array<Dynamic> = [];
        for (dyn in vargs) {
            out += Gmod.tostring(dyn) + "\t";
            final varref = Handlers.generateVariablesReference(dyn);
            if (varref > 0) {
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
            }
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
                    path: Debugee.normalPath(lineInfo.source),
                };
                body.line = lineInfo.currentline;
            }
        }
        final event = new ComposedEvent(EventString.output,body);
        final js = tink.Json.stringify((cast event : OutputEvent));
        event.sendtink(js);
        ignoreTrace = false;
    }
}
@:native("_G") private extern class G {
    static var __oldprint:Null<Function>;

    static var print:Function;
}