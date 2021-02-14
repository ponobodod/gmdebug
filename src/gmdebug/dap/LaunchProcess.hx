package gmdebug.dap;

import js.Node;
import js.node.Buffer;
import gmdebug.composer.ComposedEvent;

using StringTools;

class LaunchProcess {

    var childProcess:js.node.child_process.ChildProcess;

    public function new(programPath:String,luaDebug:LuaDebugger,?programArgs:Array<String>) {
        programArgs = programArgs.or([]);
		var argString = "";
		for (arg in programArgs) {
			argString += arg + " ";
		}
        
        childProcess = js.node.ChildProcess.spawn('script -c \'$programPath -norestart $argString +sv_hibernate_think 1\' /dev/null', {
			cwd: haxe.io.Path.directory(programPath),
			env: Node.process.env,
			shell: true
		});
		childProcess.stdout.on("data", (str:Buffer) -> {
			new ComposedEvent(output, {
				category: Stdout,
				output: str.toString().replace("\r", ""),
				data: null
			}).send(luaDebug);
		});
		childProcess.stderr.on("data", (str:Buffer) -> {
			new ComposedEvent(output, {
				category: Stdout,
				output: str.toString(),
				data: null
			}).send(luaDebug);
		});
		childProcess.on("error", (err) -> {
			new ComposedEvent(output, {
				category: Stderr,
				output: err.message + "\n" + err.stack,
				data: null
			}).send(luaDebug);
			trace("Child process error///");
			trace(err.message);
			trace(err.stack);
			trace("Child process error end///");
			luaDebug.shutdown();
			return;
		});
    }

    public function write(chunk:Dynamic) {
        childProcess.stdin.write(chunk);

    }

    public function kill() {
        childProcess.kill();
    }

    //read?
}