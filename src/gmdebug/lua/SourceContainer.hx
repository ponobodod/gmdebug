package gmdebug.lua;

import haxe.Constraints.Function;
import haxe.ds.ObjectMap;
import gmdebug.lua.handlers.IHandler;
import gmod.Gmod;
import gmod.stringtypes.Hook.GMHook;
import gmod.libs.HookLib;
import haxe.io.Path as HxPath;
import gmdebug.lua.DebugLoop.SourceInfo;
import gmdebug.composer.*;
using gmod.helpers.WeakTools;
using Safety;
using Lambda;

class SourceContainer {
	
	final uniqueSources:Map<String, Null<Source>> = [];

	public var sources:Array<Source> = [];

	public var sourceCache:ObjectMap<Function,SourceInfo>;

	public function new() {
		HookLib.Add(GMHook.Think, "gmdebug-source-get", () -> {
			if (Gmod.CurTime() > readSourceTime) {
				readSourceTime = Gmod.CurTime() + 1;
				readSourceInfo();
			}
		});
		sourceCache = makeSourceCache();
	}

	function makeSourceCache() {
		final sc = new haxe.ds.ObjectMap<haxe.Constraints.Function, SourceInfo>();
		sc.setWeakKeysM();
		return sc;
	}

	function readSourceInfo() {
		if (Debugee.dest == "")
			return;
		for (si in sourceCache) {
			if (!uniqueSources.exists(si.source)) {
				final result = infoToSource(si);
				if (result != null) {
					new ComposedEvent(loadedSource, {
						reason: New,
						source: result
					}).send();
					sources.push(result);
				}
				uniqueSources.set(si.source, result);
			}
		}
	}

	static var readSourceTime:Float = 0;

	static function infoToSource(info:SourceInfo):Null<Source> {
		return switch (info.source) {
			case "=[C]":
				null;
			case x:
				final pathStr = Debugee.normalPath(x);
				final path = new HxPath(pathStr);
				{
					name: path.file,
					path: path.toString(),
				};
		}
	}
}
