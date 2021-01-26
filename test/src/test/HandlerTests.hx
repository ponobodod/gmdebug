package test;


import safety.macro.ArgumentNullCheck.NoCheck;
import gmdebug.VariableReference;
import haxe.PosInfos;
import vscode.debugProtocol.DebugProtocol.StopReason;
import utest.Assert;
import utest.Async;
import gmdebug.composer.ComposedRequest;
import js.Node;
import gmdebug.dap.Handlers.GmDebugLaunchRequestArguments;

using test.TestHelper;
using Lambda;
using tink.CoreApi;
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
        trace("starting test");
        new ComposedRequest(pause,{threadId: 0}).send();
        final pause = session.waitForResponse(pause) && session.waitForEvent(stopped);
        var dothing = @:await pause;
        trace("found both");
        dothing.a.ok();
        new ComposedRequest(_continue,{threadId: 0}).send();
        final cont = @:await session.waitForResponse(_continue);
        cont.ok();
        trace("continued ok");
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

    @:timeout(2000)    
    @:await function testBreakpoint(async:Async) {
        sendBreakpoint();
        var rep = @:await session.waitForResponse(setBreakpoints);
        rep.ok();
        var breakpoint = @:await session.waitForEvent(stopped);
        Assert.equals(StopReason.Breakpoint,breakpoint.body.reason);
        ridBreakpoint();
        @:await session.waitForResponse(setBreakpoints);
        async.done();
    }

    function wait(ms:Int):Future<Noise> {
        return Future.irreversible(function(cb) haxe.Timer.delay(function() cb(Noise), ms));
    }

    @:timeout(2500)
    @:depends(testBreakpoint)
    @:await function testBreakpointOnOff(async:Async) {
        sendBreakpoint();
        var rep = @:await session.waitForResponse(setBreakpoints);
        rep.ok();
        var breakpoint = @:await session.waitForEvent(stopped);
        Assert.equals(StopReason.Breakpoint,breakpoint.body.reason);
        ridBreakpoint();
        @:await session.waitForResponse(setBreakpoints);
        new ComposedRequest(_continue,{
            threadId: 0
        }).send();
        async.setTimeout(600);
        
        final pass = wait(500);
        final stoppedAgain = session.waitForEvent(stopped);
        final result = stoppedAgain || pass;
        result.handle((val) -> {
            trace("dot dot dot");
            switch (val) {
                case Left(_):
                    Assert.fail("Stopped after breakpoint removed");
                case Right(_):
                    trace("pass");
                    Assert.pass();       
            }
            
            async.done();

        });
        
    }

    @:timeout(1000)
    @:depends(testBreakpoint)
    @:await function testStackHeight(async:Async) {
        sendBreakpoint();
        @:await session.waitForEvent(stopped);
        new ComposedRequest(stackTrace,{threadId: 0}).send();
        final stackRep = @:await session.waitForResponse(stackTrace);
        final stackFrames = stackRep.body.stackFrames;
        Assert.equals(1,stackFrames.length,"Incorrect stack height!!!");
        Assert.equals(84,stackFrames[0].line);
        ridBreakpoint();
        @:await session.waitForResponse(setBreakpoints);
        async.done();
    }

    @:timeout(1000)
    @:depends(testStackHeight)
    @:await function testScopes(async:Async) {
        sendBreakpoint();
        @:await session.waitForEvent(stopped);
        new ComposedRequest(stackTrace,{threadId: 0}).send();
        final stackRep = @:await session.waitForResponse(stackTrace);
        final stackFrames = stackRep.body.stackFrames;
        new ComposedRequest(scopes,{frameId: stackFrames[0].id}).send();
        final scopesRep = @:await session.waitForResponse(scopes);
        scopesRep.ok();
        Assert.notEquals(0,scopesRep.body.scopes.length);
        ridBreakpoint();
        @:await session.waitForResponse(setBreakpoints);
        async.done();
    }

    @:timeout(1000)
    @:depends(testStackHeight)
    @:await function testArgs(async:Async) {
        sendBreakpoint();
        @:await session.waitForEvent(stopped);
        new ComposedRequest(stackTrace,{threadId: 0}).send();
        final stackRep = @:await session.waitForResponse(stackTrace);
        final stackFrames = stackRep.body.stackFrames;
        new ComposedRequest(scopes,{frameId: stackFrames[0].id}).send();
        final scopesRep = @:await session.waitForResponse(scopes);
        Assert.isTrue(scopesRep.body.scopes.exists((scope) -> scope.name == "Arguments"),"No arguments scope...");
        new ComposedRequest(variables,{
            variablesReference: VariableReference.encode(FrameLocal(0,stackFrames[0].id,Arguments)),
        }).send();
        final variablesRep = @:await session.waitForResponse(variables);
        variablesRep.ok();
        final variablesArr = variablesRep.body.variables;
        Assert.equals(2,variablesArr.length);
        Assert.equals("name",variablesArr[0].name);
        Assert.equals("gm",variablesArr[1].name);
        ridBreakpoint();
        @:await session.waitForResponse(setBreakpoints);
        async.done();
    }

    @:timeout(1000)
    @:depends(testScopes)
    @:await function testSteps() {
        sendBreakpoint();
        @:await session.waitForEvent(stopped);
        new ComposedRequest(stackTrace,{threadId: 0}).send();
        @:await session.waitForResponse(stackTrace);
        new ComposedRequest(stepIn,{threadId: 0}).send();
        @:await session.waitForEvent(stopped);
        
    }

    @:timeout(2000)
    @:await function teardown(async:Async) {
        session.clearHandlers();
        trace("tearing down...");
        new ComposedRequest(_continue,{threadId: 0}).send();
        final contRep = @:await session.waitForResponse(_continue);
        contRep.ok();
        trace("tore down");
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