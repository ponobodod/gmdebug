package gmdebug.composer;

import gmdebug.GmDebugMessage;
import haxe.Json;
#if lua
import gmdebug.lua.Debugee;
import gmod.Gmod;
#elseif js
import gmdebug.dap.LuaDebugger;
#end

/**
 * Using a small subset of features. Don't really need more than this.
 **/
class ComposedGmDebugMessage<T> extends ComposedProtocolMessage {

    public var msg:GmMsgType<T>;
    public var body:T;
    public function new(msg:GmMsgType<T>,body:T) {
        super("gmdebug");
        this.msg = msg;
        this.body = body;
    }

}