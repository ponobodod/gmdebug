package gmdebug.lua.handlers;

class HStepIn implements IHandler<StepInRequest> {
	public function new() {}

	public function handle(stepInReq:StepInRequest):HandlerResponse {
		Debugee.state = STEP(null);
		var rep = stepInReq.compose(stepIn);
		rep.send();
		DebugLoop.enableLineStep();
		return CONTINUE;
	}
}
