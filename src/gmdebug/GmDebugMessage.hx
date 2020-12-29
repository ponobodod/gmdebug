package gmdebug;

typedef GmDebugMessage<T> = ProtocolMessage & {
    // type : String,
    msg : GmMsgType<T>,
    body : T
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

    ?dapMode : DapModeStr,

    ?autoLaunch : Bool

}

typedef GMPlayerAddedMessage = {
    /** ID of client. **/
    playerID : Int,
    /** name of client **/
    name : String
}

typedef GMPlayerRemovedMessage = {
    /** ID of client **/
    playerID : Int
}

typedef GMClientID = {
    /**
	Thread number given
    **/
    id : Int
}

typedef GMServerInfoMessage = {

    ip : String,

    isLan : Bool
 
}