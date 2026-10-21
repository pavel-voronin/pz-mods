package me.pavel.modstudio;

import java.lang.foreign.*;
import java.lang.invoke.MethodHandle;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import static java.lang.foreign.ValueLayout.*;

/** Standalone read-only Steam probe; never launches the game or changes publications. */
public final class ReadProbe {
    public static void main(String[] args) throws Throwable {
        Path library=Path.of(args[0]);
        SymbolLookup symbols=SymbolLookup.libraryLookup(library,Arena.global());
        Linker linker=Linker.nativeLinker();
        MethodHandle init=linker.downcallHandle(symbols.find("SteamAPI_InitFlat").orElseThrow(),FunctionDescriptor.of(JAVA_INT, ADDRESS));
        MethodHandle callbacks=linker.downcallHandle(symbols.find("SteamAPI_RunCallbacks").orElseThrow(),FunctionDescriptor.ofVoid());
        MethodHandle shutdown=linker.downcallHandle(symbols.find("SteamAPI_Shutdown").orElseThrow(),FunctionDescriptor.ofVoid());
        try (Arena arena=Arena.ofConfined()) {
            MemorySegment message=arena.allocate(1024);
            int result=(int)init.invokeExact(message);
            if(result!=0) throw new IllegalStateException("Steam initialization failed ("+result+"): "+message.getString(0));
        }
        ReadRequest request=null;
        try {
            request=SteamReader.open(library).begin(args[1],args[2]);
            while(request.getState().equals("loading")) { callbacks.invokeExact();request.poll();Thread.sleep(50); }
            if(!request.getState().equals("loaded")) throw new IllegalStateException(request.getError());
            System.out.println("Workshop ID: "+request.getItemId());
            System.out.println("Requested language: "+request.getRequestedLanguage());
            System.out.println("Translation exists: unknown (Steam may return fallback text)");
            System.out.println("Title: "+request.getTitle());
            System.out.println("Description: "+request.getDescription().getBytes(StandardCharsets.UTF_8).length+" UTF-8 bytes");
            System.out.println("Dependencies: "+request.getDependencies());
            System.out.println("Tags: "+request.getTags());
            System.out.println("Content descriptors: "+request.getContentDescriptors());
            System.out.println("Preview URL: "+request.getPreviewUrl());
            if(args.length>3 && args[3].equals("--preview")) {
                zombie.network.GameServer.server=true; // Headless asset decoding only; no game/UI/render context.
                PreviewDownload preview=PreviewDownload.start(request);
                try {
                    while(preview.getState().equals("loading")) Thread.sleep(20);
                    if(!preview.getState().equals("loaded")) throw new IllegalStateException("Preview download: "+preview.getError());
                    PreviewInfo info=preview.getInfo();
                    System.out.println("Downloaded preview: "+info.getFormat()+" "+info.getWidth()+"x"+info.getHeight()+", "+(long)info.getBytes()+" bytes, "+info.getFrames()+" frame(s)");
                } finally {preview.cancel();}
            }
            System.out.println("Metadata: "+(request.getMetadata()==null?"unavailable":request.getMetadata().isEmpty()?"empty":"present"));
            System.out.println("Read completed. No publication changes were sent.");
        } finally { if(request!=null) request.cancel();shutdown.invokeExact(); }
    }
}
