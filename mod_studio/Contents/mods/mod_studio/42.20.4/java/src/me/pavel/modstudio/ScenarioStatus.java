package me.pavel.modstudio;

import java.util.*;
import zombie.core.Translator;
import zombie.ui.UIFont;
import zombie.ui.TextManager;
import me.zed_0xff.zombie_buddy.Patch;

/** One bounded snapshot; native UI owns drawing, the existing writer owns disk IO. */
public final class ScenarioStatus {
    record Snapshot(long at,String id,String phase,int step,int total,String command,String next,double elapsed,double left,boolean exact,double future,double limits) {}
    private static volatile Snapshot snapshot;
    private static long textAt;
    private static String[] text=new String[0];
    static void update(String id,String phase,int step,int total,String command,String next,double elapsed,double left,boolean exact,double future,double limits){
        snapshot=new Snapshot(System.nanoTime(),clean(id),clean(phase).toLowerCase(Locale.ROOT),step,total,clean(command),clean(next),Math.max(0,elapsed),Math.max(0,left),exact,Math.max(0,future),Math.max(0,limits));
    }
    static String clean(String value){if(value==null)return "";var out=new StringBuilder();for(int i=0;i<value.length()&&out.length()<72;i++){char c=value.charAt(i);out.append(c>=32&&c<127?c:'?');}return out.toString();}
    static String seconds(double value){return (int)Math.ceil(Math.max(0,value))+"s";}
    static String[] lines(Snapshot s,long now,boolean blocked,java.util.function.Function<String,String> label){
        double age=Math.max(0,now-s.at)/1e9;
        String running=label.apply(age>5?"Waiting":"Running")+" "+"....".substring(0,1+(int)(now/500_000_000L%4));
        String clock=s.exact?label.apply("Left"):label.apply("Limit");
        return new String[]{label.apply("Scenario")+" "+s.id+" | "+running,
            s.step+"/"+s.total+" "+(s.command.isEmpty()?s.phase:s.command)+" | "+s.phase+" | "+seconds(s.elapsed+age)+" | "+clock+" "+seconds(s.left-age),
            label.apply("Next")+" "+(s.next.isEmpty()?"-":s.next)+" | "+label.apply("Timed")+" "+seconds((s.exact?s.left:0)+s.future)+" + "+label.apply("Limits")+" "+seconds((s.exact?0:s.left)+s.limits),
            label.apply("Input")+" "+label.apply(blocked?"Blocked":"Free")+" | "+label.apply("Update")+" "+String.format(Locale.ROOT,"%.1fs",age)};
    }
    static Map<String,Object> progress(){
        var s=snapshot;if(s==null)return Map.of();
        var out=new LinkedHashMap<String,Object>();out.put("schema",1);out.put("scenario",s.id);out.put("phase",s.phase);out.put("step",s.step);out.put("total",s.total);out.put("command",s.command);out.put("next",s.next);out.put("elapsed_seconds",s.elapsed);out.put("left_seconds",s.left);out.put("exact_timer",s.exact);out.put("future_timed_seconds",s.future);out.put("future_limit_seconds",s.limits);out.put("input_blocked",ScenarioHost.suppressInput());out.put("monotonic_ns",s.at);return out;
    }
    /** A transient reader lock may defer progress, never fail the scenario artifact writer. */
    static boolean saveProgress(java.nio.file.Path directory,Map<String,Object> progress){
        if(progress.isEmpty())return true;
        try{
            var temporary=directory.resolve("progress.tmp");java.nio.file.Files.writeString(temporary,ScenarioJson.write(progress));
            java.nio.file.Files.move(temporary,directory.resolve("progress.json"),java.nio.file.StandardCopyOption.REPLACE_EXISTING);
            return true;
        }catch(java.io.IOException transientFailure){return false;}
    }
    static void loadingHeartbeat(){
        var s=snapshot;long now=System.nanoTime();if(s==null||!s.phase.equals("loading")||now-s.at<500_000_000L)return;
        double age=(now-s.at)/1e9;snapshot=new Snapshot(now,s.id,s.phase,s.step,s.total,s.command,s.next,s.elapsed+age,Math.max(0,s.left-age),false,s.future,s.limits);
    }
    public static void draw(){
        var s=snapshot;if(s==null||!ScenarioHost.requested())return;
        long now=System.nanoTime();if(now>=textAt){textAt=now+250_000_000L;text=lines(s,now,ScenarioHost.suppressInput(),key->Translator.getText("UI_MS_Scenario_"+key));}
        var font=UIFont.NewSmall;int h=TextManager.instance.getFontHeight(font)+1,w=0;
        for(var line:text)w=Math.max(w,TextManager.instance.MeasureStringX(font,line));
        int x=8,y=165;zombie.core.SpriteRenderer.instance.renderi(null,x,y,w+12,h*text.length+8,0,0,0,.75f,null);
        for(int i=0;i<text.length;i++)TextManager.instance.DrawString(font,x+6,y+4+i*h,text[i],.85,.9,.85,1);
    }
    @Patch(className="zombie.core.Core",methodName="EndFrameUI",warmUp=true)
    public static class NativeUi {
        @Patch.OnEnter public static void enter(){ScenarioStatus.draw();}
    }
    private ScenarioStatus(){}
}
