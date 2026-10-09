package me.pavel.modstudio;

import java.lang.invoke.*;
import java.util.*;
import jassimp.*;
import org.lwjgl.util.vector.Quaternion;
import org.lwjgl.util.vector.Vector3f;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.skinnedmodel.model.jassimp.ImportedSkeleton;

/** Clip-local key indices; original interpolation arithmetic and wrap behavior are retained. */
public final class AnimationKeyLookup {
    private static final VarHandle WRAPPER,END;
    static {
        try {
            var lookup=MethodHandles.privateLookupIn(ImportedSkeleton.class,MethodHandles.lookup());
            WRAPPER=lookup.findVarHandle(ImportedSkeleton.class,"wrapper",AiBuiltInWrapperProvider.class);
            END=lookup.findVarHandle(ImportedSkeleton.class,"end",Quaternion.class);
        }catch(ReflectiveOperationException error){throw new ExceptionInInitializerError(error);}
    }
    public static final class Scope implements AutoCloseable {
        private final Scope previous;
        final IdentityHashMap<AiNodeAnim,double[][]> indices=new IdentityHashMap<>();
        private boolean closed;
        Scope(){previous=current.get();current.set(this);}
        @Override public void close(){if(closed)return;closed=true;if(previous==null)current.remove();else current.set(previous);indices.clear();}
    }
    private static final ThreadLocal<Scope> current=new ThreadLocal<>();
    public static Scope open(){return new Scope();}
    private static double[] times(AiNodeAnim node,int kind){
        Scope scope=current.get();if(scope==null)return null;
        double[][] channels=scope.indices.computeIfAbsent(node,ignored->new double[3][]);
        if(channels[kind]!=null)return channels[kind];
        int count=kind==0?node.getNumPosKeys():kind==1?node.getNumRotKeys():node.getNumScaleKeys();double[] result=new double[count];
        boolean sorted=true;for(int i=0;i<count;i++){
            result[i]=kind==0?node.getPosKeyTime(i):kind==1?node.getRotKeyTime(i):node.getScaleKeyTime(i);
            if(Double.isNaN(result[i]) || (i>0 && result[i]<result[i-1]))sorted=false;
        }
        // A one-element NaN sentinel remembers unusual source data and requests native fallback.
        channels[kind]=sorted?result:new double[]{Double.NaN};return channels[kind];
    }
    static int frame(double[] times,float time){
        if(Float.isNaN(time))return times.length-1;
        int low=1,high=times.length;
        while(low<high){int middle=(low+high)>>>1;if((double)time<times[middle])high=middle;else low=middle+1;}
        return low-1;
    }
    private static boolean unsupported(double[] times){return times==null || (times.length==1 && Double.isNaN(times[0]));}
    public static Vector3f position(AiNodeAnim node,float time,double duration){
        double[] keys=times(node,0);if(unsupported(keys))return null;
        Vector3f result=new Vector3f();if(keys.length==0)return result;
        int index=frame(keys,time),next=(index+1)%keys.length;
        float t1=(float)keys[index],t2=(float)keys[next],diff=t2-t1;
        if(diff<0)diff=(float)((double)diff+duration);
        if(diff>0){
            float r=t2-t1,s=time-t1;
            float x1=node.getPosKeyX(index),x2=node.getPosKeyX(next),x=x1+(s/=r)*(x2-x1);
            float y1=node.getPosKeyY(index),y2=node.getPosKeyY(next),y=y1+s*(y2-y1);
            float z1=node.getPosKeyZ(index),z2=node.getPosKeyZ(next),z=z1+s*(z2-z1);
            result.set(x,y,z);
        }else result.set(node.getPosKeyX(index),node.getPosKeyY(index),node.getPosKeyZ(index));
        return result;
    }
    public static Vector3f scale(AiNodeAnim node,float time){
        double[] keys=times(node,2);if(unsupported(keys))return null;
        Vector3f result=new Vector3f(1,1,1);if(keys.length==0)return result;
        int index=frame(keys,time);result.set(node.getScaleKeyX(index),node.getScaleKeyY(index),node.getScaleKeyZ(index));return result;
    }
    public static Quaternion rotation(ImportedSkeleton skeleton,AiNodeAnim node,float time,double duration){
        double[] keys=times(node,1);if(unsupported(keys))return null;
        Quaternion result=new Quaternion();if(keys.length==0)return result;
        int index=frame(keys,time),next=(index+1)%keys.length;
        float t1=(float)keys[index],t2=(float)keys[next],diff=t2-t1;
        if(diff<0)diff=(float)((double)diff+duration);
        if(diff>0){
            float factor=(time-t1)/diff;
            AiBuiltInWrapperProvider wrapper=(AiBuiltInWrapperProvider)WRAPPER.get(skeleton);
            AiQuaternion start=node.getRotKeyQuaternion(index,wrapper),finish=node.getRotKeyQuaternion(next,wrapper);
            double cos=start.getX()*finish.getX()+start.getY()*finish.getY()+start.getZ()*finish.getZ()+start.getW()*finish.getW();
            Quaternion end=(Quaternion)END.get(skeleton);end.set(finish.getX(),finish.getY(),finish.getZ(),finish.getW());
            if(cos<0){cos*=-1.;end.setX(-end.getX());end.setY(-end.getY());end.setZ(-end.getZ());end.setW(-end.getW());}
            double a,b;
            if(1.-cos>1.e-4){double omega=Math.acos(cos),sin=Math.sin(omega);a=Math.sin((1.-(double)factor)*omega)/sin;b=Math.sin((double)factor*omega)/sin;}
            else {a=1.-(double)factor;b=factor;}
            result.set((float)(a*(double)start.getX()+b*(double)end.getX()),(float)(a*(double)start.getY()+b*(double)end.getY()),(float)(a*(double)start.getZ()+b*(double)end.getZ()),(float)(a*(double)start.getW()+b*(double)end.getW()));
        }else result.set(node.getRotKeyX(index),node.getRotKeyY(index),node.getRotKeyZ(index),node.getRotKeyW(index));
        return result;
    }
    @Patch(className="zombie.core.skinnedmodel.model.jassimp.ImportedSkeleton",methodName="processAnimation",warmUp=true,strictMatch=true)
    public static final class ScopePatch {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) jassimp.AiAnimation animation,@Patch.Local("scope") Scope scope){if(StartupPreparationPolicy.enabled("animations")){scope=AnimationKeyLookup.open();StartupPreparationPolicy.record(StartupPreparationPolicy.ANIMATIONS);}}
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Local("scope") Scope scope){if(scope!=null)scope.close();}
    }
    @Patch(className="zombie.core.skinnedmodel.model.jassimp.ImportedSkeleton",methodName="GetKeyFramePosition",warmUp=true,strictMatch=true)
    public static final class PositionPatch {
        @Patch.OnEnter(skipOn=true) public static boolean enter(@Patch.Argument(0) AiNodeAnim node,@Patch.Argument(1) float time,@Patch.Argument(2) double duration,@Patch.Local("result") Vector3f result){result=AnimationKeyLookup.position(node,time,duration);return result!=null;}
        @Patch.OnExit public static void exit(@Patch.Local("result") Vector3f result,@Patch.Return(readOnly=false) Vector3f returned){if(result!=null)returned=result;}
    }
    @Patch(className="zombie.core.skinnedmodel.model.jassimp.ImportedSkeleton",methodName="GetKeyFrameScale",warmUp=true,strictMatch=true)
    public static final class ScalePatch {
        @Patch.OnEnter(skipOn=true) public static boolean enter(@Patch.Argument(0) AiNodeAnim node,@Patch.Argument(1) float time,@Patch.Local("result") Vector3f result){result=AnimationKeyLookup.scale(node,time);return result!=null;}
        @Patch.OnExit public static void exit(@Patch.Local("result") Vector3f result,@Patch.Return(readOnly=false) Vector3f returned){if(result!=null)returned=result;}
    }
    @Patch(className="zombie.core.skinnedmodel.model.jassimp.ImportedSkeleton",methodName="GetKeyFrameRotation",warmUp=true,strictMatch=true)
    public static final class RotationPatch {
        @Patch.OnEnter(skipOn=true) public static boolean enter(@Patch.This ImportedSkeleton skeleton,@Patch.Argument(0) AiNodeAnim node,@Patch.Argument(1) float time,@Patch.Argument(2) double duration,@Patch.Local("result") Quaternion result){result=AnimationKeyLookup.rotation(skeleton,node,time,duration);return result!=null;}
        @Patch.OnExit public static void exit(@Patch.Local("result") Quaternion result,@Patch.Return(readOnly=false) Quaternion returned){if(result!=null)returned=result;}
    }
}
