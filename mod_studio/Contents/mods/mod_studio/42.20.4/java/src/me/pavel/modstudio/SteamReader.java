package me.pavel.modstudio;

import java.lang.foreign.*;
import java.lang.invoke.MethodHandle;
import java.nio.ByteBuffer;
import java.nio.charset.*;
import java.nio.file.Path;
import java.util.*;
import java.util.function.LongSupplier;
import zombie.HiddenFromLua;
import static java.lang.foreign.ValueLayout.*;

/** Read-only SteamUGC v021 client bridge. Never initializes Steam or pumps the game's callbacks. */
@HiddenFromLua
public final class SteamReader {
    static final int APP_ID = 108600;
    // Valve's Windows x64 SDK layout, pack(8). v021 includes m_ulTotalFilesSize.
    static final int DETAILS_SIZE = 9784, CALLBACK_SIZE = 280, QUERY_CALLBACK = 3401;
    static final long TIMEOUT_NANOS = 30_000_000_000L;
    static final Set<String> LANGUAGES = Set.of("english", "arabic", "bulgarian", "schinese",
        "tchinese", "czech", "danish", "dutch", "finnish", "french", "german", "greek",
        "hungarian", "indonesian", "italian", "japanese", "koreana", "norwegian", "polish",
        "portuguese", "brazilian", "romanian", "russian", "spanish", "latam", "swedish",
        "thai", "turkish", "ukrainian", "vietnamese", "malay");

    interface Calls { Object call(String name, Object... args) throws Throwable; }
    final Calls calls;
    final LongSupplier clock;

    SteamReader(Calls calls, LongSupplier clock) { this.calls = calls; this.clock = clock; }
    public static SteamReader open(Path library) {
        return new SteamReader(new NativeCalls(library), System::nanoTime);
    }

    public ReadRequest begin(String itemId, String language) {
        ReadRequest request = new ReadRequest(this, itemId, language, clock.getAsLong());
        try {
            if (itemId == null || !itemId.matches("[1-9][0-9]{0,19}")) throw new ReadFailure("invalid_id");
            long id = Long.parseUnsignedLong(itemId);
            if (!LANGUAGES.contains(language)) throw new ReadFailure("invalid_language");
            MemorySegment ugc = (MemorySegment)calls.call("SteamAPI_SteamUGC_v021");
            MemorySegment utils = (MemorySegment)calls.call("SteamAPI_SteamUtils_v010");
            if (ugc.address() == 0 || utils.address() == 0) throw new ReadFailure("steam_unavailable");
            request.ugc = ugc; request.utils = utils;
            if ((int)calls.call("SteamAPI_ISteamUtils_GetAppID", utils) != APP_ID) throw new ReadFailure("wrong_app");
            try (Arena arena = Arena.ofConfined()) {
                MemorySegment ids = arena.allocate(JAVA_LONG); ids.set(JAVA_LONG, 0, id);
                request.query = (long)calls.call("SteamAPI_ISteamUGC_CreateQueryUGCDetailsRequest", ugc, ids, 1);
                if (request.query == -1L || request.query == 0L) throw new ReadFailure("create_query");
                require("SetLanguage", ugc, request.query, arena.allocateFrom(language));
                require("SetReturnLongDescription", ugc, request.query, true);
                require("SetReturnChildren", ugc, request.query, true);
                require("SetReturnMetadata", ugc, request.query, true);
                require("SetAllowCachedResponse", ugc, request.query, 0);
                request.apiCall = (long)calls.call("SteamAPI_ISteamUGC_SendQueryUGCRequest", ugc, request.query);
                if (request.apiCall == 0) throw new ReadFailure("send_query");
            }
        } catch (Throwable e) { request.fail(error(e)); }
        return request;
    }

    void poll(ReadRequest request) {
        if (!request.state.equals("loading")) return;
        if (clock.getAsLong() - request.started >= TIMEOUT_NANOS) { request.fail("timeout"); return; }
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment failed = arena.allocate(JAVA_BOOLEAN);
            boolean completed = (boolean)calls.call("SteamAPI_ISteamUtils_IsAPICallCompleted", request.utils, request.apiCall, failed);
            if (failed.get(JAVA_BOOLEAN, 0)) throw new ReadFailure("steam_call_failed");
            if (!completed) return;
            MemorySegment callback = arena.allocate(CALLBACK_SIZE, 8);
            boolean received = (boolean)calls.call("SteamAPI_ISteamUtils_GetAPICallResult", request.utils,
                request.apiCall, callback, CALLBACK_SIZE, QUERY_CALLBACK, failed);
            if (!received || failed.get(JAVA_BOOLEAN, 0)) throw new ReadFailure("callback_failed");
            if (callback.get(JAVA_LONG, 0) != request.query) throw new ReadFailure("query_mismatch");
            int result = callback.get(JAVA_INT, 8);
            if (result != 1) throw new ReadFailure("steam_result_" + result);
            if (callback.get(JAVA_INT, 12) != 1) throw new ReadFailure("item_unavailable");
            request.data = read(request, arena);
            request.state = "loaded";
            request.release();
        } catch (Throwable e) { request.fail(error(e)); }
    }

    private Snapshot read(ReadRequest request, Arena arena) throws Throwable {
        MemorySegment details = arena.allocate(DETAILS_SIZE, 8);
        require("GetQueryUGCResult", request.ugc, request.query, 0, details);
        if (details.get(JAVA_LONG, 0) != Long.parseUnsignedLong(request.itemId)) throw new ReadFailure("item_mismatch");
        if (details.get(JAVA_INT, 8) != 1) throw new ReadFailure("item_result_" + details.get(JAVA_INT, 8));
        if (details.get(JAVA_INT, 20) != APP_ID) throw new ReadFailure("wrong_item_app");
        String title = string(details, 24, 129), description = string(details, 153, 8000);
        int childCount = bounded(details.get(JAVA_INT, 9768), 4096, "dependencies");
        List<String> children = new ArrayList<>();
        if (childCount > 0) {
            MemorySegment ids = arena.allocate((long)childCount * 8, 8);
            require("GetQueryUGCChildren", request.ugc, request.query, 0, ids, childCount);
            for (int i=0; i<childCount; i++) children.add(Long.toUnsignedString(ids.getAtIndex(JAVA_LONG, i)));
        }
        int tagCount = bounded((int)calls.call("SteamAPI_ISteamUGC_GetQueryUGCNumTags", request.ugc, request.query, 0), 4096, "tags");
        List<String> tags = new ArrayList<>();
        MemorySegment tag = arena.allocate(4096);
        for (int i=0; i<tagCount; i++) {
            tag.fill((byte)0);
            require("GetQueryUGCTag", request.ugc, request.query, 0, i, tag, 4096);
            tags.add(string(tag, 0, 4096));
        }
        MemorySegment metadata = arena.allocate(10001);
        boolean metadataKnown = (boolean)calls.call("SteamAPI_ISteamUGC_GetQueryUGCMetadata", request.ugc, request.query, 0, metadata, 10001);
        MemorySegment preview = arena.allocate(8192);
        boolean previewKnown = (boolean)calls.call("SteamAPI_ISteamUGC_GetQueryUGCPreviewURL", request.ugc, request.query, 0, preview, 8192);
        MemorySegment descriptors = arena.allocate(64 * 4, 4);
        int descriptorCount = bounded((int)calls.call("SteamAPI_ISteamUGC_GetQueryUGCContentDescriptors", request.ugc, request.query, 0, descriptors, 64), 64, "descriptors");
        List<Integer> contentDescriptors = new ArrayList<>();
        for (int i=0; i<descriptorCount; i++) contentDescriptors.add(descriptors.getAtIndex(JAVA_INT, i));
        return new Snapshot(title, description, details.get(JAVA_INT, 8180),
            Integer.toUnsignedLong(details.get(JAVA_INT, 8172)), List.copyOf(children), List.copyOf(tags),
            metadataKnown ? string(metadata, 0, 10001) : null,
            previewKnown ? string(preview, 0, 8192) : null, List.copyOf(contentDescriptors));
    }

    void require(String suffix, Object... args) throws Throwable {
        if (!(boolean)calls.call("SteamAPI_ISteamUGC_" + suffix, args)) throw new ReadFailure(suffix);
    }
    static int bounded(int n, int max, String field) {
        if (n < 0 || n > max) throw new ReadFailure("invalid_" + field + "_count");
        return n;
    }
    static String string(MemorySegment data, long offset, int capacity) throws CharacterCodingException {
        byte[] bytes = data.asSlice(offset, capacity).toArray(JAVA_BYTE);
        int n=0; while (n<bytes.length && bytes[n]!=0) n++;
        if (n == bytes.length) throw new ReadFailure("unterminated_string");
        return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes, 0, n)).toString();
    }
    static String error(Throwable e) {
        if (e instanceof ReadFailure) return e.getMessage();
        if (e instanceof NumberFormatException) return "invalid_id";
        if (e instanceof CharacterCodingException) return "invalid_utf8";
        return "bridge_error:" + e.getClass().getSimpleName();
    }
    static final class ReadFailure extends RuntimeException { ReadFailure(String message) { super(message); } }
    record Snapshot(String title, String description, int visibility, long updated,
        List<String> dependencies, List<String> tags, String metadata, String previewUrl, List<Integer> descriptors) {}

    /** Binds only read operations. Merely constructing this object makes no Steam API calls. */
    static class NativeCalls implements Calls {
        final Map<String, MethodHandle> methods = new LinkedHashMap<>();
        final SymbolLookup symbols;
        NativeCalls(Path library) {
            if (!System.getProperty("os.name").startsWith("Windows") || ADDRESS.byteSize()!=8)
                throw new ReadFailure("unsupported_platform");
            symbols = SymbolLookup.libraryLookup(library.toAbsolutePath(), Arena.global());
            bind(symbols, "SteamAPI_SteamUGC_v021", ADDRESS);
            bind(symbols, "SteamAPI_SteamUtils_v010", ADDRESS);
            bind(symbols, "SteamAPI_ISteamUtils_GetAppID", JAVA_INT, ADDRESS);
            bind(symbols, "SteamAPI_ISteamUtils_IsAPICallCompleted", JAVA_BOOLEAN, ADDRESS, JAVA_LONG, ADDRESS);
            bind(symbols, "SteamAPI_ISteamUtils_GetAPICallResult", JAVA_BOOLEAN, ADDRESS, JAVA_LONG, ADDRESS, JAVA_INT, JAVA_INT, ADDRESS);
            bind(symbols, "SteamAPI_ISteamUGC_CreateQueryUGCDetailsRequest", JAVA_LONG, ADDRESS, ADDRESS, JAVA_INT);
            bind(symbols, "SteamAPI_ISteamUGC_SetLanguage", JAVA_BOOLEAN, ADDRESS, JAVA_LONG, ADDRESS);
            for (String name : List.of("SetReturnLongDescription", "SetReturnChildren", "SetReturnMetadata"))
                bind(symbols, "SteamAPI_ISteamUGC_" + name, JAVA_BOOLEAN, ADDRESS, JAVA_LONG, JAVA_BOOLEAN);
            bind(symbols, "SteamAPI_ISteamUGC_SetAllowCachedResponse", JAVA_BOOLEAN, ADDRESS, JAVA_LONG, JAVA_INT);
            bind(symbols, "SteamAPI_ISteamUGC_SendQueryUGCRequest", JAVA_LONG, ADDRESS, JAVA_LONG);
            bind(symbols, "SteamAPI_ISteamUGC_ReleaseQueryUGCRequest", JAVA_BOOLEAN, ADDRESS, JAVA_LONG);
            bind(symbols, "SteamAPI_ISteamUGC_GetQueryUGCResult", JAVA_BOOLEAN, ADDRESS, JAVA_LONG, JAVA_INT, ADDRESS);
            bind(symbols, "SteamAPI_ISteamUGC_GetQueryUGCChildren", JAVA_BOOLEAN, ADDRESS, JAVA_LONG, JAVA_INT, ADDRESS, JAVA_INT);
            bind(symbols, "SteamAPI_ISteamUGC_GetQueryUGCNumTags", JAVA_INT, ADDRESS, JAVA_LONG, JAVA_INT);
            bind(symbols, "SteamAPI_ISteamUGC_GetQueryUGCTag", JAVA_BOOLEAN, ADDRESS, JAVA_LONG, JAVA_INT, JAVA_INT, ADDRESS, JAVA_INT);
            for (String name : List.of("GetQueryUGCMetadata", "GetQueryUGCPreviewURL"))
                bind(symbols, "SteamAPI_ISteamUGC_" + name, JAVA_BOOLEAN, ADDRESS, JAVA_LONG, JAVA_INT, ADDRESS, JAVA_INT);
            bind(symbols, "SteamAPI_ISteamUGC_GetQueryUGCContentDescriptors", JAVA_INT, ADDRESS, JAVA_LONG, JAVA_INT, ADDRESS, JAVA_INT);
        }
        void bind(SymbolLookup symbols, String name, MemoryLayout result, MemoryLayout... args) {
            MemorySegment address = symbols.find(name).orElseThrow(() -> new ReadFailure("missing_symbol:" + name));
            methods.put(name, Linker.nativeLinker().downcallHandle(address, FunctionDescriptor.of(result, args)));
        }
        public Object call(String name, Object... args) throws Throwable {
            MethodHandle method = methods.get(name);
            if (method == null) throw new ReadFailure("unbound_method");
            return method.invokeWithArguments(args);
        }
    }
}
