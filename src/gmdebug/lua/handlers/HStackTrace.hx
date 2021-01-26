package gmdebug.lua.handlers;

import gmod.libs.DebugLib;
import gmdebug.composer.ComposedEvent;

class HStackTrace implements IHandler<StackTraceRequest> {
	public function new() {}

	public function handle(x:StackTraceRequest):HandlerResponse {
		final args = x.arguments.unsafe();
		if (!Debugee.inpauseloop) {
			var response = x.compose(stackTrace, {
				stackFrames: [],
				totalFrames: 0
			});
			final js = tink.Json.stringify((cast response : StackTraceResponse)); // in pratical terms they're the same
			response.sendtink(js);
			new ComposedEvent(continued, {
				threadId: Debugee.clientID,
				allThreadsContinued: false
			}).send();
			return WAIT;
		}
		final firstFrame = switch (args.startFrame) {
			case null:
				Debugee.baseDepth.sure();
			case x:
				x + Debugee.baseDepth.sure();
		}
		final lastFrame = switch (args.levels) {
			case null | 0:
				9999;
			case x:
				firstFrame + (x - 1);
		}
		final stackFrames:Array<StackFrame> = [];
		for (i in firstFrame...lastFrame) {
			var info = DebugLib.getinfo((i + 1), "lnSfu");
			if (info == null)
				break;
			var src = switch (info.source.charAt(0)) {
				case "@":
					@:nullSafety(Off) info.source.substr(1);
				default:
					info.source;
			}
			var args:String = "";
			if (info.nparams > 0) {
				args = "(";
				for (p in 0...info.nparams) {
					final lcl = DebugLib.getlocal(i + 1, p + 1);
					final val = switch (Lua.type(lcl.b)) {
						case "table":
							"table";
						case "string":
							'"${lcl.b}"';
						default:
							Gmod.tostring(lcl.b);
					}
					args += '${lcl.a}=$val,'; // ${Lua.type(lcl.b)}
				}
				// vargs
				for (p in 1...9999) {
					final lcl = DebugLib.getlocal(i + 1, -p);
					if (lcl.a == null)
						break;
					final val = switch (Lua.type(lcl.b)) {
						case "table":
							"table";
						case "string":
							'"${lcl.b}"';
						default:
							Gmod.tostring(lcl.b);
					}
					args += '${lcl.a}=$val,';
				}
				args = args.substr(0, args.length - 1) + ")";
			}
			var name = switch [info.name, info.namewhat] {
				case [null, NOT_FOUND]:
					'anonymous function $args';
				// case [null,what]:
				//     'anonymous function ';
				case [name, what]:
					'[$what] $name $args';
			}
			var path:Null<String>;
			var hint:Null<SourcePresentationHint>;
			var line;
			var column;
			var endLine:Null<Int> = null;
			var endColumn:Null<Int> = null;
			switch (src) {
				case "=[C]":
					hint = Deemphasize;
					path = null;
					line = 0;
					column = 0;
				case x:
					path = Debugee.normalPath(x);
					hint = null;
					line = info.currentline;
					column = 1;
					endLine = info.lastlinedefined;
					endColumn = 99999;
			}
			hint = Normal;
			if (info.func != null && Exceptions.isExcepted(info.func)) {
				line = 0;
				path = null;
				column = 0;
				hint = Deemphasize;
				name = "Exception catcher";
			} else {
				hint = Normal;
			}
			var target:StackFrame = {
				id: gmdebug.FrameID.encode(Debugee.clientID.sure(), i),
				name: name,
				source: switch path {
					case null:
						null;
					case path:
						var pth = @:nullSafety(Off) path.split("/");
						{
							name: pth[pth.length - 1],
							path: path,
							presentationHint: hint
						};
				},
				line: line,
				column: column,
				endLine: endLine,
				endColumn: endColumn,
				// presentationHint:
			}
			if (path != null) {
				target.source.unsafe().path = path;
			}
			stackFrames.push(target);
		}
		var response = x.compose(stackTrace, {
			stackFrames: stackFrames,
			totalFrames: stackFrames.length
		});
		final js = tink.Json.stringify((cast response : StackTraceResponse)); // in pratical terms they're the same
		response.sendtink(js);
		return WAIT;
	}
}
