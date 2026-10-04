package me.pavel.modstudio;

import me.zed_0xff.zombie_buddy.Exposer;
import me.zed_0xff.zombie_buddy.Patch;
import org.joml.Vector3f;
import zombie.characters.IsoPlayer;
import zombie.core.physics.CarController;
import zombie.core.physics.WorldSimulation;
import zombie.iso.IsoWorld;
import zombie.vehicles.BaseVehicle;

/** Disposable scenario car. Only logical controls change after native spawn/entry. */
@Exposer.LuaClass(name="ModStudioDriving")
public final class ScenarioDriving {
    private static BaseVehicle vehicle;
    private static Route route;
    private static long nextSample,progressAt;
    private static double bestRemaining;
    private static final Vector3f forward=new Vector3f();
    private static volatile Intervals presents;
    /** Bounded 0.1 ms histogram; the last bucket is overflow, maximum stays exact. */
    static final class Intervals {
        final long[] bins=new long[10001];long count,total,max,previous;
        synchronized void add(long nanos){if(nanos<=0)return;count++;total+=nanos;max=Math.max(max,nanos);bins[(int)Math.min(bins.length-1,nanos/100_000)]++;}
        synchronized void present(long now){if(previous!=0)add(now-previous);previous=now;}
        synchronized double percentile(double p){long wanted=(long)Math.ceil(count*p),n=0;for(int i=0;i<bins.length;i++){n+=bins[i];if(n>=wanted)return i==bins.length-1?max/1e6:(i+1)*.1;}return 0;}
        synchronized String report(){return "frames="+count+" seconds="+total/1e9+" fps="+(total==0?0:count*1e9/total)+" p95ms="+percentile(.95)+" p99ms="+percentile(.99)+" maxms="+max/1e6;}
    }
    record Control(float steering,boolean gas,boolean brake,double remaining,double lateral) {}
    static final class Route {
        final double x,y,dx,dy,length,speed;
        Route(double x,double y,double tx,double ty,double speed){
            this.x=x;this.y=y;length=Math.hypot(tx-x,ty-y);
            if(!Double.isFinite(length)||length<8||length>1000||!Double.isFinite(speed)||speed<5||speed>100)
                throw new IllegalArgumentException("Drive requires 8..1000 tiles and 5..100 km/h");
            dx=(tx-x)/length;dy=(ty-y)/length;this.speed=speed;
        }
        Control control(double px,double py,double fx,double fy,double kmh){
            double along=(px-x)*dx+(py-y)*dy,lateral=(px-x)*dy-(py-y)*dx,remaining=length-along;
            double aim=Math.min(length,Math.max(0,along)+12),ax=x+dx*aim-px,ay=y+dy*aim-py;
            double angle=Math.atan2(fx*ay-fy*ax,fx*ax+fy*ay);
            float steering=(float)Math.clamp(angle*1.6,-.65,.65);
            double target=Math.min(speed,Math.sqrt(Math.max(0,remaining-2)*6)*3.6);
            boolean brake=remaining<=3||Math.abs(kmh)>target+3;
            return new Control(steering,!brake&&kmh<target-1,brake,remaining,Math.abs(lateral));
        }
    }
    private static void guard(){
        if(!ScenarioHost.requested()||!ScenarioHost.suppressInput()||!zombie.core.Core.getInstance().isNoSave())
            throw new IllegalStateException("Driving requires a disposable scenario world");
    }
    public static void spawn(String scriptName,double heading){spawnConfigured(scriptName,heading,true,false);}
    /** Same native owned car, optionally parked with headlights and the player on foot. */
    public static boolean spawnConfigured(String scriptName,double heading,boolean enter,boolean headlights){
        guard();var p=IsoPlayer.getInstance();
        if(vehicle!=null||p==null||p.getVehicle()!=null)throw new IllegalStateException("Spawn requires a player on foot and no scenario car");
        if(!Double.isFinite(heading)||heading< -180||heading>180)throw new IllegalArgumentException("Invalid heading");
        var script=zombie.scripting.ScriptManager.instance.getVehicle(scriptName);
        if(script==null||script.getPassengerCount()<1)throw new IllegalArgumentException("Unknown passenger vehicle");
        var square=p.getSquare();if(square==null||!square.TreatAsSolidFloor())throw new IllegalStateException("Spawn requires a native floor");
        WorldSimulation.instance.create();var v=new BaseVehicle(IsoWorld.instance.currentCell);boolean added=false;
        try {
            v.setScriptName(scriptName);v.setScript();v.setX(p.getX());v.setY(p.getY());v.setZ(p.getZ());
            double yaw=Math.toRadians(heading);v.setDir(zombie.iso.IsoDirections.fromAngle(new zombie.iso.Vector2((float)Math.cos(yaw),(float)Math.sin(yaw))));
            v.savedRot.rotationY((float)(Math.PI/2-yaw));v.jniTransform.setRotation(v.savedRot);
            v.setSquare(square);v.chunk=square.getChunk();v.chunk.vehicles.add(v);added=true;v.addToWorld();
            v.setGeneralPartCondition(1.3f,10f);v.repair();v.setLocked(false);v.setAlarmed(false);v.setHotwired(true);
            if(enter){
                if(!v.enter(0,p))throw new IllegalStateException("Driver seat unavailable");
                p.setRunning(false);p.setSprinting(false);p.setIsAiming(false);p.setBlockMovement(false);
                p.clearVariable("bEnteringVehicle");p.clearVariable("bExitingVehicle");
                v.setCharacterPosition(p,0,"inside");v.transmitCharacterPosition(0,"inside");v.playPassengerAnim(0,"idle");
            }
            zombie.vehicles.VehiclesDB2.instance.addVehicle(v);v.engineDoRunning();v.setHeadlightsOn(headlights);
            if(v.getHeadlightsOn()!=headlights||headlights&&!v.hasHeadlights())throw new IllegalStateException("Native vehicle headlights unavailable");
            if((p.getVehicle()==v)!=enter)throw new IllegalStateException("Native vehicle entry state differs");
            vehicle=v;v.getController().getClientControls().brake=true;
            if(enter)zombie.Lua.LuaEventManager.triggerEvent("OnEnterVehicle",p);
            ScenarioHost.event("native-car","script="+scriptName+" heading="+heading+" enter="+enter+" headlights="+v.getHeadlightsOn()+" x="+v.getX()+" y="+v.getY()+" grid="+zombie.iso.IsoChunkMap.chunkGridWidth);
            return true;
        } catch(RuntimeException|Error e){if(added){if(p.getVehicle()==v)v.exit(p);v.permanentlyRemove();}vehicle=null;throw e;}
    }
    public static void drive(double x,double y,double kmh){
        guard();checkDriver();route=new Route(vehicle.getX(),vehicle.getY(),x,y,kmh);
        bestRemaining=route.length;progressAt=System.nanoTime();nextSample=0;
        presents=new Intervals();
        ScenarioHost.event("native-drive-start","x="+x+" y="+y+" kmh="+kmh+" distance="+route.length);
    }
    private static void checkDriver(){
        if(vehicle==null||vehicle.getDriver()!=IsoPlayer.getInstance())throw new IllegalStateException("Scenario driver unavailable");
    }
    public static boolean poll(){
        guard();checkDriver();if(route==null)throw new IllegalStateException("No active drive");
        long now=System.nanoTime();vehicle.getForwardVector(forward);
        var c=route.control(vehicle.getX(),vehicle.getY(),forward.x,forward.z,vehicle.getCurrentSpeedKmHour());
        if(c.lateral>6)throw new IllegalStateException("Vehicle left the route: "+c.lateral+" tiles");
        if(c.remaining<bestRemaining-.5){bestRemaining=c.remaining;progressAt=now;}
        if(now>=nextSample){nextSample=now+250_000_000L;sample(c);}
        if(c.remaining<=4&&Math.abs(vehicle.getCurrentSpeedKmHour())<2){sample(c);stop();return true;}
        if(now-progressAt>8_000_000_000L)throw new IllegalStateException("Vehicle stuck with "+c.remaining+" tiles remaining");
        return false;
    }
    private static void sample(Control c){
        var v=vehicle;double lead=128;
        for(int side=-1;side<=1;side++)for(int d=0;d<=128;d+=2){
            int cx=(int)Math.floor((v.getX()+route.dx*d-route.dy*side*4)/8),cy=(int)Math.floor((v.getY()+route.dy*d+route.dx*side*4)/8);
            var chunk=IsoWorld.instance.currentCell.getChunk(cx,cy);
            if(chunk==null||!chunk.loaded){lead=Math.min(lead,d);break;}
        }
        ScenarioHost.event("native-drive-sample","x="+v.getX()+" y="+v.getY()+" kmh="+v.getCurrentSpeedKmHour()+" remaining="+c.remaining+" lateral="+c.lateral+" nativeAhead="+lead);
    }
    public static void stop(){route=null;var frames=presents;presents=null;if(frames!=null)ScenarioHost.event("native-drive-frames",frames.report());if(vehicle!=null){vehicle.getController().getClientControls().reset();vehicle.getController().getClientControls().brake=true;}}
    public static void close(){stop();var v=vehicle;vehicle=null;if(v!=null){var p=IsoPlayer.getInstance();if(p!=null&&p.getVehicle()==v)v.exit(p);v.permanentlyRemove();}}
    public static void controls(CarController controller){
        if(vehicle==null||controller.vehicleObject!=vehicle||!ScenarioHost.suppressInput())return;
        var out=controller.getClientControls();long forceBrake=out.forceBrake;out.reset();out.forceBrake=forceBrake;out.brake=true;
        if(route==null||vehicle.getDriver()!=IsoPlayer.getInstance())return;
        vehicle.getForwardVector(forward);var c=route.control(vehicle.getX(),vehicle.getY(),forward.x,forward.z,vehicle.getCurrentSpeedKmHour());
        out.steering=c.steering;out.forward=c.gas;out.brake=c.brake;
        long dt=System.currentTimeMillis()-out.forceBrake;if(out.forceBrake!=0&&dt>0&&dt<1000){out.forward=false;out.brake=true;}
    }
    @Patch(className="zombie.core.physics.CarController",methodName="updateControls",warmUp=true,strictMatch=true)
    public static class NativeControls {
        @Patch.OnExit public static void exit(@Patch.This CarController controller){ScenarioDriving.controls(controller);}
    }
    public static void present(){var frames=presents;if(frames!=null)frames.present(System.nanoTime());}
    @Patch(className="org.lwjglx.opengl.Display",methodName="swapBuffers",warmUp=true,strictMatch=true)
    public static class Present {
        @Patch.OnExit public static void exit(){ScenarioDriving.present();}
    }
    private ScenarioDriving(){}
}
