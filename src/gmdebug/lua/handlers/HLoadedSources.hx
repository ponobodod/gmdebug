package gmdebug.lua.handlers;

class HLoadedSources implements IHandler<LoadedSourcesRequest> {

    public function new() {
        
    }

    public function handle(load:LoadedSourcesRequest) {
        var resp = load.compose(loadedSources, {sources: []});
		resp.send();
		return WAIT;
    }
}