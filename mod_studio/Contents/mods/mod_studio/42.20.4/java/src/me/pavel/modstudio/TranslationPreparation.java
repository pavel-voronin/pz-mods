package me.pavel.modstudio;

import me.zed_0xff.zombie_buddy.Patch;

/** The native %%|%([1-9]) replacement, without a matcher allocation per string. */
public final class TranslationPreparation {
    public static String format(String input) {
        StringBuilder output=null;
        int copied=0;
        for(int i=input.indexOf('%');i>=0 && i+1<input.length();i=input.indexOf('%',i+1)) {
            char next=input.charAt(i+1);
            if(next=='%'){i++;continue;}
            if(next<'1' || next>'9')continue;
            if(output==null)output=new StringBuilder(input.length()+3);
            output.append(input,copied,i+2).append("$s");
            copied=i+2;i++;
        }
        return output==null?input:output.append(input,copied,input.length()).toString();
    }
    @Patch(className="zombie.core.Translator",methodName="formatFixer",warmUp=true,strictMatch=true)
    public static final class FormatPatch {
        @Patch.OnEnter(skipOn=true) public static boolean enter(@Patch.Argument(0) String input,@Patch.Local("formatted") String formatted,@Patch.Local("handled") boolean handled) {
            if(input==null || !StartupPreparationPolicy.enabled("definitions"))return false;
            formatted=TranslationPreparation.format(input);handled=true;
            StartupPreparationPolicy.record(StartupPreparationPolicy.TRANSLATIONS);return true;
        }
        @Patch.OnExit public static void exit(@Patch.Local("handled") boolean handled,@Patch.Local("formatted") String formatted,@Patch.Return(readOnly=false) String result){if(handled)result=formatted;}
    }
}
