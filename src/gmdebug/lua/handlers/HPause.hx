package gmdebug.lua.handlers;

import gmdebug.lua.handlers.IHandler.HandlerResponse;

class HPause implements IHandler<PauseRequest> {
	public function new() {}

	public function handle(pauseReq:PauseRequest):HandlerResponse {
		var rep = pauseReq.compose(pause, {});
		rep.send();
		Debugee.startHaltLoop(Pause,  StackConst.PAUSE);
		return WAIT;
	}
}
