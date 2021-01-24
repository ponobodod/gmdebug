package test;

import haxe.PosInfos;
import tink.CoreApi.Future;
import vscode.debugProtocol.DebugProtocol.StopReason;
import utest.Assert;
import utest.Async;
import gmdebug.composer.ComposedRequest;
import js.Node;
import gmdebug.dap.Handlers.GmDebugLaunchRequestArguments;

using test.TestHelper;

@:await class HandlerTests extends utest.Test {

    var session:LuaDebuggerTest;

    @:timeout(10000)
    @:await public function setupClass(async:Async) {
        session = new LuaDebuggerTest(false);
        Node.process.on("SIGTRM", () -> session.shutdown());
        untyped session.start(Node.process.stdin, Node.process.stdout);
        
        // redirect traces to stderr
        haxe.Log.trace = (v, ?infos) -> {
            final str = haxe.Log.formatOutput(v, infos);
            Node.console.error(str);
        };
        final launchArgs:GmDebugLaunchRequestArguments = {
            serverFolder: "/home/g/gmodDS/garrysmod/",
            programPath: "auto"
        }
        new ComposedRequest(launch,launchArgs).send();
        @:await session.waitForEvent(initialized);
        new ComposedRequest(configurationDone,{}).send();
        async.done();
    }

    @:timeout(1000)
    @:await function testPause(async:Async) {
        new ComposedRequest(pause,{threadId: 0}).send();
        final pause = @:await session.waitForResponse(pause);
        pause.ok();
        @:await session.waitForEvent(stopped);
        new ComposedRequest(_continue,{threadId: 0}).send();
        final cont = @:await session.waitForResponse(_continue);
        cont.ok();
        async.done();
    }

    function sendBreakpoint() {
        new ComposedRequest(setBreakpoints,{
            source: {path: "/home/g/gmodDS/garrysmod/lua/includes/modules/hook.lua"},
            breakpoints: [{
                line: 84,
            }]
        }).send();
    }

    function ridBreakpoint() {
        new ComposedRequest(setBreakpoints,{
            source: {path : "/home/g/gmodDS/garrysmod/lua/includes/modules/hook.lua"},
            breakpoints: []
        }).send();
    }

    @:timeout(1000)    
    @:await function testBreakpoint(async:Async) {
        sendBreakpoint();
        var rep = @:await session.waitForResponse(setBreakpoints);
        rep.ok();
        var breakpoint = @:await session.waitForEvent(stopped);
        Assert.equals(StopReason.Breakpoint,breakpoint.body.reason);
        ridBreakpoint();
        async.done();
    }

    @:timeout(1000)
    @:await function testStackHeight(async:Async) {
        sendBreakpoint();
        @:await session.waitForEvent(stopped);
        new ComposedRequest(stackTrace,{threadId: 0}).send();
        final stackRep = @:await session.waitForResponse(stackTrace);
        final stackFrames = stackRep.body.stackFrames;
        Assert.equals(1,stackFrames.length,"Incorrect stack height!!!");
        Assert.equals(84,stackFrames[0].line);
        ridBreakpoint();
        async.done();
    }

    @:timeout(1000)
    @:await function teardown(async:Async) {
        session.clearHandlers();
        new ComposedRequest(_continue,{threadId: 0}).send();
        final contRep = @:await session.waitForResponse(_continue);
        contRep.ok();
        session.clearHandlers();
        async.done();
    }

    public function teardownClass() {
        new ComposedRequest(disconnect,{}).send();
    }

    public function new() {
        super();
    }


}