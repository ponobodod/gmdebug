package gmdebug.lua;

class FunctionBreakpointManager implements IHandler<SetFunctionBreakpointsRequest> {

    final functionBP = new haxe.ds.ObjectMap<Function,Bool>();

    public function new() {
	
    }
    
    public function handle(req:SetFunctionBreakpointsRequest) {
        final args = x.arguments.unsafe();
        functionBP.clear();
        //candidate for map and yucky functional ect.
        final bpResponse:Array<Breakpoint> = [];
        for (fbp in args.breakpoints) {
            final eval = Util.processReturnable(fbp.name);
            final resp:Breakpoint = switch (Util.compileString(eval,"gmdebug FuncBp:")) {
                case Error(err):
                    {
                        verified : false,
                        message : "Failed to compile" 
                    };
                case Success(Util.runCompiledFunction(_) => Error(err)):
                    {
                        verified : false,
                        message : "Failed to run" 
                    };
                case Success(Util.runCompiledFunction(_) => Success(result))
                    if (Lua.type(result) != "function"):
                    {
                        verified : false,
                        message : "Result is not a function" //TODO add error message 
                    };
                case Success(Util.runCompiledFunction(_) => Success(func)):
                    functionBP.set(func,true);
                    {
                        verified : true
                    }
            }
            bpResponse.push(resp);
        }
        final resp = x.compose(setFunctionBreakpoints, {
            breakpoints : bpResponse
        });
        resp.send();
        return WAIT;
    }

    public function bpSet(x:Function) {
	return functionBP.exists(x);
    }

}