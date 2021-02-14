package gmdebug.dap; 

using gmdebug.composer.ComposeTools;

class DapFailureTools {
	
	/** True if sent error **/
	public static function sendError(opt:haxe.ds.Option<DapFailure>,req:Request<Dynamic>,luaDebug:LuaDebugger) {
		return switch (opt) {
			case Some(err):
				req.composeFail(err.message,{
					id : err.id,
					format : err.message
				}).send(luaDebug);
				true;
			default:	
				false;
		}
	}

	public inline static function noError(err:haxe.ds.Option<DapFailure>) {
		return err == None;
	}
}

/**
	A simple message type is not enough to construct a user facing error in vscode..
**/
typedef DapFailure = {
	id : Int,
	message : String
}