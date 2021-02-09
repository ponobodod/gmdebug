package gmdebug.lua;

class StackConst {

    public static final MIN_HEIGHT = 3;

    public static final MIN_HEIGHT_OUT = 4;

#if !gmddebug
    public static final STEP = 3;

    public static final STEP_DEBUG_LOOP = 4;

    public static final EXCEPT = 4;

    public static final PAUSE = 4;
#else
    public static final STEP = 3;

    public static final STEP_DEBUG_LOOP = 5;

    public static final EXCEPT = 5;

    public static final PAUSE = 5;
#end

}