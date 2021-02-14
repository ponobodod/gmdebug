package gmdebug.lua.managers;

import haxe.Constraints.Function;

class StepManager {

    public function new() {

    }

    public var stepState(default,null):StepState = WAIT;

    public var baseDepth(default,null):Null<Int> = null;

}

enum StepState {
    WAIT;
    STEP(targetHeight:Null<Int>);
    OUT(outFunc:Function, lowestLine:Int);
}