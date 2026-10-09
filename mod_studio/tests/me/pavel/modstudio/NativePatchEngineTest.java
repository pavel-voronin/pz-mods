package me.pavel.modstudio;

import java.io.*;
import java.lang.instrument.*;
import java.lang.reflect.*;
import java.net.*;
import java.nio.file.*;
import java.util.*;
import java.util.jar.*;
import net.bytebuddy.jar.asm.*;

/** Execute the installed Buddy matcher and transformer in an offline JVM.
 * Instrumentation is a recorder; it never attaches an agent or redefines game classes. */
public final class NativePatchEngineTest {
    public static void main(String[] args)throws Exception {
        Map<String,byte[]> converted=new HashMap<>();
        List<ClassFileTransformer> transformers=new ArrayList<>();
        Instrumentation recorder=(Instrumentation)java.lang.reflect.Proxy.newProxyInstance(NativePatchEngineTest.class.getClassLoader(),new Class<?>[]{Instrumentation.class},(proxy,method,values)->switch(method.getName()){
            case "redefineClasses" -> {for(ClassDefinition definition:(ClassDefinition[])values[0])converted.put(definition.getDefinitionClass().getName(),definition.getDefinitionClassFile());yield null;}
            case "addTransformer" -> {transformers.add((ClassFileTransformer)values[0]);yield null;}
            case "removeTransformer","isRetransformClassesSupported","isRedefineClassesSupported","isModifiableClass","isModifiableModule" -> true;
            case "isNativeMethodPrefixSupported" -> false;
            case "getAllLoadedClasses","getInitiatedClasses" -> new Class<?>[0];
            case "retransformClasses","redefineModule" -> null;
            default -> throw new UnsupportedOperationException(method.getName());
        });
        Class<?> patchTransformer=Class.forName("me.zed_0xff.zombie_buddy.PatchTransformer");
        Method convert=patchTransformer.getDeclaredMethod("transformPatchClass",Class.class,Instrumentation.class,int.class,boolean.class);convert.setAccessible(true);
        for(Class<?> hook:List.of(LuaPreparationHooks.PreparePatch.class,LuaPreparationHooks.ScopePatch.class,AnimationKeyLookup.ScopePatch.class,StartupLuaDiagnostics.EventPatch.class,TranslationPreparation.FormatPatch.class,SaveDirectoryPreparation.ListPatch.class))convert.invoke(null,hook,recorder,0,false);
        boolean legacy=args.length>0 && args[0].equals("legacy");
        if(legacy){
            // Reproduce the shipped defect: a strict advice declared without any
            // target arguments. Its body does not access the removed parameters.
            String name=LuaPreparationHooks.PreparePatch.class.getName();
            ClassWriter writer=new ClassWriter(0);
            new ClassReader(converted.get(name)).accept(new ClassVisitor(Opcodes.ASM9,writer){
                @Override public MethodVisitor visitMethod(int access,String method,String descriptor,String signature,String[] exceptions){
                    if(!method.equals("enter"))return super.visitMethod(access,method,descriptor,signature,exceptions);
                    return new MethodVisitor(Opcodes.ASM9,super.visitMethod(access,method,"()V",null,exceptions)){
                        @Override public void visitParameter(String name,int access){}
                        @Override public void visitAnnotableParameterCount(int count,boolean visible){}
                        @Override public AnnotationVisitor visitParameterAnnotation(int parameter,String descriptor,boolean visible){return null;}
                    };
                }
            },ClassReader.SKIP_DEBUG);
            converted.put(name,writer.toByteArray());
        }
        Path jar=Files.createTempFile("modstudio-native-matcher-",".jar");
        try(JarOutputStream output=new JarOutputStream(Files.newOutputStream(jar))){
            for(var entry:converted.entrySet()){output.putNextEntry(new JarEntry(entry.getKey().replace('.','/')+".class"));output.write(entry.getValue());output.closeEntry();}
        }
        ClassLoader parent=NativePatchEngineTest.class.getClassLoader();
        Class<?> loaderType=Class.forName("me.zed_0xff.zombie_buddy.Loader");
        Field instrumentation=loaderType.getDeclaredField("g_instrumentation"),verbosity=loaderType.getDeclaredField("g_verbosity");instrumentation.setAccessible(true);verbosity.setAccessible(true);
        Object before=instrumentation.get(null);int beforeVerbosity=verbosity.getInt(null);
        try(URLClassLoader patches=new URLClassLoader(new URL[]{jar.toUri().toURL()},null){
            @Override protected Class<?> loadClass(String name,boolean resolve)throws ClassNotFoundException {
                byte[] bytes=converted.get(name);if(bytes==null)return parent.loadClass(name);
                synchronized(getClassLoadingLock(name)){Class<?> type=findLoadedClass(name);if(type==null)type=defineClass(name,bytes,0,bytes.length);if(resolve)resolveClass(type);return type;}
            }
        }){
            instrumentation.set(null,recorder);verbosity.setInt(null,0);
            Class.forName("me.zed_0xff.zombie_buddy.PatchEngine").getMethod("applyPatches",String.class,ClassLoader.class).invoke(null,"me.pavel.modstudio",patches);
            if(transformers.isEmpty())throw new AssertionError("Native patch engine did not register its transformer");
            Map<String,Map<String,Integer>> calls=new HashMap<>();
            for(String name:List.of("zombie.Lua.LuaManager","zombie.Lua.Event","zombie.core.skinnedmodel.model.jassimp.ImportedSkeleton","zombie.core.Translator","zombie.Lua.LuaManager$GlobalObject")){
                Class<?> target=Class.forName(name,false,parent);String internal=name.replace('.','/');byte[] bytes;
                try(InputStream input=target.getResourceAsStream("/"+internal+".class")){bytes=input.readAllBytes();}
                for(ClassFileTransformer transformer:transformers){byte[] result=transformer.transform(target.getModule(),parent,internal,null,target.getProtectionDomain(),bytes);if(result!=null)bytes=result;}
                Map<String,Integer> methods=new HashMap<>();calls.put(name,methods);
                new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9){
                    @Override public MethodVisitor visitMethod(int access,String method,String descriptor,String signature,String[] exceptions){
                        return new MethodVisitor(Opcodes.ASM9){
                            @Override public void visitMethodInsn(int opcode,String owner,String called,String descriptor,boolean isInterface){if(owner.startsWith("me/pavel/modstudio/"))methods.merge(method+":"+called,1,Integer::sum);}
                        };
                    }
                },ClassReader.SKIP_DEBUG|ClassReader.SKIP_FRAMES);
            }
            require(calls,"zombie.Lua.LuaManager","RunLuaInternal:prepare",legacy?0:1);
            require(calls,"zombie.Lua.LuaManager","LoadDirBase:begin",3);
            require(calls,"zombie.Lua.Event","trigger:begin",1);
            require(calls,"zombie.core.skinnedmodel.model.jassimp.ImportedSkeleton","processAnimation:open",1);
            require(calls,"zombie.core.Translator","formatFixer:format",1);
            require(calls,"zombie.Lua.LuaManager$GlobalObject","getFullSaveDirectoryTable:list",1);
            System.out.println(legacy?"Installed native patch engine negative control PASS: former argument-free strict hook emits no Lua preparation call":"Installed native patch engine PASS: actual method selection emits Lua preparation, all directory scopes, event diagnostics and animation scope; no live instrumentation");
        }finally{instrumentation.set(null,before);verbosity.setInt(null,beforeVerbosity);Files.delete(jar);}
    }
    private static void require(Map<String,Map<String,Integer>> calls,String owner,String method,int expected){
        int actual=calls.get(owner).getOrDefault(method,0);if(actual!=expected)throw new AssertionError("Native matcher "+owner+"."+method+" calls="+actual+", expected="+expected);
    }
}
