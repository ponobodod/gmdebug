
package gmdebug.lua;

import gmdebug.ComposedMessage;
import gmod.libs.GameLib;
import gmdebug.GmDebugMessage;
import gmod.Gmod;
class CustomHandlers {

    public static function handle(x:GmDebugMessage<Dynamic>) {
        switch (x.msg) {
            case clientID:
                h_clientID(cast x);
	        case intialInfo:
		        h_initalInfo(cast x);
            case playerAdded | playerRemoved | serverInfo:
		throw "dur";
        }

    }

    static function h_clientID(x:GmDebugMessage<GMClientID>) {
        trace('recieved id ${x.body.id}');
        Debugee.clientID = x.body.id;
    }


    static function isLan() {
	return Gmod.GetConVar("sv_lan").GetBool();
    }

    static function h_initalInfo(x:GmDebugMessage<GmDebugIntialInfo>) {
	Debugee.dest = x.body.location;
	if (x.body.dapMode == Launch) {
	    new ComposedGmDebugMessage(serverInfo,{
		ip : GameLib.GetIPAddress(),
		isLan : isLan() 
	    }).send();
	    Debugee.dapMode = Launch;
	} else {
	    Debugee.dapMode = Attach;
	}
	
    }
}
