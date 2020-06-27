package gmdebug;

import gmdebug.VariableReference;
class BitShiftTest {

    public static function main() {


        var child1 = VariableReference.encode(Child(10,123922));
        var framelocal = VariableReference.encode(FrameLocal(10,50,110213));
        framelocal = VariableReference.encode(FrameLocal(10,50,1));
        framelocal = VariableReference.encode(FrameLocal(10,50,1));
        framelocal = VariableReference.encode(FrameLocal(10,50,11000000));
        framelocal = VariableReference.encode(FrameLocal(10,50,1));
        framelocal = VariableReference.encode(FrameLocal(10,50,11000000));
        framelocal = VariableReference.encode(FrameLocal(0,127,100000));
        var global = VariableReference.encode(Global(10,100000));
       
        var fid = FrameID.encode(0,100000000);
        final frame = (fid : FrameID).getValue();
        final cid = frame.clientID;
        final actual = frame.actualFrame;
        trace('frame $cid $actual');
        trace('$child1 ${child1.getValue()} ${framelocal.getValue()} $framelocal $global ${global.getValue()}');

    }
}
