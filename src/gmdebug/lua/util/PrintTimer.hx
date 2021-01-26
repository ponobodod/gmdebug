package gmdebug.lua.util;

#if !macro
import gmod.Gmod;
#end
class PrintTimer {

    #if !macro
    static var timersArr:Array<Float> = [];

    
    static function _printTimer(ident:Int,time:Float,run:() -> Void) {
        final timer = timersArr[ident];
        if (timer != null) {
            if (Gmod.SysTime() > timer) {
                run();
                timersArr[ident] = Gmod.SysTime() + time;
            }
        } else {
            run();
            timersArr[ident] = Gmod.SysTime() + time;
        }
    }
    #end


    #if macro
    static var nextPrinter = 0;
    #end

    public static macro function print_time(time:Float,run:haxe.macro.Expr) {
        return macro @:privateAccess gmdebug.lua.util.PrintTimer._printTimer($v{nextPrinter++},$v{time},$run);
    }
}

