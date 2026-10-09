package me.pavel.modstudio;

import java.lang.reflect.*;
import java.util.*;
import me.zed_0xff.zombie_buddy.Patch;

/** Guard the installed Buddy's strict matcher, before bytecode advice emission. */
public final class StartupPatchSignatureTest {
    public static void main(String[] args)throws Exception {
        int checked=0;
        for(String owner:List.of("StartupPreparationPolicy","LuaPreparationHooks","LuaFolderScan","ScriptBlockParser","ItemParameterDispatch","StartupLuaDiagnostics","AnimationFrameCollector","AnimationKeyLookup","ClipFrameIndex","TranslationPreparation","SaveDirectoryPreparation")){
            for(Class<?> hook:Class.forName("me.pavel.modstudio."+owner,false,StartupPatchSignatureTest.class.getClassLoader()).getDeclaredClasses()){
                Patch patch=hook.getAnnotation(Patch.class);if(patch==null || !patch.strictMatch())continue;
                Class<?> nativeClass=Class.forName(patch.className(),false,hook.getClassLoader());
                boolean matched=false;
                for(Method advice:hook.getDeclaredMethods()){
                    if(advice.getAnnotation(Patch.OnEnter.class)==null && advice.getAnnotation(Patch.OnExit.class)==null)continue;
                    boolean all=Arrays.stream(advice.getParameters()).anyMatch(p->p.isAnnotationPresent(Patch.AllArguments.class));
                    Map<Integer,Class<?>> arguments=new HashMap<>();
                    for(Parameter parameter:advice.getParameters()){
                        Patch.Argument arg=parameter.getAnnotation(Patch.Argument.class);
                        if(arg!=null)arguments.put(arg.value(),parameter.getType());
                    }
                    for(Method target:nativeClass.getDeclaredMethods()){
                        if(!target.getName().equals(patch.methodName()))continue;
                        if(all || target.getParameterCount()==0){matched=true;continue;}
                        if(arguments.isEmpty())continue;
                        boolean valid=true;
                        for(var arg:arguments.entrySet())if(arg.getKey()>=target.getParameterCount() || (arg.getValue()!=Object.class && !arg.getValue().isAssignableFrom(target.getParameterTypes()[arg.getKey()]))){valid=false;break;}
                        if(valid)matched=true;
                    }
                }
                if(!matched)throw new AssertionError("Installed Buddy strict matcher selects no native method: "+hook.getName()+" -> "+patch.className()+"."+patch.methodName());
                checked++;
            }
        }
        if(checked<10)throw new AssertionError("Missing startup patch coverage");
        StartupPreparationPolicy.compatible=true;
        for(String feature:List.of("lua","definitions","itemDispatch","animations")) {
            if(!StartupPreparationPolicy.enabled(feature))throw new AssertionError("Verified default disabled: "+feature);
            System.setProperty("modstudio.startup."+feature,"false");
            if(StartupPreparationPolicy.enabled(feature))throw new AssertionError("Explicit disable ignored: "+feature);
            System.clearProperty("modstudio.startup."+feature);
        }
        for(String feature:List.of("diagnostics","menuData","modMetadata"))
            if(StartupPreparationPolicy.enabled(feature))throw new AssertionError("Experiment enabled by default: "+feature);
        System.setProperty("modstudio.startup.enabled","false");
        System.setProperty("modstudio.startup.lua","true");
        if(StartupPreparationPolicy.enabled("lua"))throw new AssertionError("Benchmark master disable ignored");
        System.clearProperty("modstudio.startup.enabled");System.clearProperty("modstudio.startup.lua");
        StartupPreparationPolicy.compatible=false;
        if(StartupPreparationPolicy.enabled("lua"))throw new AssertionError("Unsupported version enabled");
        StartupPreparationPolicy.compatible=true;
        StartupPreparationPolicy.finish();
        if(StartupPreparationPolicy.enabled("lua"))throw new AssertionError("Startup scope remains active after menu entry");
        System.out.println("Startup defaults PASS: verified features on, experiments off, explicit disables/version guard/menu retirement preserved");
        System.out.println("Native startup signature selection PASS: "+checked+" strict hooks select installed methods");
    }
}
