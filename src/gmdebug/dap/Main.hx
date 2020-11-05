package gmdebug.dap;
import js.Syntax;
import js.node.ChildProcess;
import js.node.console.Console;
import js.node.Process;
import js.node.net.Server;
import js.node.Net;
import js.Node;
import sys.net.Host;
import js.node.net.Socket;
import vscode.debugAdapter.testSupport.DebugClient;
import vscode.debugAdapter.DebugSession;
using Lambda;
class Main {
    
    public static function main() {
        var args = Sys.args().slice(2);
        var port = 0;
        for (arg in args) {
            final portMatch = ~/^--server=(\d{4,5})$/;
            if (portMatch.match(arg)) {
                port = Std.parseInt(portMatch.matched(0));
            }
        }
        if (port > 0) {
            var server = Net.createServer((socket) -> {
                socket.on('end',() -> trace("Closed"));
                final session = new LuaDebugger(false,true);
                session.setRunAsServer(true);
                untyped session.start(socket,socket);
            });
            server.listen(4555,"localhost");
        } else {
            final session = new LuaDebugger(false);
            Node.process.on("SIGTRM", () -> session.shutdown());
            untyped session.start(Node.process.stdin,Node.process.stdout);
            //redirect traces to stderr
            haxe.Log.trace = (v,?infos) -> {
                final str = haxe.Log.formatOutput(v, infos);
                Node.console.error(str);

            };
            trace("started stdin");
        }
    }
}
