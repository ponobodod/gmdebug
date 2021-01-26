package gmdebug.lua;

abstract GmodPath(String) to String {

    public static inline extern function gPath(x:String):GmodPath {
        return cast x;
    }
}