package gmdebug.lua.handlers;

interface IHandler<T:Request<Dynamic>> {
	function handle(req:T):HandlerResponse;
}

enum HandlerResponse {
	WAIT;
	CONTINUE;
	DISCONNECT;
	CONFIG_DONE;
}
