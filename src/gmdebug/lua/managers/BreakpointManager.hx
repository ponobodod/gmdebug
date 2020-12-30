package gmdebug.lua;

class BreakpointManager implements IHandler<SetBreakpointsRequest>  {

    var breakLocsCache:Map<String,Map<Int,Bool>> = [];

    var breakpoints(default,null):Map<String,Map<Int,BreakPoint>> = [];

    var bpID:Int = 0;

    public function retrieveSourceLineInfo(source:String):Map<Int,Bool> {
        return switch (breakLocsCache.get(source)) {
            case null:
                var map:Map<Int,Bool> = [];
                breakLocsCache.set(source,map);
                map;
            case x:
                x.unsafe();
        }
    }

    public function getForLine(line:Int):Map<Int,Breakpoint>  {
	return bp.get(line);
    }

    public function handle(req:SetBreakpointsRequest):HandlerResponse {
        final args = x.arguments.unsafe();
        final bpResponse:Array<Breakpoint> = [];
        if (args.breakpoints != null) {
            final nmpath = args.source.path.sure();
            final pathBreakpoints:Map<Int,BreakPoint> = [];
            for (bp in args.breakpoints) {
                final possibleLocs = breakLocsCache[Debugee.fullPathToGmod(nmpath).or("")];
                var verified = false;
                var message:Null<String> = null;
                var bpType =
                    if (bp.condition == null) {
                        NORMAL(bpID++);
                    } else {
                        final eval = Util.processReturnable(bp.condition);
                        switch (Util.compileString(eval,"Gmdebug Conditional BP: ")) {
                            case Error(err):
                                verified = false;
                                message = 'Failed to compile condition $err';
                                null;
                            case Success(compiledFunc):
                                CONDITIONAL(bpID++,compiledFunc);
                        }
                    }

                if (possibleLocs != null) {
                    final activeLineStatus = possibleLocs.get(bp.line);
                    switch (activeLineStatus) {
                        case null:
                            verified = true;
                            message = "This breakpoint could not be confirmed.";
                        case false:
                            verified = false;
                            message = "Lua does not consider this an active line.";
                            bpType = null;
                        case true:
                            verified = true;
                    }
                } else {
                    verified = true;
                    message = "This file has not been visited by running code yet.";
                }
                bpResponse.push({
                    verified : verified,
                    message : message,
                    line : bp.line
                });
                if (bpType != null) {
                    pathBreakpoints.set(bp.line,bpType);
                }
            }
            final fixpath = Debugee.fullPathToGmod(nmpath).or(nmpath);
            DebugLoop.breakpoints.set(fixpath,pathBreakpoints);
        }
        var resp = x.compose(setBreakpoints,{breakpoints: bpResponse});
        final js = tink.Json.stringify((cast resp : SetBreakpointsResponse)); //in pratical terms they're the same
        resp.sendtink(js) ;
        return WAIT;
    }
}

enum BreakPoint {
    NORMAL(id:Int);
    CONDITIONAL(id:Int,condition:Function);
}