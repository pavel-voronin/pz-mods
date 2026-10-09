package me.pavel.modstudio;
import java.nio.file.*;
import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;

/** Native Lua initialization only; never enters GameWindow, a menu or a world. */
public final class NativeLoaderExposureProbe {
    public static void main(String[] arguments)throws Exception {
        ZomboidFileSystem.instance.base.set(Path.of(arguments[0]).toFile());
        ZomboidFileSystem.instance.setCacheDir(arguments[1]);
        zombie.core.random.RandStandard.INSTANCE.init();
        if(arguments.length>2){
            Path root=Path.of(arguments[1],"mods","pz3d"),version=root.resolve("42.20.4"),bundle=version.resolve("media/java/client/core.jar");
            Files.createDirectories(bundle.getParent());Files.createDirectories(root.resolve("common/media/lua/client"));
            Files.writeString(version.resolve("mod.info"),"id=pz3d\nname=pz3d\nmodversion=0.7.0-beta1\nversionMin=42.21.0\nversionMax=42.21.0\njavaJarFile=media/java/client/core.jar\njavaPkgName=com.pavelvoronin.pz3dLoader.bootstrap\n");
            Files.copy(Path.of(arguments[2]),bundle);Files.copy(Path.of(arguments[2]+".zbs"),Path.of(bundle+".zbs"));
            ZomboidFileSystem.instance.setModFoldersOrder("mods");
            ZomboidFileSystem.instance.loadMods(new java.util.ArrayList<>(java.util.List.of("pz3d")));
            System.out.println("[ExposureProbe] signed core loaded before native Lua init");
        }
        LuaManager.init();
        System.out.println("[ExposureProbe] after native Lua init: loaderFlag="+LuaManager.env.rawget("pz3dLoaderAgent")+" api="+(LuaManager.env.rawget("PZ3D")!=null));
        if(arguments.length>3 && (!Boolean.TRUE.equals(LuaManager.env.rawget("pz3dLoaderAgent")) || LuaManager.env.rawget("PZ3D")==null))throw new AssertionError("Early preparation did not preserve the native loader's Lua API");
        Class<?> agent=Class.forName("com.pavelvoronin.pz3dLoader.Agent");
        var instrumentation=(java.lang.instrument.Instrumentation)agent.getField("g_instrumentation").get(null);
        instrumentation.retransformClasses(LuaManager.Exposer.class);
        LuaManager.init();
        System.out.println("[ExposureProbe] after native exposer retransformation and Lua reset: loaderFlag="+LuaManager.env.rawget("pz3dLoaderAgent")+" api="+(LuaManager.env.rawget("PZ3D")!=null));
        agent.getMethod("expose").invoke(null);
        System.out.println("[ExposureProbe] after explicit expose: loaderFlag="+LuaManager.env.rawget("pz3dLoaderAgent")+" api="+(LuaManager.env.rawget("PZ3D")!=null));
    }
}
