package gmdebug.dap;

import gmdebug.composer.RequestString;
import js.Node;
import js.node.Buffer;
import js.node.child_process.ChildProcess;
import js.node.fs.Stats;
import js.node.Fs;
import gmdebug.composer.*;
import vscode.debugProtocol.DebugProtocol;
import gmdebug.VariableReference;
import gmdebug.GmDebugMessage;
import haxe.io.Path as HxPath;
using gmdebug.composer.ComposeTools;
using gmdebug.dap.DapFailure; 
using Lambda;
using Safety;
using StringTools;


class RequestRouter {

	var luaDebug:LuaDebugger;

	var clients:ClientStorage;

	var prevRequests:PreviousRequests;

	public function new(luaDebug:LuaDebugger,clients:ClientStorage,prevRequests:PreviousRequests) {
		this.luaDebug = luaDebug;
		this.clients = clients;
		this.prevRequests = prevRequests;
	}

	public function route(req:Request<Dynamic>) {
		final command:AnyRequest = req.command;
		switch (command) {
			case pause | stackTrace | stepIn | stepOut | next | "continue":
				final id = (req : HasThreadID).arguments.threadId;
				clients.sendAny(id, req);
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
				prevRequests.update(req);
				clients.sendAll(req);	
			// h_setBreakpoints(req);
			case setExceptionBreakpoints:
				prevRequests.update(req);
				clients.sendAll(req);
			case setFunctionBreakpoints:
				prevRequests.update(req);
				clients.sendAll(req);
			case initialize:
				h_initialize(req);
			case configurationDone:
				clients.sendServer(req);
			case threads:
				h_threads(req);
			case loadedSources | modules | goto | gotoTargets | breakpointLocations | _continue: // _continue: ARRRRGGGHHHH
				clients.sendServer(req);
		}
	}

	function h_threads(req:ThreadsRequest) {
		final threadArr = [{name: "Server", id: 0}];
		for (cl in clients.getClients()) {
			threadArr.push({
				name : cl.gmodName,
				id : cl.clID
			});
		} 
		req.compose(threads, {threads: threadArr}).send(luaDebug);
	}

	function h_disconnect(req:DisconnectRequest) {
		clients.sendAll(req);
		req.compose(disconnect).send(luaDebug);
		luaDebug.shutdown();
	}

	function h_variables(req:VariablesRequest) {
		final ref:VariableReference = req.arguments.variablesReference;
		if ((ref : Int) <= 0) {
			trace("invalid variable reference");
			req.compose(variables, {variables: []}).send(luaDebug);
			return;
		}
		switch (ref.getValue()) {
			case Global(clID, _) | FrameLocal(clID, _, _) | Child(clID, _):
				clients.sendAny(clID, req);
		}
	}

	function h_evaluate(req:EvaluateRequest) {
		final expr = req.arguments.expression;
		if (expr.charAt(0) == "/") {
			switch (luaDebug.dapMode) {
				case LAUNCH(child):
					final actual = expr.substr(1);
					child.write(actual + "\n");
					req.compose(evaluate, {
						result: "",
						variablesReference: 0
					}).send(luaDebug);
					return;
				default:
			}
		}
		final client = switch (req.arguments.frameId) {
			case null:
				0; // run as server if not in frame context. might cause issues...
			case frame:
				(frame : FrameID).getValue().clientID;
		}
		clients.sendAny(client, req);
	}

	function h_initialize(req:InitializeRequest) {
		final response:InitializeResponse = {
			seq: 0, // it gets ignored anyway
			request_seq: req.seq,
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
		response.body.supportsDelayedStackTraceLoading = true;
		response.body.supportsBreakpointLocationsRequest = false;
		
		luaDebug.sendResponse(response);
	}

	function h_launch(req:GmDebugLaunchRequest) {
		final serverFolder = req.arguments.serverFolder;
		final serverFolderResult = validateServerFolder(serverFolder);
		if (serverFolderResult != None) {
			serverFolderResult.sendError(req,luaDebug);
			return;
		}
		// handle windows stuff here
		final programPath = switch (req.arguments.programPath) {
			case null:
				req.composeFail("Gmdebug requires the property \"programPath\" to be specified when launching.", {
					id: 2,
					format: "Gmdebug requires the property \"programPath\" to be specified when launching",
				}).send(luaDebug);
				return;
			case "auto":
				'$serverFolder/../srcds_run';
			case path:
				path;
		}
		final programPathResult = validateProgramPath(programPath);
		if (programPathResult != None) {
			programPathResult.sendError(req,luaDebug);
			return;
		}
		luaDebug.shouldAutoConnect = req.arguments.autoConnectLocalGmodClient.or(false);
		var childProcess = new LaunchProcess(programPath,luaDebug,req.arguments.programArgs);
		if (req.arguments.noDebug) {
			luaDebug.dapMode = LAUNCH(childProcess);
			
			luaDebug.serverFolder = HxPath.normalize(HxPath.addTrailingSlash(req.arguments.serverFolder));
			final comp = (req : LaunchRequest).compose(launch,{});
			comp.send(luaDebug);
			return;
		}
		copyLuaFiles(serverFolder);
		final clientFolders = req.arguments.clientFolders.or([]);
		for (ind => client in clientFolders) {
			final clientFolderResult = validateClientFolder(client);
			if (clientFolderResult != None) {
				clientFolderResult.sendError(req,luaDebug);
				return;
			}
			clientFolders[ind] = HxPath.normalize(HxPath.addTrailingSlash(client));
		}
		final serverSlash = HxPath.normalize(HxPath.addTrailingSlash(req.arguments.serverFolder));
		luaDebug.serverFolder = serverSlash;
		luaDebug.setClientLocations(clientFolders);
		luaDebug.dapMode = LAUNCH(childProcess);
		luaDebug.startServer(req);
	}

	function h_scopes(req:ScopesRequest) {
		final client = (req.arguments.frameId : FrameID).getValue().clientID; // mandatory
		clients.sendAny(client, req);
	}

	function copyLuaFiles(serverFolder:String) {
		final addonFolder = HxPath.join([serverFolder, "addons"]);
		final debugFolder = HxPath.join([addonFolder, "debugee"]);
		js.node.ChildProcess.execSync('cp -r ../generated/debugee $addonFolder', {cwd: HxPath.directory(Sys.programPath())}); // todo fix for windows
	}

	function h_attach(req:GmDebugAttachRequest) {
		final serverFolder = req.arguments.serverFolder;
		final serverFolderResult = validateServerFolder(serverFolder);
		if (serverFolderResult != None) {
			serverFolderResult.sendError(req,luaDebug);
			return;
		}
		final clientFolders = req.arguments.clientFolders.or([]);
		for (ind => client in clientFolders) {
			final clientFolderResult = validateClientFolder(client);
			if (clientFolderResult != None) {
				clientFolderResult.sendError(req,luaDebug);
				return;
			}
			clientFolders[ind] = HxPath.addTrailingSlash(client);
		}
		final serverSlash = HxPath.addTrailingSlash(req.arguments.serverFolder);
		luaDebug.serverFolder = serverSlash;
		luaDebug.setClientLocations(clientFolders);
		luaDebug.startServer(req);
	}


	function validateProgramPath(programPath:String):haxe.ds.Option<DapFailure> {
		return if (programPath == null) {
			Some({
				id : 2,
				message : "Gmdebug requires the property \"programPath\" to be specified when launching"
			});
		} else {
			if (!Fs.existsSync(programPath)) {
				Some({
					id : 4,
					message : "The program specified by \"programPath\" does not exist!"
				});
			} else if (!Fs.statSync(programPath).isFile()) {
				Some({
					id : 5,
					message : "The program specified by \"programPath\" is not a file."
				});
			} else {
				None;
			}
		}

	}

	function validateServerFolder(serverFolder:String):haxe.ds.Option<DapFailure> {
		return if (serverFolder == null) {
			Some({
				id : 2,
				message : "Gmdebug requires the property \"serverFolder\" to be specified."
			});
		} else {
			final addonFolder = js.node.Path.join(serverFolder, "addons");
			if (!HxPath.isAbsolute(serverFolder)) {
				Some({
					id : 3,
					message : "Gmdebug requires the property \"serverFolder\" to be an absolute path (i.e from root folder)."
				});
			} else if (!Fs.existsSync(serverFolder)) {
				Some({
					id : 4,
					message : "The \"serverFolder\" path does not exist!"
				});
			} else if (!Fs.statSync(serverFolder).isDirectory()) {
				Some({
					id : 5,
					message : "The \"serverFolder\" path is not a directory."
				});
			} else if (!Fs.existsSync(addonFolder) || !Fs.statSync(addonFolder).isDirectory()) {
				Some({
					id : 6,
					message : "\"serverFolder\" does not seem to be a garrysmod directory. (looking for \"addons\" folder)"
				});
			} else {
				None;
			}
		}
	}

	function validateClientFolder(folder:String):haxe.ds.Option<DapFailure> {
		final addonFolder = js.node.Path.join(folder, "addons");
		final gmdebug = js.node.Path.join(folder, "data", "gmdebug");
		return if (!HxPath.isAbsolute(folder)) {
			Some({
				id : 8,
				message : 'Gmdebug requires client folder: $folder to be an absolute path (i.e from root folder).'
			});
		} else if (!Fs.existsSync(folder)) {
			Some({
				id : 9,
				message : 'The client folder: $folder does not exist!'
			});
		} else if (!Fs.statSync(folder).isDirectory()) {
			Some({
				id : 10,
				message : 'The client folder: $folder is not a directory.'
			});
		} else if (!Fs.existsSync(addonFolder) || !Fs.statSync(addonFolder).isDirectory()) {
			Some({
				id : 11,
				message : 'The client folder: $folder does not seem to be a garrysmod directory. (looking for \"addons\" folder)'
			});
		} else {
			None;
		}
	}
}

private typedef HasThreadID = {
	arguments:{
		threadId:Int
	}
}





