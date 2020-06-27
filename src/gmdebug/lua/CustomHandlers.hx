
package gmdebug.lua;

import gmdebug.Cross.GMClientID;
import gmdebug.Cross.GmDebugMessage;
import gmdebug.Cross.GmDebugIntialInfo;
class CustomHandlers {

    public static function handle(x:GmDebugMessage<Dynamic>) {
        switch (x.msg) {
            case clientID:
                h_clientID(cast x);
	    case intialInfo:
		h_initalInfo(cast x);
            case playerAdded | playerRemoved:
		throw "dur";
        }

    }

    static function h_clientID(x:GmDebugMessage<GMClientID>) {
        trace('recieved id ${x.body.id}');
        Debugee.clientID = x.body.id;
    }

    static function h_initalInfo(x:GmDebugMessage<GmDebugIntialInfo>) {
	Debugee.dest = x.body.location;
    }
}
