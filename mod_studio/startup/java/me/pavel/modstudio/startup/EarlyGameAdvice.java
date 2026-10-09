package me.pavel.modstudio.startup;

import net.bytebuddy.asm.Advice;

/** Advice targeting only vanilla game classes. */
public final class EarlyGameAdvice {
    public static class CommentAdvice {
        @Advice.OnMethodEnter(skipOn=Advice.OnNonDefaultValue.class)
        public static String enter(@Advice.Argument(0) String text){return StartupScanner.enabled?StartupScripts.stripComments(text):null;}
        @Advice.OnMethodExit public static void exit(@Advice.Enter String prepared,@Advice.Return(readOnly=false) String output){if(prepared!=null)output=prepared;}
    }
    public static class TokenAdvice {
        @Advice.OnMethodEnter(skipOn=Advice.OnNonDefaultValue.class)
        public static java.util.ArrayList<String> enter(@Advice.Argument(0) String text){return StartupScanner.enabled?StartupScripts.parseTokens(text):null;}
        @Advice.OnMethodExit public static void exit(@Advice.Enter java.util.ArrayList<String> prepared,@Advice.Return(readOnly=false) java.util.ArrayList<String> output){if(prepared!=null)output=prepared;}
    }
    public static class WatchUpdateAdvice {
        @Advice.OnMethodEnter public static void enter(){StartupWatch.flush();}
    }
    public static class IndexAdvice {
        @Advice.OnMethodEnter public static void enter(){StartupScanner.enterIndex();}
        @Advice.OnMethodExit(onThrowable=Throwable.class) public static void exit(){StartupScanner.exitIndex();}
    }
    public static class WatchBatchAdvice {
        @Advice.OnMethodEnter public static void enter(){StartupWatch.begin();}
        @Advice.OnMethodExit(onThrowable=Throwable.class) public static void exit(){StartupWatch.finish();}
    }
    public static class WatchAdvice {
        @Advice.OnMethodEnter(skipOn=Advice.OnNonDefaultValue.class)
        public static boolean enter(@Advice.Argument(0) java.nio.file.Path root,@Advice.This Object owner,@Advice.FieldValue("watcher") java.nio.file.WatchService watcher){
            return StartupWatch.submit(root,owner,watcher);
        }
    }
    public static class RelativeAdvice {
        @Advice.OnMethodEnter(skipOn=Advice.OnNonDefaultValue.class)
        public static String enter(@Advice.Argument(0) java.net.URI root,@Advice.Argument(1) String path){return StartupScanner.relative(root,path);}
        @Advice.OnMethodExit public static void exit(@Advice.Enter String cached,@Advice.Return(readOnly=false) String result){if(cached!=null)result=cached;}
    }
    public static class ScanAdvice {
        @Advice.OnMethodEnter(skipOn=Advice.OnNonDefaultValue.class)
        public static boolean enter(@Advice.Argument(0) java.io.File root,@Advice.FieldValue("loadList") java.util.List<String> output,@Advice.Local("start") long start){
            start=StartupTrace.scanEnter();
            return StartupScanner.enabled && start!=0 && StartupScanner.replace(root,output,StartupScanner.POLL);
        }
        @Advice.OnMethodExit(onThrowable=Throwable.class)
        public static void exit(@Advice.Argument(0) java.io.File root,@Advice.Local("start") long start,@Advice.Thrown Throwable error){StartupTrace.scanExit(root,start,error);}
    }
}
