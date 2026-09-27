package me.pavel.modstudio;

import java.nio.file.*;
import java.util.*;
import zombie.core.znet.SteamWorkshop;
import static me.pavel.modstudio.OfflineTest.*;

final class ReleaseContentTest {
    static void run(Path root)throws Exception {
        Path folder=root.resolve("release-fixture");
        Path source=folder.resolve("Contents/mods/dev/42.20.4");
        Path release=folder.resolve("Contents.release");
        Path runtime=release.resolve("mods/runtime/42.20.4");
        Files.createDirectories(source);Files.createDirectories(runtime);
        Files.writeString(source.resolve("mod.info"),"name=Development\nid=Development\n");
        Files.writeString(source.resolve("private.exe"),"source must not be uploaded");
        Files.writeString(runtime.resolve("mod.info"),"name=Runtime\nid=Runtime\n");
        Files.writeString(runtime.resolve("live.lua"),"return true");
        var item=item(folder,"1234567890");Bridge.configure(item,31);
        check(Path.of(item.getContentFolder()).equals(release),"actual native getter selects release root");
        check(Bridge.validate(item,true)==null,"native validation sees runtime instead of invalid development content");
        var recorder=new Recorder();Guard.backends=ignored->recorder;
        check(Bridge.arm(item)&&SteamWorkshop.instance.SubmitWorkshopItem(item),"release submission reaches native upload adapter");
        check(Path.of((String)recorder.calls.get("content")).equals(release),"Steam receives release root without an extra directory level");
        var entries=LocalFiles.listAssets(item,"");
        check(entries.size()==1&&entries.getFirst().getName().equals("Contents (release)")&&entries.getFirst().getPath().equals("Contents"),"asset browser shows one logical Contents root with release marker");
        check(LocalFiles.assetPath(item,"Contents/mods/runtime/42.20.4/live.lua").equals(runtime.resolve("live.lua").toRealPath()),"logical asset path resolves release bytes");
        check(LocalFiles.listAssets(item,"Contents/mods").getFirst().getPath().equals("Contents/mods/runtime"),"nested paths never expose Contents.release");
        var scan=FileScan.start(Path.of(item.getContentFolder()),null,null);AssetTest.await(scan);
        check(scan.getContentLabel().equals("Contents (release)")&&scan.getFileCount()==2,"scan size and root label use release package");
        check(scan.snapshot.keySet().equals(Set.of("mods/runtime/42.20.4/mod.info","mods/runtime/42.20.4/live.lua")),"manifest paths remain normal Contents-relative paths");
        Path developmentNotes=folder.resolve("Contents/release-notes.txt");
        Files.writeString(developmentNotes,"Development notes");
        check(Bridge.loadReleaseNotes(item).equals(""),"missing release notes never fall back to development notes");
        String notes="Fixed\r\n- Flashlight colors\r\n- Исправление\r\n";
        Files.writeString(release.resolve("release-notes.txt"),"\uFEFF"+notes);
        check(Bridge.loadReleaseNotes(item).equals(notes),"release notes preserve UTF-8 and line breaks, stripping BOM");
        check(Bridge.validate(item,true)==null,"release notes are allowed while native mod validation remains active");
        Files.writeString(release.resolve("unexpected.txt"),"other root files stay forbidden");
        check("FileNotAllowedInContents".equals(Bridge.validate(item,true)),"only release-notes.txt is allowed at root");
        Files.delete(release.resolve("unexpected.txt"));
        Files.writeString(runtime.resolve("bad.exe"),"invalid release");
        Files.writeString(release.resolve("release-notes.txt"),"");
        check(Bridge.loadReleaseNotes(item).equals(""),"empty release notes stay empty");
        check("FileTypeNotAllowed".equals(Bridge.validate(item,true)),"invalid release is rejected rather than silently falling back");
        Files.move(release,folder.resolve("saved-release"));
        check(Path.of(item.getContentFolder()).equals(folder.resolve("Contents")),"removing release restores ordinary content selection");
        check(Bridge.loadReleaseNotes(item).equals("Development notes"),"ordinary packages load development notes");
        check("FileTypeNotAllowed".equals(Bridge.validate(item,true)),"fallback validates development content normally");
        System.out.println("PASS: release content routing, real native validation/upload, logical asset paths and manifest hashing.");
    }
}
