package me.pavel.modstudio;

import java.lang.foreign.MemorySegment;
import java.util.ArrayList;
import me.zed_0xff.zombie_buddy.Exposer;

/** One explicit read; results never imply that the requested translation exists. */
@Exposer.LuaClass(name="ModStudioReadRequest")
public final class ReadRequest {
    final SteamReader reader;
    final String itemId, language;
    final long started;
    long query = -1, apiCall;
    MemorySegment ugc, utils;
    String state = "loading", error;
    SteamReader.Snapshot data;

    ReadRequest(SteamReader reader, String id, String language, long started) {
        this.reader=reader; this.itemId=id; this.language=language; this.started=started;
    }
    public void poll() { reader.poll(this); }
    public void cancel() { if (state.equals("loading")) { state="cancelled"; release(); } }
    void fail(String error) { this.error=error; state="error"; release(); }
    void release() {
        long handle=query; query=-1;
        if (handle == -1 || handle == 0 || ugc == null) return;
        try { reader.calls.call("SteamAPI_ISteamUGC_ReleaseQueryUGCRequest", ugc, handle); }
        catch (Throwable e) { System.err.println("[ModStudio] Could not release read query: " + e.getClass().getSimpleName()); }
    }
    public String getState() { return state; }
    public String getError() { return error; }
    public String getItemId() { return itemId; }
    public String getRequestedLanguage() { return language; }
    // SteamUGCDetails_t has no actual-language or translation-presence member.
    public String getTranslationPresence() { return "unknown"; }
    public String getTitle() { return data==null ? null : data.title(); }
    public String getDescription() { return data==null ? null : data.description(); }
    public int getVisibility() { return data==null ? -1 : data.visibility(); }
    public long getUpdated() { return data==null ? 0 : data.updated(); }
    public String getMetadata() { return data==null ? null : data.metadata(); }
    public String getPreviewUrl() { return data==null ? null : data.previewUrl(); }
    public ArrayList<String> getDependencies() { return data==null ? new ArrayList<>() : new ArrayList<>(data.dependencies()); }
    public ArrayList<String> getTags() { return data==null ? new ArrayList<>() : new ArrayList<>(data.tags()); }
    public ArrayList<Integer> getContentDescriptors() { return data==null ? new ArrayList<>() : new ArrayList<>(data.descriptors()); }
}
