package me.pavel.modstudio;

import java.lang.invoke.*;
import java.lang.reflect.Array;
import java.util.*;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.skinnedmodel.animation.AnimationClip;
import zombie.core.skinnedmodel.animation.Keyframe;

/** Group native keyframe identities once instead of scanning every frame for each bone. */
public final class ClipFrameIndex {
    private static final VarHandle FRAMES,GROUPS;
    private static final MethodHandle ELEMENT;
    static {
        try {
            var lookup=MethodHandles.privateLookupIn(AnimationClip.class,MethodHandles.lookup());
            Class<?> element=Class.forName("zombie.core.skinnedmodel.animation.AnimationClip$KeyframeByBoneIndexElement");
            FRAMES=lookup.findVarHandle(AnimationClip.class,"keyframeArray",Keyframe[].class);
            GROUPS=lookup.findVarHandle(AnimationClip.class,"keyFramesByBoneIndex",Array.newInstance(element,0).getClass());
            ELEMENT=MethodHandles.privateLookupIn(element,MethodHandles.lookup()).findConstructor(element,MethodType.methodType(void.class,List.class)).asType(MethodType.methodType(Object.class,List.class));
        }catch(ReflectiveOperationException error){throw new ExceptionInInitializerError(error);}
    }
    public static boolean apply(AnimationClip clip){
        Keyframe[] frames=(Keyframe[])FRAMES.get(clip);Object groups=GROUPS.get(clip);
        if(frames==null || groups==null || Array.getLength(groups)!=60)return false;
        int[] sizes=new int[60];for(Keyframe frame:frames){if(frame==null)return false;if(frame.bone>=0 && frame.bone<60)sizes[frame.bone]++;}
        List<List<Keyframe>> lists=new ArrayList<>(60);for(int count:sizes)lists.add(new ArrayList<>(count));
        for(Keyframe frame:frames)if(frame.bone>=0 && frame.bone<60)lists.get(frame.bone).add(frame);
        for(int bone=0;bone<60;bone++){
            List<Keyframe> list=lists.get(bone);if(!clip.keepLastFrame && list.size()>1)list.removeLast();
            try {Array.set(groups,bone,(Object)ELEMENT.invokeExact(list));}
            catch(RuntimeException|Error failure){throw failure;}
            catch(Throwable failure){throw new IllegalStateException(failure);}
        }
        return true;
    }
    @Patch(className="zombie.core.skinnedmodel.animation.AnimationClip",methodName="recalculateKeyframesByBoneIndex",warmUp=true,strictMatch=true)
    public static final class IndexPatch {
        @Patch.OnEnter(skipOn=true) public static boolean enter(@Patch.This AnimationClip clip){return StartupPreparationPolicy.enabled("animations") && ClipFrameIndex.apply(clip);}
    }
}
