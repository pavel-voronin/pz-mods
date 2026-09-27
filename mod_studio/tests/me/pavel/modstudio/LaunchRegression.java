package me.pavel.modstudio;

import java.nio.file.*;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.*;
import se.krka.kahlua.luaj.compiler.LuaCompiler;

/** Standalone Studio API, menu and loadouts in the installed game Lua VM. */
public final class LaunchRegression {
    static void run(KahluaThread thread, KahluaTable env, String source, String name) throws Exception {
        var result=thread.pcall(LuaCompiler.loadstring(source,name,env),new Object[0]);
        if(!Boolean.TRUE.equals(result[0])) throw new AssertionError(name+": "+java.util.Arrays.toString(result));
    }
    static String function(Path source, String name) throws Exception {
        String code=Files.readString(source);
        int start=code.indexOf("function "+name+"(");
        if(start<0) throw new AssertionError("Missing native function: "+name);
        int end=code.indexOf("\nfunction ",start+1);
        return code.substring(start,end<0?code.length():end);
    }
    public static void main(String[] args) throws Exception {
        Path root=Path.of(args[0]), game=Path.of(args[1]);
        Path lua=root.resolve("Contents/mods/mod_studio/common/media/lua/client/ModStudio");
        Path screens=game.resolve("media/lua/client/OptionScreens");
        // Verify the Lua API against the installed game rather than inventing a
        // Java-class global in the fixture (the original in-game launch failure).
        var factory=zombie.Lua.LuaManager.GlobalObject.class.getMethod("instanceItem",String.class);
        var binding=factory.getAnnotation(se.krka.kahlua.integration.annotations.LuaMethod.class);
        if(binding==null || !binding.global() || !"instanceItem".equals(binding.name()))
            throw new AssertionError("Native global instanceItem binding is unavailable");
        var platform=J2SEPlatform.getInstance();
        for(boolean debug:new boolean[]{false,true}) {
            var env=platform.newEnvironment();
            var thread=new KahluaThread(platform,env); thread.debugOwnerThread=Thread.currentThread();
            run(thread,env,"DEBUG="+debug+"\n"+Files.readString(root.resolve("tests/fixtures/launch-setup.lua")),"setup");
            run(thread,env,function(screens.resolve("CharacterCreationMain.lua"),"CharacterCreationMain:onOptionMouseDown"),"native-launch");
            run(thread,env,function(screens.resolve("CharacterCreationProfession.lua"),"CharacterCreationProfession.initWorld"),"native-spawn");
            run(thread,env,Files.readString(lua.resolve("LaunchAPI.lua")),"api");
            run(thread,env,Files.readString(lua.resolve("Settings.lua")),"settings");
            run(thread,env,Files.readString(lua.resolve("Launch.lua")),"launch");
            run(thread,env,"local s=makeScreen(); s:prerender(); assert(#s.modStudioLaunchLabels==1, 'Studio alone has a save toggle and no discovered presets')","no-presets");
            run(thread,env,"ModStudio.Launch.register('fixture','one',{name='Rising+Vehicles',sandboxPreset='New Rising',spawnRegion='Rosewood, KY',inventory={{type='Base.Ammo',count=2,fullAmmo=true},{type='Base.Watch',worn=true}}})","registration");
            run(thread,env,Files.readString(lua.resolve("Launch.lua")),"launch");
            run(thread,env,Files.readString(root.resolve("tests/fixtures/launch-checks.lua")),"checks");
            run(thread,env,Files.readString(lua.resolve("Settings.lua")),"reload-settings");
            run(thread,env,"assert(ModStudio.Settings.noSave==false, 'saved setting survives Lua reset')","persistence");
        }
        // Exercise the native file API in a test-only cache, including directory creation.
        Path cache=root.resolve(".build/launch-native-settings");
        Files.createDirectories(cache);
        zombie.ZomboidFileSystem.instance.setCacheDir(cache.toString());
        var writer=zombie.Lua.LuaManager.GlobalObject.getFileWriter("ModStudio/settings.ini",true,false);
        if(writer==null) throw new AssertionError("Native settings writer unavailable");
        writer.write("noSave=false\n"); writer.close();
        try(var reader=zombie.Lua.LuaManager.GlobalObject.getFileReader("ModStudio/settings.ini",false)) {
            if(reader==null || !"noSave=false".equals(reader.readLine())) throw new AssertionError("Native settings readback");
        }
        System.out.println("PASS: with/without debug, API registration, persistent settings, native launch/spawn, loadouts, watch, error recovery and save isolation.");
    }
}
