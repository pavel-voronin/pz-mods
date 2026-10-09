package me.pavel.modstudio;

import java.lang.invoke.*;
import java.util.*;
import gnu.trove.list.array.TFloatArrayList;
import gnu.trove.set.hash.TIntHashSet;
import jassimp.AiAnimation;
import jassimp.AiNodeAnim;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.skinnedmodel.model.jassimp.ImportedSkeleton;
import zombie.debug.DebugType;

/** Preserve native frame/channel order while replacing repeated linear membership scans. */
public final class AnimationFrameCollector {
    private static final VarHandle BONES;
    static {
        try {BONES=MethodHandles.privateLookupIn(ImportedSkeleton.class,MethodHandles.lookup()).findVarHandle(ImportedSkeleton.class,"boneIndices",HashMap.class);}
        catch(ReflectiveOperationException error){throw new ExceptionInInitializerError(error);}
    }
    private static int key(float value){return value==0?0:Float.floatToRawIntBits(value);}
    private static void append(TFloatArrayList list,TIntHashSet seen,float value){
        // Native float == merges signed zeros and never considers NaN equal.
        if(Float.isNaN(value) || seen.add(key(value)))list.add(value);
    }
    public static void collect(Map<String,Integer> bones,AiAnimation animation,TFloatArrayList[] times,ArrayList<ArrayList<AiNodeAnim>> channels){
        TIntHashSet[] seen=new TIntHashSet[times.length];
        for(AiNodeAnim channel:animation.getChannels()){
            Integer index=bones.get(channel.getNodeName());
            if(index==null){DebugType.General.error("Could not find bone index for node name: \"%s\"",channel.getNodeName());continue;}
            ArrayList<AiNodeAnim> boneChannels=channels.get(index);
            if(boneChannels==null){boneChannels=new ArrayList<>();channels.set(index,boneChannels);}
            boneChannels.add(channel);
            TFloatArrayList list=times[index];if(list==null)times[index]=list=new TFloatArrayList();
            TIntHashSet set=seen[index];
            if(set==null){seen[index]=set=new TIntHashSet();for(int i=0;i<list.size();i++){float value=list.get(i);if(!Float.isNaN(value))set.add(key(value));}}
            for(int i=0;i<channel.getNumPosKeys();i++)append(list,set,(float)channel.getPosKeyTime(i));
            for(int i=0;i<channel.getNumRotKeys();i++)append(list,set,(float)channel.getRotKeyTime(i));
            for(int i=0;i<channel.getNumScaleKeys();i++)append(list,set,(float)channel.getScaleKeyTime(i));
        }
    }
    @SuppressWarnings("unchecked")
    public static void collect(ImportedSkeleton skeleton,AiAnimation animation,TFloatArrayList[] times,ArrayList<ArrayList<AiNodeAnim>> channels){collect((Map<String,Integer>)BONES.get(skeleton),animation,times,channels);}
    @Patch(className="zombie.core.skinnedmodel.model.jassimp.ImportedSkeleton",methodName="collectBoneFrames",warmUp=true,strictMatch=true)
    public static final class CollectPatch {
        @Patch.OnEnter(skipOn=true) public static boolean enter(@Patch.This ImportedSkeleton skeleton,@Patch.Argument(0) AiAnimation animation,@Patch.Argument(1) TFloatArrayList[] times,@Patch.Argument(2) ArrayList<ArrayList<AiNodeAnim>> channels){
            if(!StartupPreparationPolicy.enabled("animations"))return false;
            AnimationFrameCollector.collect(skeleton,animation,times,channels);return true;
        }
    }
}
