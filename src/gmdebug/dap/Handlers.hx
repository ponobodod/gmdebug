package gmdebug.dap;

import js.Node;
import js.node.Buffer;
import js.node.child_process.ChildProcess;
import js.node.fs.Stats;
import js.node.Fs;
import gmdebug.composer.*;
import gmdebug.composer.*;
import gmdebug.RequestString;
import vscode.debugProtocol.DebugProtocol;
import gmdebug.VariableReference;

using gmdebug.composer.ComposeTools;
using Lambda;
using Safety;
using StringTools;

typedef HasThreadID = {
	arguments:{
		threadId:Int
	}
}

class Handlers {
	public static function handle(req:Request<Dynamic>) {
		final command:AnyRequest = req.command;
		switch (command) {
			case pause | stackTrace | stepIn | stepOut | next | "continue":
				final id = (req : HasThreadID).arguments.threadId;
				LuaDebugger.inst.sendToClient(id, req);
			case attach:
				h_attach(req);
			case disconnect:
				h_disconnect(req);
			case launch:
				h_launch(req);
			case scopes:
				h_scopes(req);
			case variables:
				h_variables(req);
			case evaluate:
				h_evaluate(req);
			case setBreakpoints:
				h_setBreakpoints(req);
			case setExceptionBreakpoints:
				h_setExceptionBreakpoints(req);
			case setFunctionBreakpoints:
				h_setFunctionBreakpoints(req);
			case initialize:
				h_initialize(req);
			case configurationDone:
				LuaDebugger.inst.sendToServer(req);
			case threads:
				h_threads(req);

			case loadedSources | modules | goto | gotoTargets | breakpointLocations | _continue: // _continue: ARRRRGGGHHHH
				LuaDebugger.inst.sendToServer(req);
		}
	}

	// TODO remove
	static function sendAll(x:Request<Dynamic>) {
		LuaDebugger.inst.sendToAll(x);
	}

	static var latestBreakpoint:Null<SetBreakpointsRequest> = null;

	static function h_setBreakpoints(x:SetBreakpointsRequest) {
		latestBreakpoint = x;
		sendAll(x);
	}

	static function h_threads(x:ThreadsRequest) {
		final threadArr = [{name: "Server", id: 0}];
		for (i in 1...LuaDebugger.clients.length) {
			threadArr.push({
				name: LuaDebugger.mapClientName.get(i),
				id: i
			});
		}
		x.compose(threads, {threads: threadArr}).send();
	}

	static var latestExceptionBP:Null<SetExceptionBreakpointsRequest> = null;

	static function h_setExceptionBreakpoints(x:SetExceptionBreakpointsRequest) {
		latestExceptionBP = x;
		sendAll(x);
	}

	static function h_disconnect(x:DisconnectRequest) {
		sendAll(x);
		x.compose(disconnect).send();
		LuaDebugger.inst.shutdown();
	}

	static var latestFunctionBP:Null<SetFunctionBreakpointsRequest> = null;

	static function h_setFunctionBreakpoints(x:SetFunctionBreakpointsRequest) {
		latestFunctionBP = x;
		sendAll(x);
	}

	static function h_variables(x:VariablesRequest) {
		final ref:VariableReference = x.arguments.variablesReference;
		if ((ref : Int) <= 0) {
			trace("invalid variable reference");
			x.compose(variables, {variables: []}).send();
			return;
		}
		switch (ref.getValue()) {
			case Global(clID, _) | FrameLocal(clID, _, _) | Child(clID, _):
				LuaDebugger.inst.sendToClient(clID, x);
		}
	}

	static function h_evaluate(x:EvaluateRequest) {
		final expr = x.arguments.expression;
		if (expr.charAt(0) == "/") {
			switch (LuaDebugger.dapMode) {
				case LAUNCH(child):
					final actual = expr.substr(1);
					child.stdin.write(actual + "\n");
					x.compose(evaluate, {
						result: "",
						variablesReference: 0
					}).send();
					return;
				default:
			}
		}
		final client = switch (x.arguments.frameId) {
			case null:
				0; // run as server if not in frame context. might cause issues...
			case frame:
				(frame : FrameID).getValue().clientID;
		}
		LuaDebugger.inst.sendToClient(client, x);
	}

	static function h_initialize(x:InitializeRequest) {
		final response:InitializeResponse = {
			seq: 0, // it gets ignored anyway
			request_seq: x.seq,
			command: "initialize",
			type: Response,
			body: {},
			success: true,
		}
		response.body.supportsConfigurationDoneRequest = true;
		response.body.supportsFunctionBreakpoints = true;
		response.body.supportsConditionalBreakpoints = true;
		response.body.supportsEvaluateForHovers = true;
		response.body.supportsLoadedSourcesRequest = true;
		response.body.supportsFunctionBreakpoints = true;
		response.body.supportsBreakpointLocationsRequest = false;
		// response.body.exceptionBreakpointFilters = switch (client) {
		//     case Vscode | Emacs:
		//         null;
		//     // case Vscode:
		//     //     [{filter: "all",label: "All errors"},
		//     //      {filter: "hooks",label: "Gamemode hooks"},
		//     //      {filter: "entities",label: "Entity hooks"}];
		// }
		LuaDebugger.inst.sendResponse(response);
	}

	static function h_launch(x:GmDebugLaunchRequest) {
		final serverFolder = x.arguments.serverFolder;
		if (!validateServerFolder(serverFolder, x))
			return;
		// handle windows stuff here
		final programPath = switch (x.arguments.programPath) {
			case null:
				x.composeFail("Gmdebug requires the property \"programPath\" to be specified when launching.", {
					id: 2,
					format: "Gmdebug requires the property \"programPath\" to be specified when launching",
				}).send();
				return;
			case "auto":
				'$serverFolder/../srcds_run';
			case path:
				path;
		}
		if (!validateProgramPath(programPath, x))
			return;
		final arrArgs = x.arguments.programArgs.or([]);
		var argResult = "";
		for (arg in arrArgs) {
			argResult += arg + " ";
		}
		final childProcess = js.node.ChildProcess.spawn('script -c \'$programPath -norestart $argResult\' /dev/null', {
			cwd: haxe.io.Path.directory(programPath),
			env: Node.process.env,
			shell: true
		});
		childProcess.stdout.on("data", (str:Buffer) -> {
			new ComposedEvent(output, {
				category: Stdout,
				output: str.toString().replace("\r", ""),
				data: null
			}).send();
		});
		childProcess.stderr.on("data", (str:Buffer) -> {
			new ComposedEvent(output, {
				category: Stdout,
				output: str.toString(),
				data: null
			}).send();
		});
		childProcess.on("error", (err) -> {
			new ComposedEvent(output, {
				category: Stderr,
				output: err.message + "\n" + err.stack,
				data: null
			}).send();
			trace("Child process error///");
			trace(err.message);
			trace(err.stack);
			trace("Child process error end///");
			LuaDebugger.inst.shutdown();
			return;
		});

		// nodebug?
		setupDebugger(serverFolder);
		final clientFolders = x.arguments.clientFolders.or([]);
		for (ind => client in clientFolders) {
			if (!validateClientFolder(client, x)) {
				return;
			}
			clientFolders[ind] = haxe.io.Path.addTrailingSlash(client);
		}
		final serverSlash = haxe.io.Path.addTrailingSlash(x.arguments.serverFolder);
		LuaDebugger.inst.serverFolder = serverSlash;
		LuaDebugger.inst.clientLocations = clientFolders;
		LuaDebugger.dapMode = LAUNCH(childProcess);
		LuaDebugger.inst.startServer(Pipe, x);
	}

	static function h_scopes(x:ScopesRequest) {
		final client = (x.arguments.frameId : FrameID).getValue().clientID; // mandatory
		LuaDebugger.inst.sendToClient(client, x);
	}

	static function setupDebugger(serverFolder:String) {
		final addonFolder = haxe.io.Path.join([serverFolder, "addons"]);
		final debugFolder = haxe.io.Path.join([addonFolder, "debugee-auto"]);
		if (!Fs.existsSync(debugFolder)) {
			js.node.ChildProcess.execSync('cp -r ../generated $addonFolder', {cwd: haxe.io.Path.directory(Sys.programPath())}); // todo fix for windows
		}
	}

	static function h_attach(x:GmDebugAttachRequest) {
		final serverFolder = x.arguments.serverFolder;
		if (!validateServerFolder(serverFolder, x))
			return;
		final clientFolders = x.arguments.clientFolders.or([]);
		for (ind => client in clientFolders) {
			if (!validateClientFolder(client, x)) {
				return;
			}
			clientFolders[ind] = haxe.io.Path.addTrailingSlash(client);
		}
		final serverSlash = haxe.io.Path.addTrailingSlash(x.arguments.serverFolder);
		LuaDebugger.inst.serverFolder = serverSlash;
		LuaDebugger.inst.clientLocations = clientFolders;
		LuaDebugger.inst.startServer(Pipe, x);
	}

	static function validateProgramPath(programPath:String, launchReq:GmDebugLaunchRequest) {
		final valid = if (programPath == null) {
			launchReq.composeFail("Gmdebug requires the property \"programPath\" to be specified when launching.", {
				id: 2,
				format: "Gmdebug requires the property \"programPath\" to be specified when launching",
			}).send();
			false;
		} else {
			if (!Fs.existsSync(programPath)) {
				launchReq.composeFail("The program specified by \"programPath\" does not exist!", {
					id: 4,
					format: "The program specified by \"programPath\" does not exist!"
				}).send();
				false;
			} else if (!Fs.statSync(programPath).isFile()) {
				launchReq.composeFail("The program specified by \"programPath\" is not a file.", {
					id: 5,
					format: "The program specified by \"programPath\" is not a file.",
				}).send();
				false;
			} else {
				true;
			}
		}
		if (!valid) {
			LuaDebugger.inst.shutdown();
		}
		return valid;
	}

	static function validateServerFolder(serverFolder:String, attachReq:GmDebugAttachRequest) {
		final valid = if (serverFolder == null) {
			attachReq.composeFail("Gmdebug requires the property \"serverFolder\" to be specified.", {
				id: 2,
				format: "Gmdebug requires the property \"serverFolder\" to be specified.",
				showUser: true,
				variables: {}
			}).send();
			false;
		} else {
			final addonFolder = js.node.Path.join(serverFolder, "addons");
			if (!haxe.io.Path.isAbsolute(serverFolder)) {
				attachReq.composeFail("Gmdebug requires the property \"serverFolder\" to be an absolute path (i.e from root folder).", {
					id: 3,
					format: "Gmdebug requires the property \"serverFolder\" to be an absolute path (i.e from root folder).",
				}).send();
				false;
			} else if (!Fs.existsSync(serverFolder)) {
				attachReq.composeFail("The \"serverFolder\" path does not exist!", {
					id: 4,
					format: "The \"serverFolder\" path does not exist!"
				}).send();
				false;
			} else if (!Fs.statSync(serverFolder).isDirectory()) {
				attachReq.composeFail("The \"serverFolder\" path is not a directory.", {
					id: 5,
					format: "The \"serverFolder\" path is not a directory.",
				}).send();
				false;
			} else if (!Fs.existsSync(addonFolder) || !Fs.statSync(addonFolder).isDirectory()) {
				attachReq.composeFail("\"serverFolder\" does not seem to be a garrysmod directory. (looking for \"addons\" folder)", {
					id: 6,
					format: "\"serverFolder\" does not seem to be a garrysmod directory. (looking for \"addons\" folder)",
				}).send();
				false;
			} else {
				true;
			}
		}
		if (!valid) {
			LuaDebugger.inst.shutdown();
		}
		return valid;
	}

	static function validateClientFolder(folder:String, attachReq:GmDebugAttachRequest) {
		final addonFolder = js.node.Path.join(folder, "addons");
		final gmdebug = js.node.Path.join(folder, "data", "gmdebug");
		final valid = if (!haxe.io.Path.isAbsolute(folder)) {
			attachReq.composeFail('Gmdebug requires client folder: $folder to be an absolute path (i.e from root folder).', {
				id: 8,
				format: 'Gmdebug requires client folder: $folder to be an absolute path (i.e from root folder).',
			}).send();
			false;
		} else if (!Fs.existsSync(folder)) {
			attachReq.composeFail('The client folder: $folder does not exist!', {
				id: 9,
				format: 'The client folder: $folder does not exist!'
			}).send();
			false;
		} else if (!Fs.statSync(folder).isDirectory()) {
			attachReq.composeFail('The client folder: $folder is not a directory.', {
				id: 10,
				format: 'The client folder: $folder is not a directory.',
			}).send();
			false;
		} else if (!Fs.existsSync(addonFolder) || !Fs.statSync(addonFolder).isDirectory()) {
			attachReq.composeFail('The client folder: $folder does not seem to be a garrysmod directory. (looking for \"addons\" folder)', {
				id: 11,
				format: 'The client folder: $folder does not seem to be a garrysmod directory. (looking for \"addons\" folder)',
			}).send();
			false;
		} else {
			true;
		}
		if (!valid) {
			LuaDebugger.inst.shutdown();
		}
		return valid;
	}
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
