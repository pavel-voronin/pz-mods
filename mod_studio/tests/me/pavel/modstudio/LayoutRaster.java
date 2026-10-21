package me.pavel.modstudio;

import java.awt.*;
import java.awt.image.BufferedImage;
import java.nio.file.*;
import java.util.*;
import java.util.regex.*;
import javax.imageio.ImageIO;
import se.krka.kahlua.vm.KahluaTable;

/** Optional temporary raster of the editor's actual layout commands, not a game screenshot. */
final class LayoutRaster {
    static int n(KahluaTable table,String key){return ((Number)table.rawget(key)).intValue();}
    static void write(KahluaTable env,Path game) throws Exception {
        String target=System.getProperty("modstudio.layoutPreview");if(target==null)return;
        var review=(KahluaTable)env.rawget("MSReview");
        var output=new BufferedImage(n(review,"width"),n(review,"height"),BufferedImage.TYPE_INT_RGB);
        var g=output.createGraphics();g.setColor(new Color(9,9,9));g.fillRect(0,0,output.getWidth(),output.getHeight());
        Map<Integer,Map<Integer,Map<String,Integer>>> glyphs=new HashMap<>();Map<String,BufferedImage> pages=new HashMap<>();
        String[] fonts={"Small","Medium","Large"};Path folder=game.resolve("media/fonts");
        String fontSet=(String)review.rawget("fontSet");if(!fontSet.equals("default"))folder=folder.resolve("EN").resolve(fontSet);
        for(int i=1;i<=3;i++){
            var chars=new HashMap<Integer,Map<String,Integer>>();glyphs.put(i,chars);
            for(String line:Files.readAllLines(folder.resolve("zomboid"+fonts[i-1]+".fnt"))){
                if(!line.startsWith("char id="))continue;
                var fields=new HashMap<String,Integer>();var m=Pattern.compile("(\\w+)=(-?\\d+)").matcher(line);
                while(m.find())fields.put(m.group(1),Integer.parseInt(m.group(2)));chars.put(fields.get("id"),fields);
            }
        }
        var commands=(KahluaTable)review.rawget("commands");var iterator=commands.iterator();
        while(iterator.advance()){
            var command=(KahluaTable)iterator.getValue();int x=n(command,"x"),y=n(command,"y"),w=n(command,"w"),h=n(command,"h");
            var color=(KahluaTable)command.rawget("color");float r=((Number)color.rawget(1d)).floatValue(),green=((Number)color.rawget(2d)).floatValue(),b=((Number)color.rawget(3d)).floatValue();g.setColor(new Color(r,green,b));
            String kind=(String)command.rawget("kind");
            if(kind.equals("border")){g.drawRect(x,y,w-1,h-1);continue;}
            if(kind.equals("fill")){g.fillRect(x,y,w,h);continue;}
            if(kind.equals("texture")){
                String path=(String)command.rawget("value");var icon=pages.get(path);
                if(icon==null){icon=ImageIO.read(game.resolve(path).toFile());pages.put(path,icon);}
                g.drawImage(icon,x,y,w,h,null);continue;
            }
            int font=n(command,"font");String text=(String)command.rawget("value");
            for(int cp:text.codePoints().toArray()){
                var ch=glyphs.get(font).get(cp);if(ch==null)continue;
                String imageName="zomboid"+fonts[font-1]+"_"+ch.get("page")+".png";
                String cacheKey=imageName+"/"+r+"/"+green+"/"+b;
                var atlas=pages.get(cacheKey);
                if(atlas==null){
                    atlas=ImageIO.read(folder.resolve(imageName).toFile());
                    for(int py=0;py<atlas.getHeight();py++)for(int px=0;px<atlas.getWidth();px++){
                        int argb=atlas.getRGB(px,py);atlas.setRGB(px,py,(argb&0xff000000)|((int)(((argb>>16)&255)*r)<<16)|((int)(((argb>>8)&255)*green)<<8)|(int)((argb&255)*b));
                    }
                    pages.put(cacheKey,atlas);
                }
                int dx=x+ch.get("xoffset"),dy=y+ch.get("yoffset"),sx=ch.get("x"),sy=ch.get("y"),cw=ch.get("width"),chh=ch.get("height");
                g.drawImage(atlas,dx,dy,dx+cw,dy+chh,sx,sy,sx+cw,sy+chh,null);x+=ch.get("xadvance");
            }
        }
        g.dispose();ImageIO.write(output,"PNG",Path.of(target).toFile());
    }
}
