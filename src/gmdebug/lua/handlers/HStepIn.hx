package gmdebug.lua.handlers;

class HStepIn implements IHandler<StepInRequest> {
	public function new() {}

	public function handle(stepIn:StepInRequest):HandlerResponse {
		Debugee.state = STEP(null);
		var rep = x.compose(stepIn);
		rep.send();
		DebugLoop.activateLineStepping();
		return CONTINUE;
	}
}
