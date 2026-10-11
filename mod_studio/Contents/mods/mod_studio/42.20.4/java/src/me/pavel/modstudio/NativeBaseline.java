package me.pavel.modstudio;

import java.nio.file.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import me.zed_0xff.zombie_buddy.Exposer;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.IsoPlayer;
import zombie.iso.*;
import zombie.core.*;

/** Native loader experiment; enabled only by the external isolated runner. */
@Exposer.LuaClass(name="ModStudioNativeBaseline")
public final class NativeBaseline {
    public static final boolean enabled=Boolean.getBoolean("modstudio.nativeBaseline")&&ScenarioHost.requested();
    public static volatile Window window;
    public static final ConcurrentHashMap<IsoChunk,Stage> stages=new ConcurrentHashMap<>();
    static final ArrayBlockingQueue<String> records=new ArrayBlockingQueue<>(32768);
    static volatile long dropped;
    static volatile String writerError="";
    static Thread writer;
    static boolean oldNoclip;
    static zombie.core.textures.Texture worldMap,cityMap,ruralMap;
    static int viewX,viewY;static double playerX,playerY;
    static final int VIEW=31,STEP=32;
    static final Set<Long> visited=new HashSet<>();
    static final ArrayDeque<double[]> trail=new ArrayDeque<>();
    static final Histogram hudCost=new Histogram();
    static long sampleTime;static double sampleX,sampleY;
    static String routeLabel="";
    static String statusLine="Native baseline | preparing protected player and maps";
    static long contentChunks,contentObjects,contentSquares,contentUpper;
    public static String[] hud=new String[0];
    public static volatile byte[] gridHud=new byte[0];
    public static final class Stage {final int x,y;public final long request=System.nanoTime();volatile long worker,done,attach,objects;Stage(IsoChunk c){this(c.wx,c.wy);}public Stage(int x,int y){this.x=x;this.y=y;}}
    static final class Histogram {
        final long[] bins=new long[20001];long n,total,max,over16,over33,over100;
        synchronized void add(long ns){if(ns<=0)return;n++;total+=ns;max=Math.max(max,ns);if(ns>16_666_667)over16++;if(ns>33_333_333)over33++;if(ns>100_000_000)over100++;bins[(int)Math.min(bins.length-1,ns/100_000)]++;}
        synchronized double q(double fraction){if(n==0)return 0;long wanted=(long)Math.ceil(n*fraction),c=0;for(int i=0;i<bins.length;i++){c+=bins[i];if(c>=wanted)return i==bins.length-1?max/1e6:(i+1)*.1;}return 0;}
        synchronized String json(){return "{\"count\":"+n+",\"mean\":"+(n==0?0:total/1e6/n)+",\"p50\":"+q(.5)+",\"p95\":"+q(.95)+",\"p99\":"+q(.99)+",\"max\":"+max/1e6+",\"above16\":"+over16+",\"above33\":"+over33+",\"above100\":"+over100+"}";}
    }
    public static final class Window {
        public final String name;final double x,y,dx,dy,seconds;public final boolean detailed,showHud;
        final long start=System.nanoTime();final Histogram updateIntervals=new Histogram(),updateCost=new Histogram(),present=new Histogram(),probeCost=new Histogram();
        long previousUpdate,previousPresent,updateStart,nextSample,lateSince,lateCount,maxLate;double minLead=Double.POSITIVE_INFINITY,maxDeficit,distance,lastX,lastY,maxJump;long maxHeap;int maxQueue,minReadyAhead=Integer.MAX_VALUE,maxMissingAhead;double maxAge;
        Window(String name,double x,double y,double dx,double dy,double seconds,boolean detailed,boolean showHud){this.name=name;this.x=x;this.y=y;this.dx=dx;this.dy=dy;this.seconds=seconds;this.detailed=detailed;this.showHud=showHud;lastX=x;lastY=y;}
    }
    public static void guard(){if(!enabled||!ScenarioHost.suppressInput()||!Core.getInstance().isNoSave())throw new IllegalStateException("Baseline requires owned native-only NoSave scenario");}
    public static boolean requested(){return enabled;}
    public static boolean open(){
        guard();if(writer!=null)return true;
        worldMap=zombie.core.textures.Texture.getSharedTexture("media/textures/modstudio-native-baseline-world.png");cityMap=zombie.core.textures.Texture.getSharedTexture("media/textures/modstudio-native-baseline-city.png");ruralMap=zombie.core.textures.Texture.getSharedTexture("media/textures/modstudio-native-baseline-rural.png");
        if(worldMap==null||cityMap==null||ruralMap==null)throw new IllegalStateException("Prepared native maps missing from mod media");
        if(!worldMap.isReady()||!cityMap.isReady()||!ruralMap.isReady())return false;
        if(org.lwjglx.opengl.Display.getFramebufferWidth()==0||org.lwjglx.opengl.Display.getFramebufferHeight()==0)return false;
        var p=IsoPlayer.getInstance();if(!p.isGodMod()||!p.isInvisible())throw new IllegalStateException("Baseline player must be invisible and invulnerable");oldNoclip=p.isNoClip();p.setNoClip(true,true);if(!p.isNoClip())throw new IllegalStateException("Native noclip unavailable");
        ScenarioHost.event("native-baseline-display","framebuffer="+org.lwjglx.opengl.Display.getFramebufferWidth()+"x"+org.lwjglx.opengl.Display.getFramebufferHeight()+" cap="+ScenarioHost.frameLimit()+" uncapped="+ScenarioHost.frameUncapped()+" vsync="+ScenarioHost.frameSync());
        Path output=Path.of(System.getProperty("modstudio.scenario.output"));
        writer=new Thread(()->{try(var out=Files.newBufferedWriter(output.resolve("native-events.csv"))){out.write("kind,ns,window,x,y,a,b,c,d,e,f,readyAhead,requiredAhead,missingAhead\n");while(true){String line=records.poll(1,TimeUnit.SECONDS);if("CLOSE".equals(line))break;if(line!=null){out.write(line);out.newLine();}}}catch(Exception e){writerError=e.toString();}},"native-baseline-writer");writer.setDaemon(true);writer.start();
        ScenarioHost.event("native-baseline","grid="+IsoChunkMap.chunkGridWidth+" screen="+Core.width+"x"+Core.height+" noSave="+Core.getInstance().isNoSave()+" population="+zombie.SandboxOptions.instance.zombies.getValue()+" invisible="+p.isInvisible()+" god="+p.isGodMod()+" health="+p.getHealth());
        playerX=p.getX();playerY=p.getY();viewX=Math.floorDiv(p.getXi(),8)-VIEW/2;viewY=Math.floorDiv(p.getYi(),8)-VIEW/2;hud=new String[]{"Native chunk baseline | preparing static map display"};return true;
    }
    public static void emit(String line){if(!records.offer(line))dropped++;}
    public static boolean start(String name,double dx,double dy,double seconds,boolean detailed,boolean showHud){
        guard();if(writer==null||!IsoPlayer.getInstance().isNoClip())throw new IllegalStateException("Baseline not prepared");if(window!=null)throw new IllegalStateException("Window already active");if(!name.matches("[a-z0-9_-]{1,60}")||Math.abs(Math.hypot(dx,dy)-1)>.001||seconds<1||seconds>600)throw new IllegalArgumentException("Invalid native route window");hud=new String[0];gridHud=new byte[0];
        sampleTime=0;contentChunks=contentObjects=contentSquares=contentUpper=0;hudCost.n=hudCost.total=hudCost.max=hudCost.over16=hudCost.over33=hudCost.over100=0;Arrays.fill(hudCost.bins,0);trail.clear();routeLabel=name.startsWith("rural")?"Forest / countryside":"Louisville / urban";var p=IsoPlayer.getInstance();window=new Window(name,p.getX(),p.getY(),dx,dy,seconds,detailed,showHud);
        ScenarioHost.event("native-baseline-start",name+" x="+p.getX()+" y="+p.getY()+" dx="+dx+" dy="+dy+" seconds="+seconds+" detailed="+detailed+" hud="+showHud);return true;
    }
    public static boolean poll(){guard();var w=window;if(w==null)return true;double elapsed=(System.nanoTime()-w.start)/1e9;statusLine=String.format(Locale.ROOT,"Native baseline | %s | %.0f s left | %s",w.name,Math.max(0,w.seconds-elapsed),w.showHud?"map and telemetry":"control: map and detailed HUD disabled");if(elapsed<w.seconds)return false;stop();return true;}
    public static boolean stop(){
        var w=window;if(w==null)return true;window=null;statusLine="Native baseline | between measurement windows";long end=System.nanoTime();if(w.lateSince!=0)w.maxLate=Math.max(w.maxLate,end-w.lateSince);
        var p=IsoPlayer.getInstance();double elapsed=(end-w.start)/1e9,along=(p.getX()-w.x)*w.dx+(p.getY()-w.y)*w.dy;
        String json="{\"name\":\""+w.name+"\",\"grid\":"+IsoChunkMap.chunkGridWidth+",\"seconds\":"+elapsed+",\"kmh\":"+along/elapsed*3.6+",\"distance\":"+along+",\"minLead\":"+(Double.isFinite(w.minLead)?w.minLead:-1)+",\"lateCount\":"+w.lateCount+",\"maxLateMs\":"+w.maxLate/1e6+",\"maxDeficit\":"+w.maxDeficit+",\"maxJump\":"+w.maxJump+",\"maxQueue\":"+w.maxQueue+",\"maxAgeMs\":"+w.maxAge+",\"maxHeap\":"+w.maxHeap+",\"dropped\":"+dropped+",\"detailed\":"+w.detailed+",\"hud\":"+w.showHud+",\"updateIntervals\":"+w.updateIntervals.json()+",\"updateCost\":"+w.updateCost.json()+",\"presents\":"+w.present.json()+",\"probeCost\":"+w.probeCost.json()+",\"hudCost\":"+hudCost.json()+",\"contentChunks\":"+contentChunks+",\"contentObjects\":"+contentObjects+",\"contentSquares\":"+contentSquares+",\"contentUpperSquares\":"+contentUpper+",\"startX\":"+w.x+",\"startY\":"+w.y+",\"endX\":"+p.getX()+",\"endY\":"+p.getY()+",\"health\":"+p.getHealth()+",\"invisible\":"+p.isInvisible()+",\"god\":"+p.isGodMod()+",\"dx\":"+w.dx+",\"dy\":"+w.dy+"}";
        json=json.substring(0,json.length()-1)+",\"minReadyAhead\":"+(w.minReadyAhead==Integer.MAX_VALUE?-1:w.minReadyAhead)+",\"maxMissingAhead\":"+w.maxMissingAhead+",\"attachedChunksPerSecond\":"+contentChunks/elapsed+"}";
        try{Files.writeString(Path.of(System.getProperty("modstudio.scenario.output"),"native-"+w.name+".json"),json);}catch(IOException e){throw new UncheckedIOException(e);}
        ScenarioHost.event("native-baseline-stop",json);if(w.updateCost.n==0||w.present.n==0)throw new IllegalStateException("Missing native update or presentation instrumentation");return true;
    }
    public static boolean close()throws InterruptedException {stop();var p=IsoPlayer.getInstance();if(p!=null)p.setNoClip(oldNoclip,true);if(writer!=null){records.put("CLOSE");writer.join(5000);if(writer.isAlive()||!writerError.isEmpty()||dropped!=0)throw new IllegalStateException("Baseline writer: "+writerError+" dropped="+dropped);writer=null;}return true;}
    public static void movement(IsoMovingObject object){
        var w=window;if(w==null||object!=IsoPlayer.getInstance())return;var p=IsoPlayer.getInstance();double distance=Math.min(w.seconds,(System.nanoTime()-w.start)/1e9)*(80.0/3.6),tx=w.x+w.dx*distance,ty=w.y+w.dy*distance;
        // Let native postupdate apply its one-tile cap, noclip, square ownership and fallback.
        p.setNextX((float)tx);p.setNextY((float)ty);
    }
    public static void beginUpdate(){var w=window;if(w==null)return;long now=System.nanoTime();w.updateStart=now;if(w.previousUpdate!=0)w.updateIntervals.add(now-w.previousUpdate);w.previousUpdate=now;}
    static boolean ready(int x,int y){var cell=IsoWorld.instance.currentCell;var square=cell.getGridSquare(x,y,0);if(square==null)return false;var chunk=square.getChunk();var stage=chunk==null?null:stages.get(chunk);return chunk!=null&&chunk.loaded&&cell.getChunk(Math.floorDiv(x,8),Math.floorDiv(y,8))==chunk&&stage!=null&&stage.attach!=0&&stage.objects!=0&&square.getObjects()!=null&&square.getFloor()!=null;}
    public static void endUpdate(){
        var w=window;if(w==null||w.updateStart==0)return;long now=System.nanoTime();long cost=now-w.updateStart;w.updateCost.add(cost);if(w.detailed&&cost>33_333_333)emit("slow-update,"+now+","+w.name+","+IsoPlayer.getInstance().getX()+","+IsoPlayer.getInstance().getY()+","+cost/1e6);long probe=now;var p=IsoPlayer.getInstance();double elapsed=(now-w.start)/1e9,along=(p.getX()-w.x)*w.dx+(p.getY()-w.y)*w.dy;
        w.maxDeficit=Math.max(w.maxDeficit,elapsed*80/3.6-along);w.maxJump=Math.max(w.maxJump,Math.hypot(p.getX()-w.lastX,p.getY()-w.lastY));w.lastX=p.getX();w.lastY=p.getY();
        double lead=-1;int queue=0;double age=0;
        if(w.detailed){
            lead=IsoChunkMap.chunkGridWidth*8;for(int side=-1;side<=1;side++)for(int d=0;d<=IsoChunkMap.chunkGridWidth*8;d++){int x=(int)Math.floor(p.getX()+w.dx*d-w.dy*side*4),y=(int)Math.floor(p.getY()+w.dy*d+w.dx*side*4);if(!ready(x,y)){lead=Math.min(lead,d);break;}}
            w.minLead=Math.min(w.minLead,lead);if(lead<8){if(w.lateSince==0){w.lateSince=now;w.lateCount++;}}else if(w.lateSince!=0){w.maxLate=Math.max(w.maxLate,now-w.lateSince);w.lateSince=0;}
        }
        if(now>=w.nextSample){w.nextSample=now+200_000_000L;for(var entry:stages.entrySet()){var s=entry.getValue();if(s.objects==0&&!entry.getKey().refs.isEmpty()){queue++;age=Math.max(age,(now-s.request)/1e6);}}w.maxQueue=Math.max(w.maxQueue,queue);w.maxAge=Math.max(w.maxAge,age);long heap=Runtime.getRuntime().totalMemory()-Runtime.getRuntime().freeMemory();w.maxHeap=Math.max(w.maxHeap,heap);
            int aheadRequired=0,aheadReady=0;var map=IsoWorld.instance.currentCell.chunkMap[0];
            if(w.detailed){for(int y=0;y<IsoChunkMap.chunkGridWidth;y++)for(int x=0;x<IsoChunkMap.chunkGridWidth;x++){int cx=map.getWorldXMin()+x,cy=map.getWorldYMin()+y;if(((cx*8+4)-p.getX())*w.dx+((cy*8+4)-p.getY())*w.dy<0)continue;aheadRequired++;var c=IsoWorld.instance.currentCell.getChunk(cx,cy);var st=c==null?null:stages.get(c);if(c!=null&&c.loaded&&st!=null&&st.attach!=0&&st.objects!=0)aheadReady++;}w.minReadyAhead=Math.min(w.minReadyAhead,aheadReady);w.maxMissingAhead=Math.max(w.maxMissingAhead,aheadRequired-aheadReady);}
            var sq=p.getCurrentSquare();boolean current=sq!=null&&sq.getX()==p.getXi()&&sq.getY()==p.getYi();
            emit("sample,"+now+","+w.name+","+p.getX()+","+p.getY()+","+elapsed+","+lead+","+(elapsed*80/3.6-along)+","+queue+","+age+","+current+","+aheadReady+","+aheadRequired+","+(aheadRequired-aheadReady));
            if(w.showHud){
                double speed=sampleTime==0?along/Math.max(.001,elapsed)*3.6:Math.hypot(p.getX()-sampleX,p.getY()-sampleY)/((now-sampleTime)/1e9)*3.6;
                sampleTime=now;sampleX=p.getX();sampleY=p.getY();playerX=p.getX();playerY=p.getY();viewX=Math.floorDiv(p.getXi(),8)-VIEW/2;viewY=Math.floorDiv(p.getYi(),8)-VIEW/2;
                trail.add(new double[]{playerX,playerY});while(trail.size()>180)trail.removeFirst();
                hud=new String[]{routeLabel+" | "+w.name+" | native grid "+IsoChunkMap.chunkGridWidth+" x "+IsoChunkMap.chunkGridWidth,
                    String.format(Locale.ROOT,"%.1f / %.0f s | speed %.1f km/h | average %.1f",elapsed,w.seconds,speed,along/Math.max(.001,elapsed)*3.6),
                    String.format(Locale.ROOT,"position %.1f, %.1f | diagonal %.3f, %.3f",playerX,playerY,w.dx,w.dy),
                    String.format(Locale.ROOT,"ready lead %.0f tiles / %.2f s | minimum %.0f",lead,lead/(80.0/3.6),w.minLead),
                    String.format(Locale.ROOT,"ahead ready %d / %d | missing %d | attached %.1f chunks/s",aheadReady,aheadRequired,aheadRequired-aheadReady,contentChunks/Math.max(.001,elapsed)),
                    String.format(Locale.ROOT,"queue %d | oldest %.1f ms | low-reserve episodes %d",queue,age,w.lateCount),
                    String.format(Locale.ROOT,"movement deficit %.2f tiles | maximum %.2f | square %s",elapsed*80/3.6-along,w.maxDeficit,current),
                    timing("update cost",w.updateCost),timing("present interval",w.present),timing("probe cost",w.probeCost),
                    String.format(Locale.ROOT,"heap %.0f MiB | chunks attached %d",heap/1048576.0,contentChunks),
                    String.format(Locale.ROOT,"objects / chunk %.0f | upper squares / chunk %.0f",contentObjects/(double)Math.max(1,contentChunks),contentUpper/(double)Math.max(1,contentChunks)),
                    "5 Hz map snapshot | north up | cell = 8 x 8 tiles",
                    "GREEN loaded / objects attached   YELLOW attach pending",
                    "ORANGE requested / worker   BLUE previously loaded / unloaded",
                    "WHITE player   CYAN recent path   RED overview route"};
                byte[] grid=new byte[VIEW*VIEW];var cell=IsoWorld.instance.currentCell;
                for(int y=0;y<VIEW;y++)for(int x=0;x<VIEW;x++){int cx=viewX+x,cy=viewY+y;long key=((long)cx<<32)^(cy&0xffffffffL);var c=cell.getChunk(cx,cy);var st=c==null?null:stages.get(c);int state=c==null?visited.contains(key)?4:0:!c.loaded?1:st==null||st.objects==0?2:3;if(state==3)visited.add(key);grid[y*VIEW+x]=(byte)state;}
                for(var entry:stages.entrySet()){var st=entry.getValue();int x=st.x-viewX,y=st.y-viewY;if(st.objects==0&&!entry.getKey().refs.isEmpty()&&x>=0&&y>=0&&x<VIEW&&y<VIEW)grid[y*VIEW+x]=(byte)(st.done==0?1:2);}
                gridHud=grid;
            }
        }w.probeCost.add(System.nanoTime()-probe);
    }
    public static void present(){var w=window;if(w==null)return;long now=System.nanoTime();synchronized(w.present){if(w.previousPresent!=0){long cost=now-w.previousPresent;w.present.add(cost);if(w.detailed&&cost>33_333_333)emit("slow-present,"+now+","+w.name+",0,0,"+cost/1e6);}w.previousPresent=now;}}
    public static void milestone(IsoChunk c,int phase){if(!enabled)return;var s=stages.computeIfAbsent(c,Stage::new);long now=System.nanoTime();switch(phase){case 1->s.worker=now;case 2->s.done=now;case 3->s.attach=now;case 4->{s.objects=now;if(window!=null&&window.detailed){long objects=0,squares=0,upper=0;for(var level:c.squares){if(level==null)continue;for(var sq:level){if(sq!=null){squares++;objects+=sq.getObjects().size();if(sq.getZ()>0)upper++;}}}contentChunks++;contentObjects+=objects;contentSquares+=squares;contentUpper+=upper;emit("content,"+now+","+window.name+","+c.wx+","+c.wy+","+objects+","+squares+","+upper);}}}var w=window;if(w!=null&&w.detailed)emit("chunk"+phase+","+now+","+w.name+","+c.wx+","+c.wy+","+(now-s.request)/1e6);}
    @Patch(className="zombie.iso.IsoChunkMap",methodName="CalcChunkWidth",warmUp=true,strictMatch=true)
    public static class Grid {@Patch.OnEnter public static void enter(){if(!enabled)return;int n=Integer.getInteger("modstudio.nativeGrid",0);var d=zombie.debug.DebugOptions.instance;d.worldChunkMap13x13.setValue(n==13);d.worldChunkMap11x11.setValue(n==11);d.worldChunkMap9x9.setValue(false);d.worldChunkMap7x7.setValue(false);d.worldChunkMap5x5.setValue(false);}}
    @Patch(className="zombie.iso.IsoWorld",methodName="render",warmUp=true,strictMatch=true)
    public static class WorldRender {@Patch.OnEnter(skipOn=true) public static boolean enter(){if(!enabled||IsoWorld.instance.currentCell==null)return false;var manager=zombie.iso.fboRenderChunk.FBORenderChunkManager.instance;manager.recycle();manager.startFrame();manager.submitCachesForFrame();zombie.iso.fboRenderChunk.FBORenderCorpses.getInstance().update();zombie.iso.fboRenderChunk.FBORenderItems.getInstance().update();zombie.iso.fboRenderChunk.FBORenderShadows.getInstance().clear();SpriteRenderer.instance.renderi(null,0,0,Core.getInstance().getOffscreenWidth(0),Core.getInstance().getOffscreenHeight(0),0,0,0,1,null);return true;}}
    @Patch(className="zombie.ui.UIManager",methodName="render",warmUp=true,strictMatch=true)
    public static class NativeUi {@Patch.OnEnter(skipOn=true) public static boolean enter(){return enabled&&IsoPlayer.getInstance()!=null;}}
    @Patch(className="zombie.gameStates.IngameState",methodName="renderframetext",warmUp=true,strictMatch=true)
    public static class FrameText {@Patch.OnEnter(skipOn=true) public static boolean enter(){return enabled;}}
    @Patch(className="zombie.iso.sprite.SkyBox",methodName="draw",warmUp=true,strictMatch=true)
    public static class Sky {@Patch.OnEnter(skipOn=true) public static boolean enter(){return enabled;}}
    @Patch(className="zombie.core.skinnedmodel.DeadBodyAtlas",methodName="renderUI",warmUp=true,strictMatch=true)
    public static class CorpsesUi {@Patch.OnEnter(skipOn=true) public static boolean enter(){return enabled;}}
    @Patch(className="zombie.core.skinnedmodel.model.WorldItemAtlas",methodName="renderUI",warmUp=true,strictMatch=true)
    public static class ItemsUi {@Patch.OnEnter(skipOn=true) public static boolean enter(){return enabled;}}
    @Patch(className="zombie.iso.IsoMovingObject",methodName="postupdate",warmUp=true,strictMatch=true)
    public static class Move {@Patch.OnEnter public static void enter(@Patch.This IsoMovingObject o){movement(o);}}
    @Patch(className="zombie.GameWindow",methodName="logic",warmUp=true,strictMatch=true)
    public static class Update {@Patch.OnEnter public static void enter(){beginUpdate();}@Patch.OnExit public static void exit(){endUpdate();}}
    @Patch(className="org.lwjglx.opengl.Display",methodName="swapBuffers",warmUp=true,strictMatch=true)
    public static class Present {@Patch.OnExit public static void exit(){present();}}
    @Patch(className="zombie.iso.WorldStreamer",methodName="addJob",warmUp=true,strictMatch=true)
    public static class Request {@Patch.OnEnter public static void enter(@Patch.Argument(0) IsoChunk c,@Patch.Argument(1) int x,@Patch.Argument(2) int y){if(enabled){var s=new Stage(x,y);stages.put(c,s);var w=window;if(w!=null&&w.detailed)emit("chunk0,"+s.request+","+w.name+","+x+","+y+",0");}}}
    @Patch(className="zombie.iso.WorldStreamer",methodName="DoChunkAlways",warmUp=true,strictMatch=true)
    public static class Worker {@Patch.OnEnter public static void enter(@Patch.Argument(0) IsoChunk c){milestone(c,1);}@Patch.OnExit public static void exit(@Patch.Argument(0) IsoChunk c){milestone(c,2);}}
    @Patch(className="zombie.iso.IsoChunkMap",methodName="setChunkDirect",warmUp=true,strictMatch=true)
    public static class Attach {@Patch.OnExit public static void exit(@Patch.Argument(0) IsoChunk c,@Patch.Return boolean ok){if(ok)milestone(c,3);}}
    @Patch(className="zombie.iso.IsoChunk",methodName="doLoadGridsquare",warmUp=true,strictMatch=true)
    public static class Objects {@Patch.OnExit public static void exit(@Patch.This IsoChunk c){milestone(c,4);}}
    @Patch(className="zombie.core.Core",methodName="EndFrameUI",warmUp=true)
    public static class Hud {@Patch.OnEnter public static void enter(){drawHud();}}
    static String timing(String label,Histogram h){return String.format(Locale.ROOT,"%s ms: p95 %.1f | p99 %.1f | max %.1f | >33 %d >100 %d",label,h.q(.95),h.q(.99),h.max/1e6,h.over33,h.over100);}
    public static void drawHud(){
        if(!enabled||IsoPlayer.getInstance()==null)return;long begin=System.nanoTime();var r=SpriteRenderer.instance;
        zombie.ui.TextManager.instance.DrawString(zombie.ui.UIFont.Medium,16,120,statusLine,1,1,1,1);
        if(hud.length==0){hudCost.add(System.nanoTime()-begin);return;}
        var texture=playerY<4096?cityMap:ruralMap;float ox=playerY<4096?9216:6144,oy=playerY<4096?0:4096;
        float u=(viewX*8-ox)/6144f,v=(viewY*8-oy)/6144f,extent=VIEW*8/6144f;
        r.render(texture,16,160,992,992,1,1,1,1,u,v,u+extent,v,u+extent,v+extent,u,v+extent);
        byte[] cells=gridHud;
        for(int i=0;i<cells.length;i++){int state=cells[i];if(state==0)continue;float red=state==3?.1f:state==4?.1f:.95f,green=state==3?.85f:state==2?.8f:state==4?.4f:.3f,blue=state==4?.95f:.1f;r.renderi(null,17+i%VIEW*STEP,161+i/VIEW*STEP,STEP-2,STEP-2,red,green,blue,.28f,null);}
        for(int i=0;i<=VIEW;i++){r.renderi(null,16+i*STEP,160,1,992,.2f,.2f,.2f,.5f,null);r.renderi(null,16,160+i*STEP,992,1,.2f,.2f,.2f,.5f,null);}
        for(var point:trail){int x=16+(int)((point[0]-viewX*8)*4),y=160+(int)((point[1]-viewY*8)*4);if(x>=16&&x<1008&&y>=160&&y<1152)r.renderi(null,x-2,y-2,4,4,0,.8f,1,1,null);}
        int px=16+(int)((playerX-viewX*8)*4),py=160+(int)((playerY-viewY*8)*4);r.renderi(null,px-5,py-5,11,11,0,0,0,1,null);r.renderi(null,px-3,py-3,7,7,1,1,1,1,null);
        r.renderi(worldMap,1040,520,640,640,1,1,1,1,null);
        var w=window;if(w!=null)r.renderline(null,1040+(int)(w.x/40),520+(int)(w.y/40),1040+(int)((w.x+w.dx*w.seconds*80/3.6)/40),520+(int)((w.y+w.dy*w.seconds*80/3.6)/40),1,0,0,1,2);
        r.renderi(null,1040+(int)(playerX/40)-3,520+(int)(playerY/40)-3,7,7,1,0,0,1,null);
        int y=16;for(int i=0;i<hud.length;i++){int x=i<3?16:1040;if(i==3)y=172;zombie.ui.TextManager.instance.DrawString(zombie.ui.UIFont.Medium,x,y,hud[i],1,1,1,1);y+=26;}
        hudCost.add(System.nanoTime()-begin);
    }
    private NativeBaseline(){}
}
