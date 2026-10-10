package me.pavel.modstudio;

import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import me.zed_0xff.zombie_buddy.Exposer;
import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.vm.KahluaTable;

/** External debug sessions with compact progress; no dependency on a tested mod. */
@Exposer.LuaClass(name="ModStudioScenario")
public final class ScenarioHost {
    private static Map<String,Object> definition;
    private static String json;
    private static volatile String error="";
    private static Path output;
    private static ScenarioPersistence.Profile persistentProfile;
    private static final List<String> nativePackages=new ArrayList<>();
    private static boolean loading;
    private static volatile boolean claimed;
    private static volatile boolean manual;
    private static volatile boolean closed,finishing;
    private static final ArrayBlockingQueue<Map<String,Object>> events=new ArrayBlockingQueue<>(4096);
    private static volatile String status="running",reason="";
    public static double clock(){return System.nanoTime()*1e-9;}
    /** A missing upper square is absence only after the owning vanilla chunk loaded. */
    public static boolean loadedEmptyCell(double x,double y,double z){
        if(!Double.isFinite(x+y+z)||x!=Math.rint(x)||y!=Math.rint(y)||z!=Math.rint(z)||x<0||y<0||x>100000||y>100000||z< -32||z>31)return false;
        var cell=zombie.iso.IsoWorld.instance.currentCell;if(cell==null)return false;
        int gx=(int)x,gy=(int)y,gz=(int)z;return loadedEmptyCell(cell.getChunkForGridSquare(gx,gy,gz),cell.getGridSquare(gx,gy,gz),gx,gy,gz);
    }
    static boolean loadedEmptyCell(zombie.iso.IsoChunk chunk,zombie.iso.IsoGridSquare square,int x,int y,int z){
        if(chunk==null||!chunk.loaded||square!=null||chunk.wx!=Math.floorDiv(x,8)||chunk.wy!=Math.floorDiv(y,8))return false;
        return z<chunk.getMinLevel()||z>chunk.getMaxLevel()||chunk.getGridSquare(Math.floorMod(x,8),Math.floorMod(y,8),z)==null;
    }
    private static long abortPoll;
    public static String error(){
        long now=System.nanoTime();
        if(claimed&&multiplayer()&&output!=null&&now>=abortPoll){
            abortPoll=now+250_000_000L;
            if(Files.isRegularFile(output.getParent().resolve("abort.txt")))error="External MP suite stopped after peer failure";
        }
        return error;
    }
    public static boolean closed(){return closed;}
    public static boolean persistent(){return persistentProfile!=null;}
    public static boolean readOnlyReplay(){return persistent()&&definition!=null&&definition.get("persistence") instanceof Map<?,?> p&&Boolean.TRUE.equals(p.get("readOnly"));}
    public static String persistentMode(){return persistent()?persistentProfile.mode():"";}
    public static String savedWorld(){return persistent()?persistentProfile.world():"";}
    public static boolean disposable(){return zombie.core.Core.getInstance().isNoSave()||persistent()&&ScenarioPersistence.current(persistentProfile,Path.of(zombie.ZomboidFileSystem.instance.getCacheDir()),Path.of(zombie.ZomboidFileSystem.instance.getCurrentSaveDir()));}
    public static int frameLimit(){return zombie.core.PerformanceSettings.getLockFPS();}
    public static boolean frameUncapped(){return zombie.core.PerformanceSettings.instance.isFramerateUncapped();}
    public static void setFrameUncapped(boolean value){
        if(!requested()||!claimed||!disposable())throw new IllegalStateException("Frame rate requires an owned scenario world");
        zombie.core.PerformanceSettings.instance.setFramerateUncapped(value);
    }
    public static boolean frameSync(){return zombie.core.Core.getInstance().getOptionVSync();}
    public static void setFrameSync(boolean value){
        if(!requested()||!claimed||!disposable())throw new IllegalStateException("VSync requires an owned scenario world");
        zombie.core.Core.getInstance().setOptionVSync(value);
    }
    public static void setFrameLimit(int value){
        if(!requested()||!claimed||!disposable())throw new IllegalStateException("Frame rate requires an owned scenario world");
        if(value<24||value>244)throw new IllegalArgumentException("Frame rate must be 24..244");
        zombie.core.PerformanceSettings.setLockFPS(value);
    }
    public static void saveNativeWorld()throws java.io.IOException {
        if(!requested()||!claimed||!persistent()||zombie.core.Core.getInstance().isNoSave()||!disposable()||zombie.network.GameClient.client||zombie.network.GameServer.server)throw new IllegalStateException("Save requires the owned persistent single-player scenario");
        zombie.GameWindow.save(false);if(zombie.savefile.PlayerDB.isAllow())zombie.savefile.PlayerDB.getInstance().saveLocalPlayersForce();zombie.iso.ChunkSaveWorker.instance.SaveNow();
        ScenarioPersistence.saved(persistentProfile,zombie.core.Core.gameSaveWorld,Path.of(zombie.ZomboidFileSystem.instance.getCurrentSaveDir()));event("native-save",zombie.core.Core.gameSaveWorld);
    }
    public static boolean requested(){return !System.getProperty("modstudio.scenario","").isEmpty();}
    // A claimed external session always exits its process, including on failure.
    // Keep the filter through cleanup so held keys cannot act during shutdown.
    public static boolean suppressInput(){return claimed&&!manual;}
    private static volatile boolean screenshotDone;
    private static volatile String screenshotError="";
    private static int loadingScreenshots;
    private static long loadingScreenshotAt;
    /** Native front-buffer capture, usable with or without a renderer provider. */
    public static void screenshot(String name){
        if(!requested()||!claimed||!disposable())throw new IllegalStateException("Screenshot requires an owned disposable scenario world");
        capture(name);
    }
    private static void capture(String name){
        if(name==null||!name.matches("[a-z0-9_-]{1,60}"))throw new IllegalArgumentException("Invalid screenshot name");
        screenshotDone=false;screenshotError="";
        zombie.core.opengl.RenderThread.invokeOnRenderContext(()->{
            int read=org.lwjgl.opengl.GL11.glGetInteger(org.lwjgl.opengl.GL30.GL_READ_FRAMEBUFFER_BINDING),buffer=org.lwjgl.opengl.GL11.glGetInteger(org.lwjgl.opengl.GL11.GL_READ_BUFFER),pack=org.lwjgl.opengl.GL11.glGetInteger(org.lwjgl.opengl.GL11.GL_PACK_ALIGNMENT);
            try{
                org.lwjgl.opengl.GL30.glBindFramebuffer(org.lwjgl.opengl.GL30.GL_READ_FRAMEBUFFER,0);
                String temporary="mod-studio-"+UUID.randomUUID()+".png";
                zombie.core.Core.getInstance().TakeFullScreenshot(temporary);
                Path destination=output.resolve("screenshots").resolve(name+".png");Files.createDirectories(destination.getParent());
                Files.move(Path.of(zombie.ZomboidFileSystem.instance.getScreenshotDir()).resolve(temporary),destination,StandardCopyOption.REPLACE_EXISTING);
            }catch(Exception e){screenshotError=e.toString();}
            finally{org.lwjgl.opengl.GL30.glBindFramebuffer(org.lwjgl.opengl.GL30.GL_READ_FRAMEBUFFER,read);org.lwjgl.opengl.GL11.glReadBuffer(buffer);org.lwjgl.opengl.GL11.glPixelStorei(org.lwjgl.opengl.GL11.GL_PACK_ALIGNMENT,pack);screenshotDone=true;}
        });
    }
    public static boolean screenshotReady(){if(!screenshotError.isEmpty())throw new IllegalStateException(screenshotError);return screenshotDone;}
    public static String expectDisplay(int width,int height){
        if(!requested()||!claimed||!disposable())throw new IllegalStateException("Display assertion requires an owned disposable scenario");
        int w=org.lwjglx.opengl.Display.getWidth(),h=org.lwjglx.opengl.Display.getHeight();
        int fw=org.lwjglx.opengl.Display.getFramebufferWidth(),fh=org.lwjglx.opengl.Display.getFramebufferHeight();
        if(w!=width||h!=height||fw!=width||fh!=height)return "Display mismatch: window="+w+"x"+h+" framebuffer="+fw+"x"+fh+" expected="+width+"x"+height;
        event("display-verified",width+"x"+height+" window and framebuffer");
        return "";
    }
    public static int clearVehicles(double x0,double y0,double x1,double y1){
        if(!requested()||!claimed||!zombie.core.Core.getInstance().isNoSave())throw new IllegalStateException("Vehicle clearing requires a disposable scenario world");
        if(!(x0>=0&&y0>=0&&x1<=100000&&y1<=100000&&x1>x0&&y1>y0&&x1-x0<=128&&y1-y0<=128))throw new IllegalArgumentException("Invalid vehicle clearing bounds");
        var player=zombie.characters.IsoPlayer.getInstance();
        var cell=zombie.iso.IsoWorld.instance.currentCell;
        if(player==null||cell==null)throw new IllegalStateException("World is not ready");
        var selected=new ArrayList<zombie.vehicles.BaseVehicle>();
        // 42.21 exposes a Set, which has no indexed get() in Lua.
        for(var vehicle:cell.getVehicles())if(vehicle.getX()>=x0&&vehicle.getX()<=x1&&vehicle.getY()>=y0&&vehicle.getY()<=y1){
            if(vehicle==player.getVehicle())throw new IllegalStateException("Cannot remove the player's vehicle");
            selected.add(vehicle);
        }
        for(var vehicle:selected)vehicle.permanentlyRemove();
        return selected.size();
    }
    private static zombie.characters.IsoPlayer human;
    private static zombie.inventory.InventoryItem humanTorch;
    public static void spawnHuman(double dx,double dy){
        if(!requested()||!claimed||!zombie.core.Core.getInstance().isNoSave())throw new IllegalStateException("Human spawn requires a disposable scenario world");
        if(!Double.isFinite(dx)||!Double.isFinite(dy)||Math.abs(dx)>8||Math.abs(dy)>8||Math.hypot(dx,dy)<1)throw new IllegalArgumentException("Human offset must be 1..8 tiles per axis");
        var player=zombie.characters.IsoPlayer.getInstance();var cell=zombie.iso.IsoWorld.instance.currentCell;
        if(human!=null||player==null||cell==null)throw new IllegalStateException("Human already exists or world is unavailable");
        int x=(int)Math.floor(player.getX()+dx),y=(int)Math.floor(player.getY()+dy),z=(int)player.getZ();
        var square=cell.getGridSquare(x,y,z);
        if(square==null||!square.TreatAsSolidFloor()||!square.isFree(false))throw new IllegalStateException("Human spawn requires a free loaded floor");
        try {
            human=new zombie.characters.IsoPlayer(cell,zombie.characters.SurvivorFactory.CreateSurvivor(),x,y,z);
            human.remote=true;human.setNpc(true);human.setGodMod(true);human.setInvisible(false);human.setBlockMovement(true);
            for(String type:List.of("Base.Shirt_Denim","Base.Trousers_Denim","Base.Shoes_TrainerTINT")){
                var item=human.getInventory().AddItem(type);
                if(!(item instanceof zombie.inventory.types.Clothing clothing))throw new IllegalStateException("Missing human clothing: "+type);
                human.setWornItem(clothing.getBodyLocation(),clothing);
            }
            human.getWornItems().getItemVisuals(human.getItemVisuals());
            var axe=human.getInventory().AddItem("Base.Axe");
            if(axe==null)throw new IllegalStateException("Missing human attachment");
            human.setPrimaryHandItem(axe);human.setDirectionAngle(90);
            human.setCurrent(square);human.setSceneCulled(false);
            if(zombie.characters.IsoPlayer.getInstance()!=player)throw new IllegalStateException("Human replaced local player");
            event("native-human","spawn x="+human.getX()+" y="+human.getY()+" z="+human.getZ()+" npc="+human.isNpc());
        } catch(RuntimeException|Error e){clearHuman();throw e;}
    }
    public static void humanLight(boolean on,double heading){
        if(!requested()||!claimed||!zombie.core.Core.getInstance().isNoSave()||human==null)throw new IllegalStateException("Human light requires a disposable scenario human");
        if(!Double.isFinite(heading)||heading< -180||heading>180)throw new IllegalArgumentException("Invalid human light heading");
        if(humanTorch==null){
            humanTorch=human.getInventory().AddItem("Base.HandTorch");
            if(!(humanTorch instanceof zombie.inventory.types.DrainableComboItem battery))throw new IllegalStateException("Native hand torch unavailable");
            battery.setUsedDelta(1);human.setPrimaryHandItem(humanTorch);
        }
        human.setDirectionAngle((float)heading);humanTorch.setActivated(on);
        var active=human.getActiveLightItems(new ArrayList<>());
        if(active.contains(humanTorch)!=on)throw new IllegalStateException("Native human light activation mismatch");
        event("native-human-light","on="+on+" heading="+heading+" remote="+human.remote+" activeItems="+active.size()+" range="+humanTorch.getLightDistance()+" strength="+humanTorch.getLightStrength());
    }
    public static void updateHuman(){
        // A local visual stand-in has no network packets. Preserve native remote-player
        // update/animation without expiring it or assigning the active local camera.
        if(human!=null)human.setTimeSinceLastNetData(0);
    }
    public static boolean humanReady(){
        if(human==null)throw new IllegalStateException("No scenario human");
        var model=human.getModel();
        return human.getCurrentSquare()!=null&&model!=null&&model.animPlayer!=null&&model.animPlayer.isReady();
    }
    public static void clearHuman(){
        var actor=human;if(actor==null)return;human=null;humanTorch=null;
        try {actor.setSceneCulled(true);}finally {try {actor.removeFromWorld();}finally {actor.removeFromSquare();}}
        event("native-human","removed");
    }
    public static KahluaTable context() {
        if(!requested()||!zombie.core.Core.debug||zombie.network.GameServer.server||zombie.network.GameClient.client&&!multiplayer())return null;
        if(!error.isEmpty())return null;
        try {
            if(definition==null){
                Path path=Path.of(System.getProperty("modstudio.scenario"));
                if(Files.size(path)>262144)throw new IllegalArgumentException("Scenario exceeds 256 KiB");
                json=Files.readString(path);definition=ScenarioJson.parse(json);validate(definition);
                output=Path.of(System.getProperty("modstudio.scenario.output"));
                persistentProfile=ScenarioPersistence.open(definition,output,Path.of(zombie.ZomboidFileSystem.instance.getCacheDir()),System.getProperty("modstudio.scenario.profile",""),System.getProperty("modstudio.scenario.profile.token",""));
                if(persistent())for(String name:System.getProperties().stringPropertyNames())if(name.startsWith("modstudio.scenario.")&&name.endsWith(".jarSha256")){
                    String prefix=name.substring(0,name.length()-".jarSha256".length()),id=prefix.substring("modstudio.scenario.".length());
                    var loaded=zombie.gameStates.ChooseGameInfo.getModDetails(id);
                    if(loaded==null||!ScenarioPersistence.packageMatches(Path.of(loaded.getVersionDir()),Path.of(System.getProperty(prefix+".jarPath","")),System.getProperty(name)))throw new java.io.IOException("Loaded native package differs from scenario build: "+id);
                    nativePackages.add(id+" versionDir="+loaded.getVersionDir()+" sha256="+System.getProperty(name));
                }
            }
            return (KahluaTable)lua(Map.of("definition",definition,"json",json,"output",output.toString()));
        }catch(Exception e){error="Invalid scenario: "+e;return null;}
    }
    public static String mcpSession(){
        String id=System.getProperty("modstudio.scenario.mcp","");
        return requested()&&!multiplayer()&&id.matches("[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}")?id:"";
    }
    public static double mcpSeconds(){
        double seconds=Double.parseDouble(System.getProperty("modstudio.scenario.mcp.seconds","1800"));
        if(!Double.isFinite(seconds)||seconds<60||seconds>7200)throw new IllegalArgumentException("Invalid MCP lifetime");
        return seconds;
    }
    private static Path mcpPath(String name){
        if(mcpSession().isEmpty()||!claimed||output==null||!zombie.core.Core.getInstance().isNoSave())
            throw new IllegalStateException("MCP requires an explicitly enabled disposable scenario");
        if(!Set.of("request.json","reply.json","status.json","history.jsonl").contains(name))throw new IllegalArgumentException("Invalid MCP file");
        return output.resolve("mcp").resolve(name);
    }
    public static KahluaTable mcpRead(){
        Path file=mcpPath("request.json");if(!Files.exists(file))return null;
        try {if(Files.size(file)>65536)throw new IllegalArgumentException("MCP request exceeds 64 KiB");
            return (KahluaTable)lua(ScenarioJson.parse(Files.readString(file)));
        }catch(Exception e){throw new IllegalStateException("MCP request read",e);}
    }
    public static void mcpWrite(String name,String value){
        Path file=mcpPath(name);
        try {
            // Parse before publishing, so incomplete or malformed data cannot escape.
            ScenarioJson.parse(value);Files.createDirectories(file.getParent());
            if(name.equals("history.jsonl")){Files.writeString(file,value+"\n",StandardOpenOption.CREATE,StandardOpenOption.APPEND);return;}
            Path temp=file.resolveSibling(name+".tmp");Files.writeString(temp,value);
            Files.move(temp,file,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
        }catch(Exception e){throw new IllegalStateException("MCP response write",e);}
    }
    public static boolean multiplayer(){return Boolean.getBoolean("modstudio.scenario.multiplayer")&&requested();}
    public static boolean resume(){return multiplayer()&&claimed&&!finishing&&zombie.network.GameClient.client;}
    public static void focus(){
        if(!claimed||!multiplayer())throw new IllegalStateException("Focus requires an external MP scenario");
        zombie.core.opengl.RenderThread.invokeOnRenderContext(()->org.lwjgl.glfw.GLFW.glfwFocusWindow(org.lwjglx.opengl.Display.getWindow()));
    }
    public static void signal(String name){
        networkGuard(name);
        try {
            var player=zombie.characters.IsoPlayer.getInstance();
            if(player==null)throw new IllegalStateException("Local network player unavailable");
            Path target=output.getParent().resolve(name+"-"+ScenarioJson.string(ScenarioJson.object(definition.get("multiplayer")),"username"));
            if(Files.exists(target))throw new IllegalArgumentException("MP barrier name already used");
            Path temp=target.resolveSibling(target.getFileName()+".tmp");
            Files.writeString(temp,ScenarioJson.write(Map.of("x",player.getX(),"y",player.getY(),"z",player.getZ(),"onlineID",player.getOnlineID())));
            Files.move(temp,target,StandardCopyOption.ATOMIC_MOVE);
        }
        catch(Exception e){throw new IllegalStateException("MP barrier write",e);}
    }
    public static boolean signaled(String name,String user){
        networkGuard(name);
        if(!user.matches("[A-Za-z0-9_]{1,32}"))throw new IllegalArgumentException("Invalid peer");
        return Files.isRegularFile(output.getParent().resolve(name+"-"+user));
    }
    public static KahluaTable checkpoint(String name,String user){
        networkGuard(name);
        if(user==null||!user.matches("[A-Za-z0-9_]{1,32}"))throw new IllegalArgumentException("Invalid peer");
        Path file=output.getParent().resolve(name+"-"+user);
        if(!Files.isRegularFile(file))return null;
        try {
            if(Files.size(file)>4096)throw new IllegalArgumentException("Oversized MP checkpoint");
            return (KahluaTable)lua(ScenarioJson.parse(Files.readString(file)));
        }catch(Exception e){throw new IllegalStateException("MP checkpoint read",e);}
    }
    private static void networkGuard(String name){
        if(!multiplayer()||!claimed||!zombie.network.GameClient.client||!zombie.core.Core.getInstance().isNoSave())throw new IllegalStateException("MP command requires an isolated external client");
        if(name==null||!name.matches("[a-z0-9_-]{1,60}"))throw new IllegalArgumentException("Invalid barrier");
    }
    static void validate(Map<String,Object> root)throws Exception {
        ScenarioPersistence.mode(root);
        if(number(root,"schema",0,1,1)!=1)throw new IllegalArgumentException("Expected schema 1");
        if(!ScenarioJson.string(root,"id").matches("[a-z0-9_-]{1,80}"))throw new IllegalArgumentException("Invalid id");
        var spawn=ScenarioJson.object(root.get("spawn"));number(spawn,"x",-1,0,100000);number(spawn,"y",-1,0,100000);number(spawn,"z",0,-32,31);
        if(root.containsKey("manual")&&!(root.get("manual") instanceof Boolean))throw new IllegalArgumentException("manual must be boolean");
        if(root.containsKey("loadingScreenshots")&&!(root.get("loadingScreenshots") instanceof Boolean))throw new IllegalArgumentException("loadingScreenshots must be boolean");
        number(root,"loadingTimeout",240,1,3600);
        number(root,"prepareTimeout",120,1,3600);
        if(Boolean.TRUE.equals(root.get("manual"))&&number(root,"repeats",1,1,20)!=1)throw new IllegalArgumentException("Manual setup cannot repeat");
        if(root.containsKey("multiplayer")){
            var mp=ScenarioJson.object(root.get("multiplayer"));
            if(!multiplayer()||!"127.0.0.1".equals(ScenarioJson.string(mp,"host")))throw new IllegalArgumentException("MP scenarios require explicit loopback launch");
            double port=number(mp,"port",0,1024,65534);if(port!=Math.rint(port))throw new IllegalArgumentException("Nonintegral MP port");
            for(String key:List.of("username","peer"))if(!ScenarioJson.string(mp,key).matches("[A-Za-z0-9_]{1,32}"))throw new IllegalArgumentException("Invalid MP "+key);
            if(number(root,"repeats",1,1,20)!=1||Boolean.TRUE.equals(root.get("manual")))throw new IllegalArgumentException("MP sessions cannot repeat or hand off");
        }
        double repeats=number(root,"repeats",1,1,20);if(repeats!=Math.rint(repeats))throw new IllegalArgumentException("Nonintegral repeats");
        if(!(root.get("steps") instanceof List<?> steps)||steps.isEmpty()||steps.size()>512)throw new IllegalArgumentException("Expected 1..512 steps");
        double budget=0;
        for(Object value:steps){var step=ScenarioJson.object(value);
            if(!ScenarioJson.string(step,"command").matches("[a-z][a-z0-9_]*\\.[a-z][a-zA-Z0-9_]*"))throw new IllegalArgumentException("Expected owner.command");
            double seconds=number(step,"seconds",0,0,600);budget+=number(step,"timeout",Math.max(30,seconds+5),.1,900);
        }
        if(budget*repeats>7200)throw new IllegalArgumentException("Scenario timeout budget exceeds two hours");
    }
    private static double number(Map<String,Object> m,String key,double fallback,double min,double max){
        Object v=m.get(key);double n=v==null?fallback:v instanceof Number x?x.doubleValue():Double.NaN;
        if(!Double.isFinite(n)||n<min||n>max)throw new IllegalArgumentException("Invalid "+key);return n;
    }
    private static Object lua(Object value){
        if(value instanceof Map<?,?> m){var t=se.krka.kahlua.j2se.J2SEPlatform.getInstance().newTable();m.forEach((k,v)->t.rawset(k,lua(v)));return t;}
        if(value instanceof List<?> a){var t=se.krka.kahlua.j2se.J2SEPlatform.getInstance().newTable();for(int i=0;i<a.size();i++)t.rawset((double)i+1,lua(a.get(i)));return t;}
        return value instanceof Number n?n.doubleValue():value;
    }
    public static synchronized boolean claim(){
        if(claimed||context()==null)return false;claimed=loading=true;
        for(String detail:nativePackages)event("native-package",detail);
        Thread writer=new Thread(ScenarioHost::write,"ModStudio-scenario-artifacts");writer.setDaemon(true);writer.start();return true;
    }
    public static int lightYardSources(){
        if(!claimed||!zombie.core.Core.getInstance().isNoSave())throw new IllegalStateException("Yard check requires disposable world");
        var cell=zombie.iso.IsoWorld.instance.currentCell;
        return cell.getLamppostPositions().size()+cell.roomLights.size();
    }
    public static void handoff(){
        if(!claimed||definition==null||!Boolean.TRUE.equals(definition.get("manual"))||!zombie.core.Core.getInstance().isNoSave())
            throw new IllegalStateException("Manual handoff requires an explicit disposable manual scenario");
        manual=true;finish("interactive","World prepared; control handed to player");
    }
    public static void worldReady(){loading=false;}
    public static void progress(String phase,int step,int total,String command,String next,double elapsed,double left,boolean exact,double future,double limits){
        if(claimed&&definition!=null)ScenarioStatus.update(String.valueOf(definition.get("id")),phase,step,total,command,next,elapsed,left,exact,future,limits);
    }
    public static void event(String kind,String detail){
        if(!claimed||finishing)return;
        if(!events.offer(Map.of("monotonic_ns",System.nanoTime(),"kind",kind,"detail",detail)))error="Scenario event queue overflow";
    }
    public static void finish(String result,String detail){if(finishing)return;status=result;reason=detail;finishing=true;loading=false;}
    private static void write(){
        try {
            Files.createDirectories(output);
            result("running","");
            long progressAt=0;
            try(var writer=Files.newBufferedWriter(output.resolve("events.jsonl"))){
                while(!finishing||!events.isEmpty()){
                    long now=System.nanoTime();if(now>=progressAt){progressAt=now+500_000_000L;ScenarioStatus.saveProgress(output,ScenarioStatus.progress());}
                    var event=events.poll(100,TimeUnit.MILLISECONDS);if(event!=null){writer.write(ScenarioJson.write(event));writer.flush();}
                }
            }
            result(error.isEmpty()?status:"failed",error.isEmpty()?reason:error);
        }catch(Exception e){error="Scenario artifact writer: "+e;try{result("failed",error);}catch(Exception ignored){}}
        finally{closed=true;}
    }
    private static void result(String state,String detail)throws Exception {
        var result=new LinkedHashMap<String,Object>();result.put("schema",1);result.put("scenario",definition.get("id"));result.put("status",state);result.put("reason",detail);
        result.put("utc",java.time.Instant.now().toString());result.put("output",output.toString());
        Path temp=output.resolve("scenario-result.tmp");Files.writeString(temp,ScenarioJson.write(result));
        Files.move(temp,output.resolve("scenario-result.json"),StandardCopyOption.REPLACE_EXISTING);
    }
    public static void autoContinue(zombie.gameStates.GameLoadingState state){
        ScenarioStatus.loadingHeartbeat();
        var env=zombie.Lua.LuaManager.env;
        boolean shortcut=env!=null && env.rawget("ModStudio") instanceof KahluaTable studio
            && studio.rawget("Launch") instanceof KahluaTable launch
            && Boolean.TRUE.equals(launch.rawget("autoContinueLoading"));
        // The native world's onStart callback can clear 'loading' while the
        // GameLoadingState still waits for additional preparation or input.
        if(requested()&&claimed&&!finishing&&definition!=null&&(zombie.core.Core.getInstance().isNoSave()||persistent())
                &&Boolean.TRUE.equals(definition.get("loadingScreenshots"))&&loadingScreenshots<16
                &&zombie.gameStates.GameLoadingState.loader!=null&&!zombie.gameStates.GameLoadingState.loader.isAlive()
                &&System.nanoTime()>=loadingScreenshotAt){
            loadingScreenshotAt=System.nanoTime()+750_000_000L;
            String name="loading-"+ ++loadingScreenshots;
            screenshot(name);
            if(screenshotError.isEmpty())events.offer(Map.of("monotonic_ns",System.nanoTime(),"kind","loading-screenshot","detail",name));
            else {error="Loading screenshot failed: "+screenshotError;loadingScreenshots=16;}
        }
        if(!loading && !shortcut)return;
        // Saved players need ordinary native loading before OnGameStart enables NoSave.
        if(loading)zombie.core.Core.getInstance().setNoSave(!persistent());
        try{var field=zombie.gameStates.GameLoadingState.class.getDeclaredField("forceDone");field.setAccessible(true);field.setBoolean(state,true);}
        catch(Exception e){error="Native loading gate: "+e;}
    }
    @Patch(className="zombie.gameStates.GameLoadingState",methodName="update",warmUp=true,strictMatch=true)
    public static class LoadingGate {
        @Patch.OnEnter public static void enter(@Patch.This zombie.gameStates.GameLoadingState state){ScenarioHost.autoContinue(state);}
    }
}
