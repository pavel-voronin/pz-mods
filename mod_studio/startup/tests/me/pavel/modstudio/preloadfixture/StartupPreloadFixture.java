package me.pavel.modstudio.preloadfixture;
import java.lang.instrument.Instrumentation;

/** Simulates classes defined by an earlier agent, without running game startup. */
public final class StartupPreloadFixture {
    public static void premain(String arguments,Instrumentation instrumentation)throws Exception{
        for(String name:new String[]{"me.zed_0xff.zombie_buddy.Loader","me.zed_0xff.zombie_buddy.PatchEngine","zombie.ZomboidFileSystem","zombie.DebugFileWatcher","zombie.GameWindow","zombie.gameStates.MainScreenState","zombie.scripting.ScriptParser"}){
            Class.forName(name,false,ClassLoader.getSystemClassLoader());
        }
    }
}
