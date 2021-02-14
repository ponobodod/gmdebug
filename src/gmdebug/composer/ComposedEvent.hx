package gmdebug.composer;

#if js
import gmdebug.dap.LuaDebugger;
#end

class ComposedEvent<T> extends ComposedProtocolMessage {
	/**
		Type of event.
	**/
	public var event:EventString<Dynamic>;

	/**
		Event-specific information.
	**/
	public var body:Null<T>;

	public function new(str:EventString<Event<T>>, ?body:T) {
		super(Event);
		event = str;
		this.body = body;
	}

	#if js
	public inline function send(luaDebug:LuaDebugger) {
		trace('sending from dap $event');
		luaDebug.sendEvent(cast this); // pls work :)
	}
	#end
}
