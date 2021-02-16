package test;

import gmdebug.dap.LuaDebugger;
import gmdebug.composer.ComposedRequest;
import gmdebug.composer.RequestString;
import vscode.debugProtocol.DebugProtocol.Response;
import utest.Assert;

class TestHelper {

    public static function ok(x:Response<Dynamic>) {
        Assert.isTrue(x.success);
    }

    public static function is<T:Response<Dynamic>>(x:T,string:RequestString<Dynamic,T>) {
        Assert.equals(string,x.command);
    }

    public static function send(x:ComposedRequest<Dynamic,Dynamic>,luaDebug:LuaDebugger) {
        luaDebug.handleMessage(x);
    }


}