package me.pavel.modstudio.startup;

import java.io.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;

public final class StartupTrace {
    private static BufferedWriter writer;
    public static volatile boolean active;
    private static final long origin=System.nanoTime();
    private static final ThreadLocal<Integer> scanDepth=ThreadLocal.withInitial(()->0);
    public static void open(String output)throws IOException{
        active=true;
        if(output.isEmpty())return;
        Files.createDirectories(Path.of(output));
        writer=Files.newBufferedWriter(Path.of(output).resolve("startup-spans.jsonl"),StandardCharsets.UTF_8);
        Runtime.getRuntime().addShutdownHook(new Thread(()->{synchronized(StartupTrace.class){try{writer.close();}catch(IOException ignored){}}},"modstudio-startup-trace"));
    }
    public static long scanEnter(){if(!active)return 0;int depth=scanDepth.get();scanDepth.set(depth+1);return depth==0?System.nanoTime():0;}
    public static void scanExit(File root,long start,Throwable error){if(!active)return;scanDepth.set(scanDepth.get()-1);if(start!=0)span("searchFolders:"+root,start,error);}
    public static void finish(){active=false;}
    public static void span(String name,long start,Throwable error){
        long end=System.nanoTime();
        if(error==null && end-start<1_000_000 && name.endsWith(".getAllModFolders"))return;
        write("{\"name\":"+quote(name)+",\"start_ms\":"+(start-origin)/1e6+",\"duration_ms\":"+(end-start)/1e6+",\"error\":"+quote(error==null?"":error.toString())+"}");
    }
    public static void note(String name,String detail){write("{\"name\":"+quote(name)+",\"detail\":"+quote(detail)+"}");}
    private static String quote(String text){return "\""+text.replace("\\","\\\\").replace("\"","\\\"").replace("\n","\\n").replace("\r","\\r")+"\"";}
    private static synchronized void write(String line){try{if(active&&writer!=null){writer.write(line);writer.newLine();writer.flush();}}catch(IOException e){System.err.println("[Mod Studio startup] trace error: "+e);}}
}
