package me.pavel.modstudio;

import java.lang.reflect.Method;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Map;
import java.util.WeakHashMap;
import zombie.HiddenFromLua;
import zombie.core.Core;
import zombie.core.znet.SteamUtils;
import zombie.core.znet.SteamWorkshop;
import zombie.core.znet.SteamWorkshopItem;

@HiddenFromLua
public final class Guard {
    static final Map<SteamWorkshopItem, Selection> selections = Collections.synchronizedMap(new WeakHashMap<>());
    static final ThreadLocal<Boolean> probing = ThreadLocal.withInitial(() -> false);
    static final ThreadLocal<Boolean> omitPreview = ThreadLocal.withInitial(() -> false);
    static boolean submitProbe;
    static Boolean health;
    static SteamWorkshopItem editorItem;
    static UploadRequest editorRequest;

    interface Backend { boolean call(String operation, Object value) throws Exception; }
    interface BackendFactory { Backend open(SteamWorkshop workshop) throws Exception; }
    // Package-private injection point for offline tests; never exposed to Lua.
    static BackendFactory backends = NativeBackend::new;

    static final class NativeBackend implements Backend {
        final SteamWorkshop workshop;
        final Map<String, Method> methods = new java.util.HashMap<>();
        NativeBackend(SteamWorkshop workshop) throws Exception {
            this.workshop = workshop;
            bind("start", "n_StartItemUpdate", long.class);
            bind("title", "n_SetItemTitle", String.class);
            bind("description", "n_SetItemDescription", String.class);
            bind("preview", "n_SetItemPreview", String.class);
            bind("tags", "n_SetItemTags", String[].class);
            bind("visibility", "n_SetItemVisibility", int.class);
            bind("content", "n_SetItemContent", String.class);
            bind("submit", "n_SubmitItemUpdate", String.class);
        }
        void bind(String key, String name, Class<?> type) throws Exception {
            Method method = SteamWorkshop.class.getDeclaredMethod(name, type);
            method.setAccessible(true);
            methods.put(key, method);
        }
        public boolean call(String operation, Object value) throws Exception {
            return (boolean) methods.get(operation).invoke(workshop, new Object[]{value});
        }
    }

    public static boolean isPreviewOmitted() { return omitPreview.get(); }

    static boolean ready() {
        if (health != null) return health;
        try {
            // GameVersion omits the hotfix number; getVersion includes it and the revision.
            if (!Core.getInstance().getVersion().startsWith("42.21.0 ")) return false;
            new NativeBackend(SteamWorkshop.instance); // Verify private API before promising protection.
            probing.set(true);
            submitProbe = false;
            SteamWorkshop.instance.SubmitWorkshopItem(null); // Unpatched code throws before any native call.
            if (!submitProbe) return false;
            omitPreview.set(true);
            SteamWorkshopItem item = new SteamWorkshopItem(zombie.ZomboidFileSystem.instance.getCacheDir() + "/Workshop");
            if (item.validatePreviewImage((Path) null) != null) return false;
            health = true;
            System.out.println("[ModStudio] Java patches verified for 42.21.0");
            return true;
        } catch (Throwable e) {
            System.err.println("[ModStudio] Protection unavailable: " + e);
            return false;
        } finally {
            probing.remove();
            omitPreview.remove();
        }
    }

    static Selection selection(SteamWorkshopItem item) { return selections.get(item); }

    static String validate(SteamWorkshopItem item, boolean finalCheck) {
        if (!ready()) return "MS_Unavailable";
        Selection s = selection(item);
        if (s == null) return "MS_Unavailable";
        if (finalCheck && !s.keep(Selection.TITLE) && item.getTitle().trim().isEmpty()) return "MS_EmptyTitle";
        if (finalCheck && !s.keep(Selection.DESCRIPTION) && item.getDescription().trim().isEmpty()) return "MS_EmptyDescription";
        boolean previous = omitPreview.get();
        omitPreview.set(!finalCheck || s.keep(Selection.PREVIEW));
        try { return LocalFiles.validateContents(item); }
        finally { omitPreview.set(previous); }
    }

    public static boolean submit(SteamWorkshop workshop, SteamWorkshopItem item) {
        if (probing.get()) { submitProbe = true; return false; }
        if(editorItem==item && editorRequest!=null) {
            UploadRequest request=editorRequest;editorRequest=null;editorItem=null;
            if(!java.util.Objects.equals(request.itemId,item.getID())) {request.fail(new IllegalStateException("identity"));return false;}
            request.start();return request.state.equals("saving") || request.state.equals("saved");
        }
        Selection s = selection(item);
        if (s == null || !s.armed) {
            System.err.println("[ModStudio] Upload blocked: no current publishing selection");
            return false;
        }
        s.armed = false; // Consume once; retries must be explicitly armed again by the UI.
        s.events.clear();
        s.error = null;
        String stage = "validation";
        try {
            if (item.getID() == null || !SteamUtils.isValidSteamID(item.getID()) ||
                (s.initialId != null && !s.initialId.equals(item.getID()))) return fail(s, "identity");
            String validation = validate(item, true);
            if (validation != null) return fail(s, validation);
            Backend backend = backends.open(workshop);
            stage = "start";
            if (!backend.call(stage, SteamUtils.convertStringToSteamID(item.getID()))) return fail(s, stage);
            String[] fields = {"title", "description", "visibility", "tags", "preview"};
            int[] bits = {Selection.TITLE, Selection.DESCRIPTION, Selection.VISIBILITY, Selection.TAGS, Selection.PREVIEW};
            for (int i = 0; i < fields.length; i++) {
                stage = fields[i];
                if (s.keep(bits[i])) { s.events.add("keep:" + stage); continue; }
                Object value = switch(stage) {
                    case "title" -> item.getTitle();
                    case "description" -> item.getSubmitDescription();
                    case "visibility" -> "Mod Template".equals(item.getTitle()) ? 2 : item.getVisibilityInteger();
                    case "tags" -> item.getSubmitTags();
                    default -> item.getPreviewImage();
                };
                if (!backend.call(stage, value)) return fail(s, stage);
                s.events.add("upload:" + stage);
            }
            stage = "content";
            if (!backend.call(stage, item.getContentFolder())) return fail(s, stage);
            stage = "submit";
            if (!backend.call(stage, item.getChangeNote())) return fail(s, stage);
            s.events.add("submitted");
            return true;
        } catch (Throwable e) {
            System.err.println("[ModStudio] Failed at " + stage + ": " + e);
            return fail(s, stage);
        }
    }

    static boolean fail(Selection s, String stage) {
        s.error = stage;
        s.events.add("error:" + stage);
        return false;
    }

    static ArrayList<String> drain(SteamWorkshopItem item) {
        Selection s = selection(item);
        ArrayList<String> result = new ArrayList<>();
        if (s != null) { result.addAll(s.events); s.events.clear(); }
        return result;
    }
}
