package gmdebug.lua.handlers;

import gmod.libs.DebugLib;

using Lambda;
using gmod.PairTools;

class HStepOut implements IHandler<StepOutRequest> {
	public function new() {}

	public function handle(stepOutReq:StepOutRequest):HandlerResponse {
		var tarheight = Debugee.stepHeight - 1;
		trace('stepOut ${tarheight < StackConst.MIN_HEIGHT} : $tarheight ${StackConst.MIN_HEIGHT}');
		if (tarheight <= StackConst.MIN_HEIGHT) {
			final info = DebugLib.getinfo(Debugee.baseDepth.unsafe() + 1, "fLSl");
			final func = info.func;
			trace('${info.source}');
            final activeLines = info.activelines;
			final lowest = activeLines.keys().fold((line, res) -> {
				return if (line < res) {
					line;
				} else {
					res;
				}
			}, cast Math.POSITIVE_INFINITY);
			trace('lowest $lowest');
			Debugee.state = OUT(func, lowest - 1,tarheight + 1); //lowest - 1, as call hook starts on first line
		} else {
			Debugee.state = STEP(tarheight);
		}
		DebugLoop.enableLineStep();
		final stepoutResp = stepOutReq.compose(stepOut);
		stepoutResp.send();
		return CONTINUE;
	}
}
