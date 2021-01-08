package gmdebug.lua.handlers;

import gmdebug.composer.RequestString;
import gmdebug.composer.ComposedResponse;

class HDummy implements IHandler<Request<Dynamic>> {
	
	public function new() {}

	// see ComposeTools.compose
	public function handle(req:Request<Dynamic>):HandlerResponse {
		var response = new ComposedResponse(req, {});
		response.success = true;
		response.send();
		return WAIT;
	}
}
