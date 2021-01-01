package gmdebug;

#if lua
import gmdebug.lib.lua.Protocol;
#elseif js
import vscode.debugProtocol.DebugProtocol;
#end

typedef AnyRequest = RequestString<Dynamic,Dynamic>;

enum abstract RequestString<X:Request<Dynamic>,Y:Response<Dynamic>>(String) from String to String  {

    var launch:RequestString<LaunchRequest,LaunchResponse>;

    var initialize:RequestString<InitializeRequest,InitializeResponse>;

    var modules:RequestString<ModulesRequest,ModulesResponse>;

    var loadedSources:RequestString<LoadedSourcesRequest,LoadedSourcesResponse>;
    var stepIn:RequestString<StepInRequest,StepInResponse>;

    var stepOut:RequestString<StepOutRequest,StepOutResponse>;

    var next:RequestString<NextRequest,NextResponse>;

    var pause:RequestString<PauseRequest,PauseResponse>;

    var gotoTargets:RequestString<GotoTargetsRequest,GotoTargetsResponse>;
    
    var goto:RequestString<GotoRequest,GotoResponse>;

    var variables:RequestString<VariablesRequest,VariablesResponse>;

    var scopes:RequestString<ScopesRequest,ScopesResponse>;

    var _continue:RequestString<ContinueRequest,ContinueResponse> = "_continue";

    var evaluate:RequestString<EvaluateRequest,EvaluateResponse>;

    var stackTrace:RequestString<StackTraceRequest,StackTraceResponse>;

    var threads:RequestString<ThreadsRequest,ThreadsResponse>;

    var setBreakpoints:RequestString<SetBreakpointsRequest,SetBreakpointsResponse>;

    var configurationDone:RequestString<ConfigurationDoneRequest,ConfigurationDoneResponse>;

    var setExceptionBreakpoints:RequestString<SetExceptionBreakpointsRequest,SetExceptionBreakpointsResponse>;

    var disconnect:RequestString<DisconnectRequest,DisconnectResponse>;

    var breakpointLocations:RequestString<BreakpointLocationsRequest,BreakpointLocationsResponse>;

    var attach:RequestString<AttachRequest,AttachResponse>;

    var setFunctionBreakpoints:RequestString<SetFunctionBreakpointsRequest,SetFunctionBreakpointsResponse>;
}

enum abstract EventString<T:Event<Dynamic>>(String) from String to String {
    var stopped:EventString<StoppedEvent>;

    var output:EventString<OutputEvent>;

    var initialized:EventString<InitializedEvent>;

    var thread:EventString<ThreadEvent>;

    var terminated:EventString<TerminatedEvent>;

    var breakpoint:EventString<BreakpointEvent>;

    var continued:EventString<ContinuedEvent>;

    var exited:EventString<ExitedEvent>;

    var process:EventString<ProcessEvent>;

    var loadedSource:EventString<LoadedSourceEvent>;
    
}
