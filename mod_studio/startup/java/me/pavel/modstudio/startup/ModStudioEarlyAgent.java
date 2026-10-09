package me.pavel.modstudio.startup;

import java.io.File;
import java.lang.instrument.Instrumentation;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import net.bytebuddy.agent.builder.AgentBuilder;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.asm.MemberSubstitution;
import static net.bytebuddy.matcher.ElementMatchers.*;

/** Mod Studio's early game preparation. Never transforms a third-party loader. */
public final class ModStudioEarlyAgent {
    public static void premain(String arguments,Instrumentation instrumentation) {
        try{install(instrumentation);}catch(Exception unavailable){
            StartupScanner.enabled=false;StartupWatch.enabled=false;StartupTrace.finish();
            System.err.println("[ModStudioStartup] early preparation unavailable; native startup retained: "+unavailable);
        }
    }
    private static void install(Instrumentation instrumentation)throws Exception {
        if(!Boolean.parseBoolean(System.getProperty("modstudio.startup.early","true")))return;
        StartupTrace.open(System.getProperty("modstudio.startup.output",""));
        String expected=ModStudioEarlyAgent.class.getPackage().getImplementationVersion();
        String actual;
        try(var input=Files.newInputStream(Path.of("projectzomboid.jar"))){
            var digest=MessageDigest.getInstance("SHA-256");byte[] buffer=new byte[1024*1024];int read;
            while((read=input.read(buffer))>=0)digest.update(buffer,0,read);
            actual=HexFormat.of().formatHex(digest.digest());
        }
        if(!actual.equals(expected)){StartupTrace.note("version-fallback","Unrecognized game build");StartupTrace.finish();return;}
        // Define the native exposer outside a filesystem transform. Otherwise a
        // loader's first recursive class load can bypass its own exposure advice.
        // No initialization, API substitution or third-party patch is performed.
        Class.forName("zombie.Lua.LuaManager$Exposer",false,ClassLoader.getSystemClassLoader());
        StartupScanner.enabled=true;StartupWatch.enabled=true;StartupWatch.deferUntilStartupComplete=true;
        var builder=new AgentBuilder.Default().disableClassFormatChanges()
            .with(AgentBuilder.RedefinitionStrategy.RETRANSFORMATION)
            .with(new AgentBuilder.Listener.Adapter(){
                @Override public void onError(String name,ClassLoader loader,net.bytebuddy.utility.JavaModule module,boolean loaded,Throwable error){
                    StartupTrace.note("transform-error",name+": "+error);
                    System.err.println("[ModStudioStartup] early transformation failed: "+name+": "+error);
                }
            });
        var directoryCheck=StartupScanner.class.getMethod("isDirectory",File.class);
        builder=builder.type(named("zombie.ZomboidFileSystem"))
            .transform((b,t,l,m,p)->b
                .visit(MemberSubstitution.relaxed().method(isDeclaredBy(File.class).and(named("isDirectory"))).replaceWith(directoryCheck).on(named("init")))
                .visit(Advice.to(EarlyGameAdvice.ScanAdvice.class).on(named("searchFolders").and(takesArguments(File.class))))
                .visit(Advice.to(EarlyGameAdvice.IndexAdvice.class).on(namedOneOf("init","loadMod")))
                .visit(Advice.to(EarlyGameAdvice.RelativeAdvice.class).on(named("getRelativeFile").and(takesArguments(java.net.URI.class,String.class))))
                .visit(Advice.to(EarlyGameAdvice.WatchBatchAdvice.class).on(named("getAllModFolders").and(takesArguments(List.class)))));
        builder=builder.type(named("zombie.DebugFileWatcher"))
            .transform((b,t,l,m,p)->b
                .visit(Advice.to(EarlyGameAdvice.WatchUpdateAdvice.class).on(named("update")))
                .visit(Advice.to(EarlyGameAdvice.WatchAdvice.class).on(named("registerDirRecursive"))));
        builder=builder.type(named("zombie.scripting.ScriptParser"))
            .transform((b,t,l,m,p)->b
                .visit(Advice.to(EarlyGameAdvice.TokenAdvice.class).on(named("parseTokens")))
                .visit(Advice.to(EarlyGameAdvice.CommentAdvice.class).on(named("stripComments"))));
        builder=builder.type(named("zombie.GameWindow"))
            .transform((b,t,l,m,p)->b.visit(Advice.to(GameReadyAdvice.class).on(named("init"))));
        builder=builder.type(named("zombie.gameStates.MainScreenState"))
            .transform((b,t,l,m,p)->b.visit(Advice.to(MenuReadyAdvice.class).on(named("enter"))));
        builder.installOn(instrumentation);
        System.out.println("[ModStudioStartup] early game preparation enabled; third-party loaders unchanged");
    }
    public static final class GameReadyAdvice {
        @Advice.OnMethodExit(onThrowable=Throwable.class) public static void exit(){StartupWatch.endStartup();}
    }
    public static final class MenuReadyAdvice {
        @Advice.OnMethodExit(onThrowable=Throwable.class) public static void exit(){
            StartupWatch.endStartup();StartupWatch.enabled=false;StartupScanner.enabled=false;StartupTrace.finish();
        }
    }
}
