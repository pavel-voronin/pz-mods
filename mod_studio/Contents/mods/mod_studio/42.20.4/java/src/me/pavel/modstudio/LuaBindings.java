package me.pavel.modstudio;

import me.zed_0xff.zombie_buddy.Exposer;
import se.krka.kahlua.vm.KahluaTable;
import zombie.HiddenFromLua;
import zombie.Lua.LuaManager;

/** Repairs our userdata bindings after ZombieBuddy's order-dependent recursive exposure. */
@HiddenFromLua
final class LuaBindings {
    private static final Class<?>[] TYPES={ReadRequest.class,UploadRequest.class,PublicationRequest.class,
        FileScan.class,PackageEntry.class,PreviewInfo.class,PreviewAnimation.class,PreviewDownload.class};
    private static LuaManager.Exposer boundExposer;
    private static KahluaTable boundEnvironment;

    static boolean ensure() {
        var exposer=LuaManager.exposer;var env=LuaManager.env;
        if(exposer==null || env==null)return true; // Offline Java calls have no Lua environment.
        if(exposer==boundExposer && env==boundEnvironment)return true;
        // Recursive exposure remembers even types it skipped before they were allowed.
        // Register all our types first, then use direct exposure, which bypasses that visited set.
        for(Class<?> type:TYPES)exposer.setExposed(type);
        var scope=LuaManager.platform.newTable();
        for(Class<?> type:TYPES){
            exposer.exposeLikeJava(type,scope);
            if(!exposer.isExposed(type))return false;
            Object table=scope.rawget(type.getSimpleName());
            String alias=type.getAnnotation(Exposer.LuaClass.class).name();
            if(table!=null && env.rawget(alias)==null)env.rawset(alias,table);
        }
        boundExposer=exposer;boundEnvironment=env;
        return true;
    }
}
