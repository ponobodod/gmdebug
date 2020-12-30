package gmdebug.lua.handlers;

class HDisconnect implements IHandler<DisconnectRequest> {

    public function new() {

    }
    
    public function handle(stepIn:DisconnectRequest):HandlerResponse {
        return DISCONNECT;
    }
}