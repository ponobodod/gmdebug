
package gmdebug.lua.handlers;

class HStepIn implements IHandler<NextRequest> {

    public function new() {

    }
    
    public function handle(stepIn:NextRequest):HandlerResponse {
        var resp = x.compose(next);
        trace('our stack height ${Debugee.stackHeight} ${Debugee.stackOffset.step}');
        var tarheight = Debugee.stackHeight - Debugee.stackOffset.step;
        Debugee.state = STEP(tarheight);
        resp.send();
        DebugLoop.activateLineStepping();
        return CONTINUE;
    }
}