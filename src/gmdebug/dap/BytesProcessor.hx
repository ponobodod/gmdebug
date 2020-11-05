package gmdebug.dap;

import haxe.Json;
import js.node.Buffer;
import haxe.io.Bytes;
import haxe.io.BytesInput;

class BytesProcessor {

    public var fillRequested(default,null):Bool = false;

    var prevClientResults:Array<Null<RecvMessageResponse>> = [];

    var prevBytes:Array<Null<haxe.io.Bytes>> = [];

    var lastGoodPos:Int = 0;

    public function new() {

    }

    public function process(jsBuf:Buffer,clientNo:Int):Array<ProtocolMessage> {
	fillRequested = false;
	var bytes:Bytes = jsBuf.hxToBytes();
	bytes = conjoinHandle(bytes,clientNo);
	return processBytes(bytes,clientNo);
    }

    function processBytes(rawBytes:Bytes,clientNo:Int):Array<ProtocolMessage> {
	final input = new BytesInput(rawBytes);
        return try {
	    addMessages(input,clientNo);
        } catch (e:haxe.io.Eof) { 
	    lastGoodPos = input.position; 
	    prevClientResults[clientNo] = null;
	    prevBytes[clientNo] = rawBytes.sub(lastGoodPos,rawBytes.length - lastGoodPos);
	    [];
        } catch (e:String) {
	    lastGoodPos = input.position; 
	    prevClientResults[clientNo] = null;
	    prevBytes[clientNo] = rawBytes.sub(lastGoodPos,rawBytes.length - lastGoodPos);
            trace(e);
	    [];
	} catch(e) {
	    throw e;
	}
    }

    function addMessages(inp:BytesInput,clientNo:Int):Array<ProtocolMessage> {
	final messages:Array<ProtocolMessage> = [];
	while (inp.position != inp.length
	    && skipAcks(inp)) {
	    final prevResult = prevClientResults[clientNo];
	    final result:RecvMessageResponse = switch (prevResult) {
		case null | Completed(_):
		    recvMessage(inp);
		case Unfinished(_, remaining):
		    recvMessage(inp,remaining);
	    }
	    prevClientResults[clientNo] = switch [prevResult,result] {
		case [Unfinished(prevString,_),Completed(curString)]:
		    messages.push(Json.parse(prevString + curString));
		    result;
		case [_,Completed(str)]:
		    messages.push(Json.parse(str));
		    result;
		case [Unfinished(prevString,_),Unfinished(curString,remain)]:
		    Unfinished(prevString + curString,remain);
		case [_,Unfinished(_,_)]:
		    result; 
	    }
	}
	return messages;
    }

    function conjoinHandle(curBytes:haxe.io.Bytes,clientNo:Int):haxe.io.Bytes {
	final oldByte = prevBytes[clientNo];
	return if (oldByte != null) {
	    final conjoinedBytes = Bytes.alloc(oldByte.length + curBytes.length);
	    conjoinedBytes.blit(0,oldByte,0,oldByte.length);
	    conjoinedBytes.blit(oldByte.length,curBytes,0,curBytes.length);
	    prevBytes[clientNo] = null;
	    conjoinedBytes;
	} else {
	    curBytes;
	}
    }

    function recvMessage(input:BytesInput,?remaining:Int):RecvMessageResponse {
        //need to conjoin and parse here, lol....
        if (remaining == null) {remaining = Cross.readHeader(input);}
        var bufRemaining = input.length - input.position;
        if (remaining > bufRemaining) { 
            var str = input.readString(bufRemaining,UTF8);
            remaining -= bufRemaining;
            return Unfinished(str,remaining);
        } else {
            var str = input.readString(remaining,UTF8);
            return Completed(str);
        }   
    }

    function skipAcks(inp:BytesInput):Bool {
        for (_ in inp.position...inp.length) {
            final byt = inp.readByte();
            if (byt != 4) {
                inp.position--;
                return true;
            } else {
                fillRequested = true;
            }
        }
        return false;
    }

}

enum RecvMessageResponse {
    Completed(x:String);
    Unfinished(x:String,remaining:Int);
}