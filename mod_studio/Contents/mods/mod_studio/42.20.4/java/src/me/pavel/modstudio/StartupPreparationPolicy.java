package me.pavel.modstudio;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.Core;
import java.util.concurrent.atomic.AtomicLongArray;

/** Verified preparation defaults end at the first main-menu entry. */
public final class StartupPreparationPolicy {
    private static volatile boolean active=true;
    // Package-private injection for isolated bytecode tests; never exposed to Lua.
    static volatile Boolean compatible;
    private static final AtomicLongArray counts=new AtomicLongArray(10);
    public static final int LUA_HIT=0,LUA_FALLBACK=1,FOLDERS=2,BLOCKS=3,VALUES=4,TOKENS=5,ITEMS=6,ANIMATIONS=7,TRANSLATIONS=8,SAVE_LISTS=9;
    public static void record(int counter){counts.incrementAndGet(counter);}
    public static boolean enabled(String feature) {
        if(!active || !Boolean.parseBoolean(System.getProperty("modstudio.startup.enabled","true")))return false;
        boolean defaultEnabled=switch(feature){
            case "lua","definitions","itemDispatch","animations" -> true;
            default -> false;
        };
        if(!Boolean.parseBoolean(System.getProperty("modstudio.startup."+feature,Boolean.toString(defaultEnabled))))return false;
        if(compatible==null)compatible=Core.getInstance().getVersion().startsWith("42.21.0 ");
        return compatible;
    }
    public static synchronized void finish(){
        if(!active)return;active=false;
        long total=0;for(int i=0;i<counts.length();i++)total+=counts.get(i);
        if(total>0)System.out.println("[ModStudioStartup] startup hooks disabled; luaPrepared="+counts.get(LUA_HIT)+" luaFallback="+counts.get(LUA_FALLBACK)+" folders="+counts.get(FOLDERS)+" blocks="+counts.get(BLOCKS)+" values="+counts.get(VALUES)+" tokenLists="+counts.get(TOKENS)+" itemParameters="+counts.get(ITEMS)+" animationClips="+counts.get(ANIMATIONS)+" translationStrings="+counts.get(TRANSLATIONS)+" saveListings="+counts.get(SAVE_LISTS));
    }
    @Patch(className="zombie.gameStates.MainScreenState",methodName="enter",warmUp=true,strictMatch=true)
    public static final class FinishPatch {
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(){StartupPreparationPolicy.finish();}
    }
}
