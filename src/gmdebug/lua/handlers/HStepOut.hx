package gmdebug.lua.handlers;

class HStepOut implements IHandler<StepOutRequest> {

    public function new() {

    }
    
    public function handle(stepIn:StepOutRequest):HandlerResponse {
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
}