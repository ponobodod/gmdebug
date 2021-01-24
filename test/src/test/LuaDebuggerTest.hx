package test;

import tink.core.Callback.CallbackLinkRef;
import tink.CoreApi.CallbackLink;
import tink.CoreApi.Future;
import gmdebug.composer.ComposedRequest;
import sys.FileSystem;
import gmdebug.composer.RequestString;
import gmdebug.composer.EventString;
import utest.Async;
import vscode.debugProtocol.DebugProtocol.Event;
import vscode.debugProtocol.DebugProtocol.Response;
import vscode.debugProtocol.DebugProtocol.ProtocolMessage;
import gmdebug.dap.LuaDebugger;
using Lambda;

class LuaDebuggerTest extends LuaDebugger {

    public function new(?x,?y) {
        super(x,y);
        eventEvents = [];
        responseEvents = [];
    }

    var eventEvents:Map<String,Array<(x:Dynamic)->Void>>;

    var responseEvents:Map<String,Array<(x:Dynamic)->Void>>;
    
    override public function handleMessage(message:ProtocolMessage) {
        super.handleMessage(message);
    }

    public function clearHandlers() {
        eventEvents = [];
        responseEvents = [];
    }

    override function sendResponse<T>(response:Response<T>) {
        final responseName = response.command;
        if (responseEvents.exists(responseName)) {
            responseEvents.get(responseName).iter((fun) -> fun(response));
            responseEvents.remove(responseName);
        }
    }

    override function sendEvent<T>(event:Event<T>) {
        final eventName = event.event;
        if (eventEvents.exists(eventName)) {
            eventEvents.get(eventName).iter((fun) -> fun(event));
            eventEvents.remove(eventName);
        }
    }

    override function shutdown() {
        switch (dapMode) {
			case LAUNCH(child):
				child.stdin.write("quit\n");
				child.kill();
			default:
		}
		for (ind => client in clients) {
			client.writeS.write(composeMessage(new ComposedRequest(disconnect, {})));
			client.readS.end();
			client.writeS.end();
			FileSystem.deleteFile(clientFiles[ind].read);
			FileSystem.deleteFile(clientFiles[ind].write);
		}
		clients.resize(0);
    }

    function _waitForEvent<T:Event<Dynamic>>(message:EventString<T>,listener:(event:T)->Void) {
        final arr = eventEvents.get(message);
        if (arr != null) {
            arr.push(listener);
        } else {
            eventEvents.set(message,[listener]);
        }
        
    }

    function _waitForResponse<T:Response<Dynamic>>(message:RequestString<Dynamic,T>,listener:(response:T)->Void) {
        final arr = responseEvents.get(message);
        if (arr != null) {
            arr.push(listener);
        } else {
            responseEvents.set(message,[listener]);
        }
    }

    public function waitForEvent<T:Event<Dynamic>>(message:EventString<T>):Future<T> {
        return Future.irreversible(_waitForEvent.bind(message));
    }

    public function waitForResponse<T:Response<Dynamic>>(message:RequestString<Dynamic,T>) {
        return Future.irreversible(_waitForResponse.bind(message));
    }

    


}