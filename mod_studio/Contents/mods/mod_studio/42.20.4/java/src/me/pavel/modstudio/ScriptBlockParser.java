package me.pavel.modstudio;

import java.lang.invoke.*;
import java.util.ArrayList;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.scripting.ScriptBucket;
import zombie.scripting.ScriptParser;

/** Native block grammar and ordering, with allocation-free header word discovery. */
public final class ScriptBlockParser {
    private static final VarHandle UID;
    static {
        try {UID=MethodHandles.privateLookupIn(ScriptParser.Block.class,MethodHandles.lookup()).findVarHandle(ScriptParser.Block.class,"uid",String.class);}
        catch(ReflectiveOperationException error){throw new ExceptionInInitializerError(error);}
    }
    private static boolean whitespace(char c){return c==' ' || c=='\t' || c=='\n' || c=='\r' || c=='\f' || c=='\u000b';}
    public static ArrayList<String> tokens(String text) {
        ArrayList<String> result=new ArrayList<>();int offset=0;
        while(text.indexOf('}',offset+1)!=-1) {
            int depth=0,open=0,close=0;
            do {
                int found=text.indexOf('{',offset+open+1);open=found<0?-1:found-offset;
                found=text.indexOf('}',offset+close+1);close=found<0?-1:found-offset;
                if((close<open && close!=-1) || open==-1){open=close;depth--;}
                else {close=open;depth++;}
            } while(depth>0);
            int end=offset+open+1;result.add(text.substring(offset,end).trim());offset=end;
        }
        String tail=text.substring(offset).trim();if(!tail.isEmpty())result.add(tail);
        return result;
    }
    public static ScriptParser.Value find(ScriptParser.Block block,String key) {
        for(ScriptParser.Value value:block.values) {
            int end=value.string.indexOf('=');if(end<=0)continue;
            if(value.getClass()!=ScriptParser.Value.class){if(value.getKey().trim().equals(key))return value;continue;}
            int start=0;while(start<end && value.string.charAt(start)<=32)start++;
            while(end>start && value.string.charAt(end-1)<=32)end--;
            if(key!=null && key.length()==end-start && value.string.regionMatches(start,key,0,key.length()))return value;
        }
        return null;
    }
    public static int read(String s,int start,ScriptParser.Block block) {
        int i;
        for(i=start;i<s.length();i++) {
            char c=s.charAt(i);
            if(c=='{') {
                ScriptParser.Block child=new ScriptParser.Block();block.children.add(child);block.elements.add(child);
                int left=start,right=i;
                while(left<right && s.charAt(left)<=32)left++;
                while(right>left && s.charAt(right-1)<=32)right--;
                int end=left;while(end<right && !whitespace(s.charAt(end)))end++;
                child.type=s.substring(left,end);
                int idStart=end;while(idStart<right && whitespace(s.charAt(idStart)))idStart++;
                int idEnd=idStart;while(idEnd<right && !whitespace(s.charAt(idEnd)))idEnd++;
                child.id=idStart<right?s.substring(idStart,idEnd):null;
                String current=ScriptBucket.getCurrentScriptObject();
                if(current!=null)UID.set(child,"UID:"+current+"@"+child.type+"@"+i);
                start=i=read(s,i+1,child);
                continue;
            }
            if(c=='}')return i+1;
            if(c!=',')continue;
            ScriptParser.Value value=new ScriptParser.Value();value.string=s.substring(start,i);
            block.values.add(value);block.elements.add(value);start=i+1;
        }
        return i;
    }
    @Patch(className="zombie.scripting.ScriptParser",methodName="readBlock",warmUp=true,strictMatch=true)
    public static final class BlockPatch {
        @Patch.OnEnter(skipOn=true) public static boolean enter(@Patch.Argument(0) String text,@Patch.Argument(1) int start,@Patch.Argument(2) ScriptParser.Block block,@Patch.Local("end") int end,@Patch.Local("handled") boolean handled) {
            if(!StartupPreparationPolicy.enabled("definitions"))return false;
            end=ScriptBlockParser.read(text,start,block);handled=true;StartupPreparationPolicy.record(StartupPreparationPolicy.BLOCKS);return true;
        }
        @Patch.OnExit public static void exit(@Patch.Local("handled") boolean handled,@Patch.Local("end") int end,@Patch.Return(readOnly=false) int result){if(handled)result=end;}
    }
    @Patch(className="zombie.scripting.ScriptParser$Block",methodName="getValue",warmUp=true,strictMatch=true)
    public static final class ValuePatch {
        @Patch.OnEnter(skipOn=true) public static boolean enter(@Patch.This ScriptParser.Block block,@Patch.Argument(0) String key,@Patch.Local("value") ScriptParser.Value value,@Patch.Local("handled") boolean handled) {
            if(!StartupPreparationPolicy.enabled("definitions"))return false;
            value=ScriptBlockParser.find(block,key);handled=true;StartupPreparationPolicy.record(StartupPreparationPolicy.VALUES);return true;
        }
        @Patch.OnExit public static void exit(@Patch.Local("handled") boolean handled,@Patch.Local("value") ScriptParser.Value value,@Patch.Return(readOnly=false) ScriptParser.Value result){if(handled)result=value;}
    }
    @Patch(className="zombie.scripting.ScriptParser",methodName="parseTokens",warmUp=true,strictMatch=true)
    public static final class TokensPatch {
        @Patch.OnEnter(skipOn=true) public static boolean enter(@Patch.Argument(0) String text,@Patch.Local("tokens") ArrayList<String> tokens,@Patch.Local("handled") boolean handled) {
            if(!StartupPreparationPolicy.enabled("definitions"))return false;
            tokens=ScriptBlockParser.tokens(text);handled=true;StartupPreparationPolicy.record(StartupPreparationPolicy.TOKENS);return true;
        }
        @Patch.OnExit public static void exit(@Patch.Local("handled") boolean handled,@Patch.Local("tokens") ArrayList<String> tokens,@Patch.Return(readOnly=false) ArrayList<String> result){if(handled)result=tokens;}
    }
}
