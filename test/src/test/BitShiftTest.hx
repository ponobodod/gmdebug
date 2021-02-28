package test;

import gmdebug.FrameID;
import utest.Assert;
import gmdebug.VariableReference;

class BitShiftTest extends utest.Test {


    function testChild() {
        var child = VariableReference.encode(Child(10,123922));
        Assert.same(Child(10,123922),child.getValue());
    }

    function testframeLocal() {
        var framelocal = VariableReference.encode(FrameLocal(10,110213,200));
        Assert.same(FrameLocal(10,110213,200),framelocal.getValue());
    }

    function testframeID() {
        var fid = FrameID.encode(12,100000000);
        final frame = (fid : FrameID).getValue();
        Assert.same({clientID : 12, actualFrame : 100000000},frame);
    }

    function testglobal() {
        var global = VariableReference.encode(Global(10,100000));
        Assert.same(Global(10,100000),global.getValue());
    }

    public function new() {
        super();
    }
}
