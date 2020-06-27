package gmdebug.lua;

import gmod.Gmod;
import gmod.libs.MathLib;
using Safety;

class DebugLoopProfile {

    static final inital:Array<Map<String,Float>> = [];
    static final vinal:Array<Map<String,Float>> = [];

    static var pass = 0;
    static var lastname = "";

    static var profileState:ProfilingState = NOT_PROFILING;

    static var cumulativeTime = 0.0;
    static var totalProfileTime = 0.0;

    public static function beginProfiling() {
        pass = 0;
        totalProfileTime = Gmod.SysTime();
        cumulativeTime = 0.0;
        profileState = PROFILING;
    }

    public static function report() {
        if (profileState != PROFILE_FINISHED) return;
        final avg:Map<String,Float> = [];
        trace("report");
        for (pass in vinal) {
            for (str => time in pass) {
                avg.set(str,avg.get(str).or(0.0) + time);
            }
        }
        for (str => time in avg) {
            trace('average $str : $time');
        }
        trace('Cumulative time $cumulativeTime / Total time $totalProfileTime');
        final percent = MathLib.Round(cumulativeTime / totalProfileTime * 100,3);
        trace('Overall runtime impact $percent');
        profileState = NOT_PROFILING;
    }

    public #if !profile inline #end static function profile(zone:String,first=false) {
        #if profile
        if (profileState != PROFILING) return;
        if (!first) profileend(); //ambigous

        if (inital[pass] == null) {
            inital[pass] = [];
            vinal[pass] = [];
        }
        inital[pass].unsafe().set(zone,Gmod.SysTime());
        lastname = zone;

        #end
    }


    public #if !profile inline #end static function profileend() {
        #if profile
        if (profileState != PROFILING) return;
        final diff = Gmod.SysTime() - inital[pass].get(lastname).unsafe();
        vinal[pass].set(lastname, diff);
        cumulativeTime += diff;

        #end
    }

    public #if !profile inline #end static function resetprofile() {
        #if profile
        if (profileState != PROFILING) return;
        profileend();
        if (pass > 25000) {
            totalProfileTime = Gmod.SysTime() - totalProfileTime;
            profileState = PROFILE_FINISHED;
        }
        pass++;
        #end
    }

}

enum ProfilingState {
    NOT_PROFILING;
    PROFILING;
    PROFILE_FINISHED;
}
