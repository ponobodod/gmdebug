package gmdebug.composer;

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
