package gmdebug.composer;


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