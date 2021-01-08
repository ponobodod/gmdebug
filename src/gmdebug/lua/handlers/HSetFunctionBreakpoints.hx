package gmdebug.lua.handlers;

import gmdebug.lua.managers.FunctionBreakpointManager;

class HSetFunctionBreakpoints implements IHandler<SetFunctionBreakpointsRequest> {


    final fbm:FunctionBreakpointManager;

    public function new(fbm:FunctionBreakpointManager) {
        this.fbm = fbm;
    }

    public function handle(req:SetFunctionBreakpointsRequest) {
		final args = req.arguments.unsafe();
		fbm.functionBP.clear();
		// candidate for map and yucky functional ect.
		final bpResponse:Array<Breakpoint> = [];
		for (fbp in args.breakpoints) {
			final eval = Util.processReturnable(fbp.name);
			final resp:Breakpoint = switch (Util.compileString(eval, "gmdebug FuncBp:")) {
				case Error(err):
					{
						verified: false,
						message: "Failed to compile"
					};
				case Success(Util.runCompiledFunction(_) => Error(err)):
					{
						verified: false,
						message: "Failed to run"
					};
				case Success(Util.runCompiledFunction(_) => Success(result)) if (Lua.type(result) != "function"):
					{
						verified: false,
						message: "Result is not a function" // TODO add error message
					};
				case Success(Util.runCompiledFunction(_) => Success(func)):
					fbm.functionBP.set(func, true);
					{
						verified: true
					}
			}
			bpResponse.push(resp);
		}
		final resp = req.compose(setFunctionBreakpoints, {
			breakpoints: bpResponse
		});
		resp.send();
		return WAIT;
	}
}