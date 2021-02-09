package gmdebug.lua.handlers;

class HNext implements IHandler<NextRequest> {
	public function new() {}

	public function handle(nextReq:NextRequest):HandlerResponse {
		var resp = nextReq.compose(next);
		var tarheight = Debugee.stepHeight;
		trace('targeting $tarheight - (${Debugee.stackHeight} ${ StackConst.STEP})');

		Debugee.state = STEP(tarheight);
		resp.send();
		DebugLoop.enableLineStep();
		return CONTINUE;
	}
}
