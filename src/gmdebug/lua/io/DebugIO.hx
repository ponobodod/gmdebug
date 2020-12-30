package gmdebug.lua.io;

interface DebugIO {
    var input(default,null):haxe.io.Input;

    var output(default,null):haxe.io.Output;

    function close():Void;
}