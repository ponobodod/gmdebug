package gmdebug.lua;

import sys.net.Host;
import haxe.io.Encoding;
import lua.lib.luasocket.socket.TcpClient;
import sys.net.Socket;

interface DebugIO {
    var input(default,null):haxe.io.Input;
    var output(default,null):haxe.io.Output;
    function close():Void;
}

class LuaSocket extends Socket implements DebugIO {

    override function connect(host:Host, port:Int) {
        super.connect(host, port);
        output = new SimpleLSOutput(cast _socket);
	final tcpClient:TcpClient = cast _socket;
	tcpClient.setoption(KeepAlive,true);
	tcpClient.setoption(TcpNoDelay,true);
    }
    
}

class SimpleLSOutput extends haxe.io.Output {

    var tcp:TcpClient;

    public function new(tcp:TcpClient) {
	this.tcp = tcp;
    }

    override function writeString(s:String, ?encoding:Encoding) {
	tcp.send(s);
    }
}
