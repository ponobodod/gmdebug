package gmdebug.composer;

#if js
import gmdebug.dap.LuaDebugger;

#end

class ComposedResponse<T> extends ComposedProtocolMessage {
	/**
		Sequence number of the corresponding request.
	**/
	var request_seq:Int;

	/**
		Outcome of the request.
		If true, the request was successful and the 'body' attribute may contain the result of the request.
		If the value is false, the attribute 'message' contains the error in short form and the 'body' may contain additional information (see 'ErrorResponse.body.error').
	**/
	public var success:Bool = true;

	/**
		The command requested.
	**/
	public var command:String;

	/**
		Contains error message if success == false.
		This raw error might be interpreted by the frontend and is not shown in the UI.
		Some predefined values exist.
		Values:
		'cancelled': request was cancelled.
		etc.
	**/
	public var message:Null<String>;

	/**
		Contains request result if success is true and optional error details if success is false.
	**/
	public var body:Null<T>;

	@:allow(gmdebug.Event.Request_2)
	public function new<X:Request<Dynamic>>(req:X, body:T) {
		super(Response);
		request_seq = req.seq;
		command = req.command;
		this.body = body;
	}

	#if js
	public inline function send() {
		trace('sending from dap $command');
		LuaDebugger.inst.sendResponse(cast this); // pls work :)
	}
	#end
}
