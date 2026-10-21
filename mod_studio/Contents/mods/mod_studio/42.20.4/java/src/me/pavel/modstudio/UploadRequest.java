package me.pavel.modstudio;

import java.lang.foreign.MemorySegment;
import java.util.List;
import me.zed_0xff.zombie_buddy.Exposer;

@Exposer.LuaClass(name="ModStudioUploadRequest")
public class UploadRequest {
    final SteamWriter writer;
    String itemId;
    final String changeNote;
    final List<SteamWriter.Change> changes;
    final boolean dependencies;
    String state="prepared",stage="",error;
    MemorySegment ugc,utils;
    long update,apiCall,started;
    int callback,callbackSize,completed;
    boolean legal,slow;
    double progress;
    UploadRequest(SteamWriter writer,String id,List<SteamWriter.Change> changes,String note,boolean dependencies) {
        this.writer=writer;itemId=id;this.changes=List.copyOf(changes);changeNote=note;this.dependencies=dependencies;
    }
    void start(){writer.start(this);}
    void fail(Throwable e){error=stage+":"+e.getMessage();state="error";}
    public void poll(){writer.poll(this);}
    public String getState(){return state;}
    public String getError(){return error;}
    public String getStage(){return stage;}
    public boolean needsLegalAgreement(){return legal;}
    public boolean isSlow(){return slow;}
    public int getCompletedOperations(){return completed;}
    public double getProgress(){return progress;}
}
