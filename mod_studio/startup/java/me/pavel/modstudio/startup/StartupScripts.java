package me.pavel.modstudio.startup;

/** Linear removal for balanced native block comments; unusual syntax falls back. */
public final class StartupScripts {
    public static java.util.ArrayList<String> parseTokens(String text){
        if(text==null)return null;
        var tokens=new java.util.ArrayList<String>();int depth=0,start=0;
        for(int i=0;i<text.length();i++){
            char c=text.charAt(i);
            if(c=='{'){
                // Native searches begin at index 1 of each remaining suffix.
                if(depth==0&&i==start)return null;
                depth++;
            }else if(c=='}'){
                if(depth==0)return null;
                if(--depth==0){tokens.add(text.substring(start,i+1).trim());start=i+1;}
            }
        }
        if(depth!=0)return null;
        String tail=text.substring(start).trim();if(!tail.isEmpty())tokens.add(tail);
        return tokens;
    }
    public static String stripComments(String text){
        if(text==null)return null;
        if(text.indexOf("/*")<0)return text;
        // Native reverse matching also sees overlapping delimiters. Preserve its
        // unusual malformed-comment behavior rather than treating these as C.
        if(text.indexOf("/*/")>=0||text.indexOf("*/*")>=0)return null;
        StringBuilder output=new StringBuilder(text.length());int depth=0,segment=0;
        for(int i=0;i+1<text.length();){
            char a=text.charAt(i),b=text.charAt(i+1);
            if(a=='/'&&b=='*'){
                if(depth!=0)return null;
                if(depth==0&&!append(output,text,segment,i))return null;
                depth++;i+=2;continue;
            }
            if(a=='*'&&b=='/'){
                if(depth==0)return null;
                depth--;i+=2;if(depth==0)segment=i;continue;
            }
            i++;
        }
        if(depth!=0||!append(output,text,segment,text.length()))return null;
        return output.toString();
    }
    private static boolean append(StringBuilder output,String text,int from,int to){
        if(from==to)return true;
        if(!output.isEmpty()){
            char a=output.charAt(output.length()-1),b=text.charAt(from);
            if((a=='/'&&b=='*')||(a=='*'&&b=='/'))return false;
        }
        output.append(text,from,to);return true;
    }
}
