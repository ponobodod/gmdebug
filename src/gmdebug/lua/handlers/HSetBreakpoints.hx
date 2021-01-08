package gmdebug.lua.handlers;

import gmdebug.lua.managers.BreakpointManager;
import gmdebug.lib.lua.Protocol;

class HSetBreakpoints implements IHandler<SetBreakpointsRequest> {

    final bm:BreakpointManager;

    public function new(bm:BreakpointManager) {
        this.bm = bm;

    }

    public function handle(req:SetBreakpointsRequest):HandlerResponse {
        final args = req.arguments.unsafe();
		final bpResponse:Array<Breakpoint> = [];
		if (args.breakpoints != null) {
			for (bp in args.breakpoints) {
                final breakPoint = bm.newBreakpoint(args.source,bp);
                bpResponse.push({
                    line : breakPoint.line,
                    message : breakPoint.message,
                    verified : breakPoint.verified
                });
            }
		}
		var resp = req.compose(setBreakpoints, {breakpoints: bpResponse});
		final js = tink.Json.stringify((cast resp : SetBreakpointsResponse)); // in pratical terms they're the same
		resp.sendtink(js);
		return WAIT;
	}
}