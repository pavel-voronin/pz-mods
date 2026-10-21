package me.pavel.modstudio;

import java.nio.file.Path;
import java.util.*;
import me.zed_0xff.zombie_buddy.Exposer;
import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.*;
import zombie.Lua.LuaManager;
import zombie.Lua.KahluaNumberConverter;
import zombie.core.znet.SteamWorkshopItem;

/** Real userdata and real ZombieBuddy/Kahlua exposure, including the order from the crash log. */
final class LuaExposureTest {
    static final Class<?>[] TYPES={Bridge.class,ReadRequest.class,UploadRequest.class,PublicationRequest.class,
        FileScan.class,PackageEntry.class,PreviewInfo.class,PreviewAnimation.class,PreviewDownload.class};
    static void run(Path folder) throws Exception {
        var originalEnv=LuaManager.env;var originalExposer=LuaManager.exposer;
        var platform=J2SEPlatform.getInstance();var manager=new KahluaConverterManager();
        KahluaNumberConverter.install(manager);
        try {
            LuaManager.env=null;LuaManager.exposer=null;
            for(Class<?> type:TYPES)Exposer.exposeClass(type);
            var env=platform.newEnvironment();LuaManager.env=env;
            LuaManager.exposer=new LuaManager.Exposer(manager,platform,env);
            // Bridge signatures encounter return types before those types have been registered.
            var expose=Exposer.class.getDeclaredMethod("exposeClassNow",Class.class);expose.setAccessible(true);
            for(Class<?> type:TYPES)expose.invoke(null,type);
            var thread=new KahluaThread(platform,env);thread.debugOwnerThread=Thread.currentThread();
            env.rawset("scan",new FileScan());
            var failure=thread.pcall(LuaCompiler.loadstring("return scan:getState()","exposure reproduction",env),new Object[0]);
            OfflineTest.check(!Boolean.TRUE.equals(failure[0]) && Arrays.toString(failure).contains("getState"),"reproduce getState userdata failure before binding repair");
            System.out.println("PASS: reproduced the logged FileScan.getState failure with real ZombieBuddy exposure.");
            // The failed VM caches the missing metatable. A fresh game VM must bind before its first lookup.
            thread=new KahluaThread(platform,env);thread.debugOwnerThread=Thread.currentThread();
            var script=LuaCompiler.loadstring("assert(ModStudioJava.isReady()); assert(scan:getState() == 'loading'); return true","repaired exposure",env);
            var result=thread.pcall(script,new Object[0]);
            OfflineTest.check(Boolean.TRUE.equals(result[0]),"real userdata after readiness check: "+Arrays.toString(result));
            for(int seed=0;seed<12;seed++){
                env=platform.newEnvironment();LuaManager.env=env;LuaManager.exposer=new LuaManager.Exposer(manager,platform,env);
                for(Class<?> type:List.of(ArrayList.class,List.class))LuaManager.exposer.setExposed(type);
                for(Class<?> type:List.of(ArrayList.class,List.class))LuaManager.exposer.exposeLikeJava(type,env);
                var order=new ArrayList<Class<?>>(List.of(TYPES));Collections.shuffle(order,new Random(seed));
                if(seed==11)Exposer.afterExposeAll();else for(Class<?> type:order)expose.invoke(null,type);
                thread=new KahluaThread(platform,env);thread.debugOwnerThread=Thread.currentThread();
                env.rawset("scan",new FileScan());
                var info=new PreviewInfo("png",512,512,1,1234);
                var download=new PreviewDownload("123");download.info=info;download.state="loaded";
                env.rawset("download",download);env.rawset("info",info);
                env.rawset("animation",new PreviewAnimation());
                env.rawset("asset",new PackageEntry("preview.png","preview.png",false,true,1234,null));
                env.rawset("read",new ReadRequest(null,"123","english",0));
                env.rawset("upload",new UploadRequest(null,"123",List.of(),"",false));
                var item=new SteamWorkshopItem(folder.toString());
                env.rawset("publication",new PublicationRequest(null,item,"Title","Description","preview.png","Build 42",2,"",""));
                env.rawset("item",item);
                script=LuaCompiler.loadstring("""
                    local bridge=ModStudioJava
                    assert(bridge.isReady()); assert(bridge.isReady()); assert(bridge==ModStudioJava)
                    assert(scan:getState() == 'loading'); assert(scan:getFileCount() == 0); assert(scan:getEntries():size() == 0)
                    assert(scan:getPhase() == 'checking'); assert(scan:getUnchanged() == 0)
                    assert(scan:getManifestId() == nil); assert(scan:getComparisonError() == nil)
                    assert(read:getState() == 'loading'); assert(read:getDependencies():size() == 0)
                    assert(asset:getName() == 'preview.png'); assert(asset:isSelectable()); assert(asset:getSize() == 1234)
                    assert(info:getWidth() == 512); assert(info:canUpload())
                    assert(download:getInfo():getFormat() == 'PNG'); assert(download:getState() == 'loaded')
                    assert(animation:getState() == 'loading'); assert(animation:getFrameCount() == 0)
                    assert(upload:getState() == 'prepared'); assert(upload:getProgress() == 0)
                    assert(publication:getState() == 'prepared'); assert(not publication:canRetry())
                    local actual=bridge.scanFiles(item)
                    assert(actual:getState() == 'loading' or actual:getState() == 'ready'); actual:cancel()
                    return true
                    ""","all real editor userdata",env);
                result=thread.pcall(script,new Object[0]);
                OfflineTest.check(Boolean.TRUE.equals(result[0]),"exposure order "+seed+": "+Arrays.toString(result));
                OfflineTest.check(!LuaManager.exposer.isExposed(SteamReader.class) && !LuaManager.exposer.isExposed(SteamWriter.class),"native API internals remain unexposed");
            }
            System.out.println("PASS: all 8 real editor userdata types, inherited methods and nested return values across 12 exposure orders / fresh Lua environments.");
        } finally {LuaManager.env=originalEnv;LuaManager.exposer=originalExposer;}
    }
}
