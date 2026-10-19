package me.pavel.modstudio;

public final class ScenarioStatusRegression {
    static void check(boolean ok,String message){if(!ok)throw new AssertionError(message);}
    public static void main(String[] args)throws Exception{
        var measured=new ScenarioStatus.Snapshot(10_000_000_000L,"city-route","measure",9,16,"pz3d.measure city", "native.drive",12,48,true,5,150);
        var stored=ScenarioStatus.class.getDeclaredField("snapshot");stored.setAccessible(true);stored.set(null,measured);
        System.setProperty("modstudio.scenario","hidden-ui-regression");
        boolean visible=zombie.ui.UIManager.visibleAllUi;
        try{zombie.ui.UIManager.visibleAllUi=false;ScenarioStatus.draw();}
        finally{zombie.ui.UIManager.visibleAllUi=visible;System.clearProperty("modstudio.scenario");stored.set(null,null);}
        var core=zombie.core.Core.getInstance();
        boolean fbo=zombie.ui.UIManager.useUiFbo,render=core.uiRenderThisFrame;
        var cachedText=ScenarioStatus.class.getDeclaredField("textAt");cachedText.setAccessible(true);
        long textAt=cachedText.getLong(null);
        try{
            zombie.ui.UIManager.visibleAllUi=true;zombie.ui.UIManager.useUiFbo=true;core.uiRenderThisFrame=false;
            stored.set(null,measured);System.setProperty("modstudio.scenario","cached-ui-regression");
            for(int frame=0;frame<120;frame++)ScenarioStatus.NativeUi.enter();
            check(cachedText.getLong(null)==textAt&&stored.get(null)==measured,"cached UI frames retain the panel without drawing a second copy or refreshing its text");
        }finally{
            zombie.ui.UIManager.visibleAllUi=visible;zombie.ui.UIManager.useUiFbo=fbo;core.uiRenderThisFrame=render;
            System.clearProperty("modstudio.scenario");stored.set(null,null);
        }
        var lines=ScenarioStatus.lines(measured,12_000_000_000L,true,s->s.toLowerCase());
        check(lines.length==4&&lines[1].contains("left 46s"),"exact remaining timer advances");
        check(lines[2].contains("native.drive")&&lines[2].contains("timed 53s + limits 150s"),"following step and known durations separate from upper limits");
        check(lines[3].contains("blocked")&&lines[3].contains("2.0s"),"actual input and update freshness");
        check(ScenarioStatus.lines(measured,16_000_000_000L,false,s->s.toLowerCase())[0].contains("waiting"),"missing updates are visible");
        var loading=new ScenarioStatus.Snapshot(0,"city","loading",0,16,"loading","pz3d.camera",3,120,false,60,180);
        check(ScenarioStatus.lines(loading,1_000_000_000L,true,s->s.toLowerCase())[1].contains("limit 119s"),"loading deadline is not an invented ETA");
        check(ScenarioStatus.clean("a\nb").equals("a?b")&&ScenarioStatus.clean("x".repeat(100)).length()==72,"bounded ASCII status");
        var directory=java.nio.file.Files.createTempDirectory("modstudio-progress-race");
        var blocked=directory.resolve("progress.json");java.nio.file.Files.createDirectory(blocked);
        var blocker=blocked.resolve("lock");java.nio.file.Files.writeString(blocker,"blocked replacement");
        var progress=java.util.Map.<String,Object>of("schema",1,"step",9);
        check(!ScenarioStatus.saveProgress(directory,progress),"failed progress replacement defers without a fatal scenario error");
        java.nio.file.Files.delete(blocker);java.nio.file.Files.delete(blocked);
        check(ScenarioStatus.saveProgress(directory,progress)&&((Number)ScenarioJson.parse(java.nio.file.Files.readString(blocked)).get("step")).intValue()==9,"the next bounded heartbeat recovers the latest progress");
        java.nio.file.Files.delete(blocked);java.nio.file.Files.delete(directory);
        System.out.println("PASS: compact scenario progress, exact and unknown timers, future steps, input and stale heartbeat.");
    }
}
