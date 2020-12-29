package gmdebug.composer;

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