package gmdebug;

typedef GmDebugMessage<T> = ProtocolMessage & {
	// type : String,
	msg:GmMsgType<T>,
	body:T
}

enum abstract GmMsgType<T>(Int) to Int {
	var playerAdded:GmMsgType<GMPlayerAddedMessage>;
	var playerRemoved:GmMsgType<GMPlayerRemovedMessage>;
	var clientID:GmMsgType<GMClientID>;
	var intialInfo:GmMsgType<GmDebugIntialInfo>;
	var serverInfo:GmMsgType<GMServerInfoMessage>;
}

enum abstract DapModeStr(String) {
	var Attach;
	var Launch;
}

typedef GmDebugIntialInfo = {
	/**
		Location. Can be server or client.
	**/
	location:String,

	?dapMode:DapModeStr,
	?autoLaunch:Bool
}

typedef GMPlayerAddedMessage = {
	/** ID of client. **/
	playerID:Int,

	/** name of client **/
	name:String
}

typedef GMPlayerRemovedMessage = {
	/** ID of client **/
	playerID:Int
}

typedef GMClientID = {
	/**
		Thread number given
	**/
	id:Int
}

typedef GMServerInfoMessage = {
	ip:String,

	isLan:Bool
}

typedef GmDebugAttachRequest = Request<GmDebugAttachRequestArguments>;

typedef GmDebugBaseRequestArguments = {
	/**
		REQUIRED The path to the servers "garrysmod" folder. Must be fully qualified.
	**/
	serverFolder:String,

	/**
		The paths to client(s) "garrysmod" folder. Must be fully qualified.
	**/
	?clientFolders:Array<String>
}

typedef GmDebugAttachRequestArguments = AttachRequestArguments & GmDebugBaseRequestArguments;

typedef GmDebugLaunchRequest = Request<GmDebugLaunchRequestArguments>;

typedef GmDebugLaunchRequestArguments = LaunchRequestArguments &
	GmDebugBaseRequestArguments & {
	/**
		REQUIRED The path to batch file or script used to launch your server
	**/
	programPath:String,

	?programArgs:Array<String>,
	/**
		If you wish to log the output.
	**/
	?fileOutput:String
}