package gmdebug.lua.managers;

import haxe.Constraints.Function;

class StepManager {

    public function new() {

    }

    public var stepState:StepState = WAIT;

}

enum StepState {
    WAIT;
    STEP(targetHeight:Null<Int>);
    OUT(outFunc:Function, lowestLine:Int);
}