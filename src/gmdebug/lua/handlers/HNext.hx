package gmdebug.lua.handlers;

class HNext implements IHandler<NextRequest> {
	public function new() {}

	public function handle(nextReq:NextRequest):HandlerResponse {
		var resp = nextReq.compose(next);
		var tarheight = Debugee.stepHeight;
		trace('targeting $tarheight - (${Debugee.stackHeight} ${Debugee.stackOffset.step})');

		Debugee.state = STEP(tarheight);
		resp.send();
		DebugLoop.activateLineStepping();
		return CONTINUE;
	}
}
