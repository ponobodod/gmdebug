package gmdebug.lua.handlers;

class HDummy implements IHandler<Request> {

    public function new() {

    }

    //see ComposeTools.compose
    public function handle() {
        var response = new ComposedResponse(req,body);
        response.success = true;
        response.send();
        return WAIT;
    }
}