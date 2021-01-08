package gmdebug.lua.handlers;

class HNext implements IHandler<NextRequest> {
	public function new() {}

	public function handle(nextReq:NextRequest):HandlerResponse {
		var resp = nextReq.compose(next);
		trace('our stack height ${Debugee.stackHeight} ${Debugee.stackOffset.step}');
		var tarheight = Debugee.stackHeight - Debugee.stackOffset.step;
		Debugee.state = STEP(tarheight);
		resp.send();
		DebugLoop.activateLineStepping();
		return CONTINUE;
	}
}
