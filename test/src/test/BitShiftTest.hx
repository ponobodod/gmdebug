package test;

import gmdebug.FrameID;
import utest.Assert;
import gmdebug.VariableReference;

class BitShiftTest extends utest.Test {


    function testChild() {
        var child = VariableReference.encode(Child(10,123922));
        Assert.same(child.getValue(),Child(10,123922));
    }

    function testframeLocal() {
        var framelocal = VariableReference.encode(FrameLocal(10,50,110213));
        Assert.same(framelocal.getValue(),FrameLocal(10,50,110213));
    }

    function testframeID() {
        var fid = FrameID.encode(0,100000000);
        final frame = (fid : FrameID).getValue();
        Assert.same(frame,{clientID : 0, actualFrame : 100000000});
    }

    function testglobal() {
        var global = VariableReference.encode(Global(10,100000));
        Assert.same(global.getValue(),Global(10,100000));
    }

    public function new() {
        super();
    }
}
