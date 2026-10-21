package me.pavel.modstudio;

import java.nio.file.*;
import java.util.*;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;
import me.zed_0xff.zombie_buddy.PatchEngine;
import zombie.ZomboidFileSystem;
import zombie.core.znet.SteamWorkshop;
import zombie.core.znet.SteamWorkshopItem;
import zombie.network.GameServer;

/** Exercises the real installed game + ZombieBuddy patches; native Steam calls are recorded only. */
public class OfflineTest {
    static int assertions;
    static void check(boolean value, String message) {
        assertions++;
        if (!value) throw new AssertionError(message);
    }
    static class Recorder implements Guard.Backend {
        final Map<String,Object> calls = new LinkedHashMap<>();
        String reject;
        public boolean call(String op, Object value) { calls.put(op, value); return !op.equals(reject); }
    }
    static SteamWorkshopItem item(Path folder, String id) {
        SteamWorkshopItem item = new SteamWorkshopItem(folder.toString());
        item.setID(id); item.setTitle("Local title"); item.setDescription("Local description");
        item.setTags(new ArrayList<>(List.of("Build 42", "Interface")));
        item.setVisibilityInteger(2); item.setChangeNote("Offline test");
        Bridge.begin(item);
        return item;
    }
    public static void main(String[] args) throws Exception {
        ReaderTest.run(Path.of(args[0], "steam_api64.dll"));
        Path root = Path.of(args[1]).toAbsolutePath();
        Files.createDirectories(root);
        ManifestTest.run(root);
        GameServer.server = true;
        ZomboidFileSystem.instance.base.set(new java.io.File(args[0]));
        ZomboidFileSystem.instance.setCacheDir(root.toString());
        PatchEngine.applyPatches("me.pavel.modstudio", OfflineTest.class.getClassLoader());
        System.out.println("Game version: " + zombie.core.Core.getInstance().getGameVersion());
        check(Bridge.isReady(), "Both actual patches must pass the handshake");
        ReleaseContentTest.run(root);
        Path folder = root.resolve("Workshop/fixture");
        Path mod = folder.resolve("Contents/mods/fixture/42.20.4");
        Files.createDirectories(mod);
        Files.writeString(mod.resolve("mod.info"), "name=Fixture\nid=ModStudioTest\n");
        Path preview = folder.resolve("preview.png");
        ImageIO.write(new BufferedImage(512, 512, BufferedImage.TYPE_INT_RGB), "png", preview.toFile());
        WriterTest.run(Path.of(args[0], "steam_api64.dll"),folder);
        String[] names = {"title", "description", "preview", "tags", "visibility"};
        int[] bits = {1, 2, 4, 8, 16};
        for (int mask=0; mask<32; mask++) {
            Recorder r = new Recorder(); Guard.backends = ignored -> r;
            SteamWorkshopItem item = item(folder, "1234567890");
            Bridge.configure(item, mask);
            check(Bridge.arm(item), "arm mask " + mask);
            check(SteamWorkshop.instance.SubmitWorkshopItem(item), "patched submit mask " + mask);
            for (int i=0; i<5; i++) check(r.calls.containsKey(names[i]) == ((mask & bits[i]) == 0), "setter " + names[i] + " mask " + mask);
            check(r.calls.containsKey("content") && r.calls.containsKey("submit"), "content always sent");
            if (r.calls.containsKey("description")) check(r.calls.get("description").toString().contains("Workshop ID: 1234567890"), "game description footer");
            int count = r.calls.size();
            check(!SteamWorkshop.instance.SubmitWorkshopItem(item) && r.calls.size() == count, "selection consumed once");
        }
        Recorder r = new Recorder(); final Recorder record = r; Guard.backends = ignored -> record;
        SteamWorkshopItem existing = item(folder, "1234567890");
        existing.setTitle(""); existing.setDescription(""); Files.delete(preview);
        check(Bridge.validate(existing, true) == null, "kept empty metadata and missing preview allowed");
        check(Bridge.arm(existing) && SteamWorkshop.instance.SubmitWorkshopItem(existing), "content-only succeeds");
        check(r.calls.keySet().equals(new LinkedHashSet<>(List.of("start","content","submit"))), "exact content-only request");
        Bridge.configure(existing, 30);
        check("MS_EmptyTitle".equals(Bridge.validate(existing, true)), "upload title requires text");
        existing.setTitle("Local"); Bridge.configure(existing, 29);
        check("MS_EmptyDescription".equals(Bridge.validate(existing, true)), "upload description requires text");
        existing.setDescription("Local"); Bridge.configure(existing, 27);
        check("PreviewNotFound".equals(Bridge.validate(existing, true)), "upload preview requires image");
        check("PreviewNotFound".equals(existing.validateContents()), "preview skip cannot leak out of scoped validation");
        SteamWorkshopItem fresh = item(folder, null); Bridge.configure(fresh, 31);
        check("PreviewNotFound".equals(Bridge.validate(fresh, true)), "creation cannot omit preview");
        check(Bridge.validate(fresh, false) == null, "initial screen can defer preview validation");
        ImageIO.write(new BufferedImage(512,512,BufferedImage.TYPE_INT_RGB), "png", preview.toFile());
        Recorder creation = new Recorder(); Guard.backends = ignored -> creation;
        check(Bridge.arm(fresh), "creation arms before Steam assigns ID");
        fresh.setID("1234567890");
        check(SteamWorkshop.instance.SubmitWorkshopItem(fresh), "creation after ID callback");
        check(creation.calls.size() == 8, "creation sends all metadata, contents, and submit");
        for (String failure : List.of("start","title","description","preview","tags","visibility","content","submit")) {
            Recorder rejected = new Recorder(); rejected.reject = failure; Guard.backends = ignored -> rejected;
            SteamWorkshopItem failing = item(folder, "1234567890"); Bridge.configure(failing, 0);
            check(Bridge.arm(failing), "arm failing stage");
            check(!SteamWorkshop.instance.SubmitWorkshopItem(failing), "rejected " + failure);
            check(failure.equals(new ArrayList<>(rejected.calls.keySet()).getLast()), "no calls after rejected " + failure);
            check(Bridge.drain(failing).contains("error:" + failure), "logged failure " + failure);
        }
        Recorder blocked = new Recorder(); Guard.backends = ignored -> blocked;
        SteamWorkshopItem changed = item(folder, "1234567890"); Bridge.arm(changed); changed.setID("1234567891");
        check(!SteamWorkshop.instance.SubmitWorkshopItem(changed) && blocked.calls.isEmpty(), "changed identity blocked before native calls");
        Bridge.begin(changed); Bridge.configure(changed, 0); Bridge.begin(changed);
        check(Guard.selection(changed).keepMask == 31, "reopening resets choices");
        Bridge.clear(changed);
        check(!SteamWorkshop.instance.SubmitWorkshopItem(changed) && blocked.calls.isEmpty(), "no UI selection blocks submission");
        LuaExposureTest.run(folder);
        Files.writeString(mod.resolve("not-allowed.exe"), "fixture");
        SteamWorkshopItem unsafe = item(folder, "1234567890");
        check("FileTypeNotAllowed".equals(Bridge.validate(unsafe, true)), "file validation still enforced");
        System.out.println("PASS: " + assertions + " assertions; 32 field combinations; no Steam native calls.");
        var platform = se.krka.kahlua.j2se.J2SEPlatform.getInstance();
        var env = platform.newEnvironment();
        var thread = new se.krka.kahlua.vm.KahluaThread(platform, env);
        thread.debugOwnerThread = Thread.currentThread();
        Path packageRoot = Path.of(args[2]);
        Bridge.validateFiles(new SteamWorkshopItem(folder.toString()) {
            @Override public String getContentFolder(){return packageRoot.resolve("Contents").toString();}
        });
        check(Files.isRegularFile(packageRoot.resolve("Contents/mods/mod_studio/42.20.4/media/java/client/ModStudio.jar.zbs")),"signed publication package present and passes real content validator");
        String ui = Files.readString(packageRoot.resolve("tests/ui.lua"));
        String source = Files.readString(packageRoot.resolve("Contents/mods/mod_studio/common/media/lua/client/ModStudio.lua"));
        LayoutFixtures.install(platform,env,Path.of(args[0]),packageRoot);
        ui=ui.replace("-- NATIVE_WIDGET_GEOMETRY",LayoutFixtures.nativeGeometry(Path.of(args[0])));
        var chunk = se.krka.kahlua.luaj.compiler.LuaCompiler.loadstring(ui.replace("-- MOD_UNDER_TEST", source), "ModStudio UI tests", env);
        Object[] result = thread.pcall(chunk, new Object[0]);
        check(Boolean.TRUE.equals(result[0]), "Kahlua UI test: " + Arrays.toString(result));
        LayoutRaster.write(env,Path.of(args[0]));
        System.out.println("PASS: Kahlua editor integration: language drafts, separate saves, omitted fields, reload and error states.");
        System.out.println("PASS: "+env.rawget("MSLayoutCount")+" locale/font/window layouts; native widget sizing and installed font metrics; "+env.rawget("MSUICheckCount")+" UI checks.");
    }
}
