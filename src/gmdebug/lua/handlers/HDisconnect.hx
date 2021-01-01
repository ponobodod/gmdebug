package gmdebug.lua.handlers;

import gmdebug.lua.handlers.IHandler;

class HDisconnect implements IHandler<DisconnectRequest> {
	public function new() {}

	public function handle(stepIn:DisconnectRequest):HandlerResponse {
		return DISCONNECT;
	}
}
