package me.pavel.modstudio;

import java.nio.file.Path;
import java.util.*;

/** Opt-in read-only network probe. Does not initialize the game or download item content. */
public final class ManifestProbe {
    public static void main(String[] args) throws Exception {
        for(int pass=1;pass<=2;pass++) {
            long start=System.nanoTime();List<String> phases=new ArrayList<>();
            FileScan scan=FileScan.start(Path.of(args[1]),args[0],ManifestSource.LIVE);
            while(scan.getState().equals("loading")) {
                String phase=scan.getPhase();if(phases.isEmpty() || !phases.getLast().equals(phase)) {phases.add(phase);System.out.println("Phase: "+phase);}
                if(System.nanoTime()-start>120_000_000_000L) {scan.cancel();throw new AssertionError("probe timeout");}
                Thread.sleep(50);
            }
            if(!scan.getState().equals("ready") || !scan.getBasis().equals("manifest")) throw new AssertionError(scan.getState()+" "+scan.getError()+" "+scan.getComparisonError());
            System.out.printf(Locale.ROOT,"Pass %d: manifest=%s files=%d same=%d added=%d changed=%d removed=%d elapsed=%.2fs%n",pass,scan.getManifestId(),scan.getFileCount(),scan.getUnchanged(),scan.getAdded(),scan.getModified(),scan.getRemoved(),(System.nanoTime()-start)/1e9);
            for(String entry:scan.getEntries()) if(!entry.startsWith("same\t")) System.out.println(entry);
            if(pass==2 && phases.contains("connecting")) throw new AssertionError("unchanged manifest must not be downloaded twice");
        }
    }
}
