package gmdebug.lua;

import gmod.Gmod;
import gmod.Hook.GMHook;
import gmod.libs.HookLib;
import gmdebug.lua.DebugLoop.SourceInfo;
import gmdebug.composer.*;
using Safety; 
using Lambda;
class SourceContainer implements IHandler<SourceRequest> {

    static final uniqueSources:Map<String,Null<Source>> = [];

    public static var sources:Array<Source> = [];

    public var sourceCache = makeSourceCache(); 

    public function handle() {

    }

    function makeSourceCache() {
	final sc = new haxe.ds.ObjectMap<Function,SourceInfo>();
	sc.setWeakKeysM();
	return sc;
    }
    
    static function readSourceInfo() {
	if (Debugee.dest == "") return; 
	for (si in DebugLoop.sourceCache) {
	    if (!uniqueSources.exists(si.source)) {
		final result = infoToSource(si);
		if (result != null) {
		    new ComposedEvent(loadedSource,{
			reason : New,
			source : result
		    }).send();
		    sources.push(result);
		}
		uniqueSources.set(si.source,result);
	    }
	}
    }

    static var readSourceTime:Float = 0;

    public static function init() {
	HookLib.Add(GMHook.Think,"source-get",() -> {
	    if (Gmod.CurTime() > readSourceTime) {
		readSourceTime = Gmod.CurTime() + 1;
		readSourceInfo();
	    }
	});
    }

    static function infoToSource(info:SourceInfo):Null<Source> {
	return switch (info.source) {
	    case "=[C]":
		null;
	    case x:
		final pathStr = Debugee.normalPath(x);
		final path = new haxe.io.Path(pathStr);
		{
		    name: path.file,
		    path: path.toString(),
		};
	}
    }
}