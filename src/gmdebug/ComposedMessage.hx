package gmdebug;

import gmdebug.GmDebugMessage;
import haxe.Json;
import gmdebug.RequestString;
#if lua
import gmdebug.lua.Debugee;
import gmod.Gmod;
#elseif js
import gmdebug.dap.LuaDebugger;
#end
class ComposedProtocolMessage {

    public var seq:Int = 0;
    public var type:MessageType;

    public function new(_type:MessageType) {
        type = _type;
    }

    #if lua
    public inline function send() {
        // final old = Gmod.SysTime();
        // trace("json start");
        var js = Json.stringify(this);
        // trace('json end ${Gmod.SysTime() - old}');
        // Debugee.writeJson(this);
        Debugee.writeJson(js);
    }
    public inline function sendtink(x:String) {
        Debugee.writeJson(x);
    }
    #end

}

class ComposedEvent<T> extends ComposedProtocolMessage {

    /**
	    Type of event.
    **/
    public var event:EventString<Dynamic>;

    /**
	    Event-specific information.
    **/
    public var body:Null<T>;


    public function new(str:EventString<Event<T>>,?body:T) {
        super(Event);
        event = str;
        this.body = body;
    }


    #if js
    public inline function send() {
	trace('sending from dap $event');
        LuaDebugger.inst.sendEvent(cast this); // pls work :)
    }
    #end
    
}


class ComposedRequest<T,X> extends ComposedProtocolMessage {

    /**
		The command to execute.
	**/
	public var command:RequestString<Request<T>,Dynamic>;

	/**
		Object containing arguments for the command.
	**/
	public var arguments:Null<T>;

    public function new(str:RequestString<Request<T>,Response<X>>,?args:T) {
        super(Request);
        command = str;
        args = arguments;
    }

}

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
    public function new<X:Request<Dynamic>>(req:X,body:T) {
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

/**
 * Using a small subset of features. Don't really need more than this.
 **/
class ComposedGmDebugMessage<T> extends ComposedProtocolMessage {

    public var msg:GmMsgType<T>;
    public var body:T;
    public function new(msg:GmMsgType<T>,body:T) {
        super("gmdebug");
        this.msg = msg;
        this.body = body;
    }

}
