package me.pavel.modstudio;

import java.io.IOException;
import java.util.*;

/** Bounded strict JSON; rejects duplicate keys and permissive JavaScript syntax. */
final class ScenarioJson {
    private final String text; private int at,nodes;
    private ScenarioJson(String text){this.text=text;}
    static Map<String,Object> parse(String text)throws IOException {
        if(text.length()>262144)throw new IOException("JSON exceeds 256 KiB");
        var p=new ScenarioJson(text);Object value=p.value(0);p.space();
        if(p.at!=text.length()||!(value instanceof Map))throw p.error("Expected one JSON object");
        return object(value);
    }
    @SuppressWarnings("unchecked") static Map<String,Object> object(Object v)throws IOException {
        if(!(v instanceof Map))throw new IOException("Expected JSON object");return (Map<String,Object>)v;
    }
    static String string(Map<String,Object> m,String key)throws IOException {
        if(!(m.get(key) instanceof String s))throw new IOException("Expected string: "+key);return s;
    }
    static void keys(Map<String,Object> m,String... keys)throws IOException {
        var allowed=Set.of(keys);for(String k:m.keySet())if(!allowed.contains(k))throw new IOException("Unknown field: "+k);
    }
    private IOException error(String message){return new IOException(message+" at character "+at);}
    private void space(){while(at<text.length()&&" \r\n\t".indexOf(text.charAt(at))>=0)at++;}
    private boolean take(char c){space();if(at<text.length()&&text.charAt(at)==c){at++;return true;}return false;}
    private void need(char c)throws IOException {if(!take(c))throw error("Expected '"+c+"'");}
    private Object value(int depth)throws IOException {
        if(depth>24||++nodes>32768)throw error("JSON structure limit exceeded");space();
        if(at==text.length())throw error("Unexpected end");char c=text.charAt(at);
        if(c=='"')return quoted();
        if(take('{')){var m=new LinkedHashMap<String,Object>();if(take('}'))return m;do{
            space();if(at==text.length()||text.charAt(at)!='"')throw error("Expected quoted key");
            String key=quoted();need(':');if(m.containsKey(key))throw error("Duplicate key: "+key);m.put(key,value(depth+1));
        }while(take(','));need('}');return m;}
        if(take('[')){var a=new ArrayList<Object>();if(take(']'))return a;do{a.add(value(depth+1));}while(take(','));need(']');return a;}
        for(String literal:List.of("true","false","null"))if(text.startsWith(literal,at)){at+=literal.length();return literal.equals("null")?null:literal.equals("true");}
        int start=at;while(at<text.length()&&"-+0123456789.eE".indexOf(text.charAt(at))>=0)at++;
        String s=text.substring(start,at);if(!s.matches("-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?"))throw error("Invalid number");
        try{double n=Double.parseDouble(s);if(!Double.isFinite(n))throw error("Non-finite number");return n;}catch(NumberFormatException e){throw error("Invalid number");}
    }
    private String quoted()throws IOException {
        at++;var out=new StringBuilder();while(at<text.length()){
            char c=text.charAt(at++);if(c=='"')return out.toString();if(c<32)throw error("Control character in string");
            if(c=='\\'){if(at==text.length())throw error("Incomplete escape");c=text.charAt(at++);switch(c){
                case '"','\\','/'->out.append(c);case 'b'->out.append('\b');case 'f'->out.append('\f');case 'n'->out.append('\n');case 'r'->out.append('\r');case 't'->out.append('\t');
                case 'u'->{if(at+4>text.length())throw error("Incomplete Unicode escape");try{out.append((char)Integer.parseInt(text.substring(at,at+4),16));}catch(NumberFormatException e){throw error("Invalid Unicode escape");}at+=4;}
                default->throw error("Invalid escape");
            }}else out.append(c);
        }throw error("Unterminated string");
    }
    static String write(Object value){var b=new StringBuilder();write(value,b);return b.toString()+"\n";}
    private static void write(Object v,StringBuilder b){
        if(v==null){b.append("null");return;}if(v instanceof String s){b.append('"');for(char c:s.toCharArray())switch(c){case '"'->b.append("\\\"");case '\\'->b.append("\\\\");case '\n'->b.append("\\n");case '\r'->b.append("\\r");case '\t'->b.append("\\t");default->{if(c<32)b.append(String.format("\\u%04x",(int)c));else b.append(c);}}b.append('"');return;}
        if(v instanceof Map<?,?> m){b.append('{');boolean first=true;for(var e:m.entrySet()){if(!first)b.append(',');first=false;write(e.getKey().toString(),b);b.append(':');write(e.getValue(),b);}b.append('}');return;}
        if(v instanceof Collection<?> a){b.append('[');boolean first=true;for(var x:a){if(!first)b.append(',');first=false;write(x,b);}b.append(']');return;}
        if(v instanceof Boolean||v instanceof Number){b.append(v);return;}throw new IllegalArgumentException("Unsupported JSON value");
    }
}
