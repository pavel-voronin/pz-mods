package me.pavel.modstudio;

import java.nio.file.*;
import java.util.regex.*;
import org.json.JSONObject;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;

/** Real installed font metrics and Lua widget sizing, without a game window or graphics context. */
final class LayoutFixtures {
    static void install(J2SEPlatform platform,KahluaTable env,Path game,Path pack) throws Exception {
        env.rawset("MSCapturePreview",System.getProperty("modstudio.layoutPreview")!=null);
        var metrics=platform.newTable();env.rawset("MSMetrics",metrics);
        for(String size:new String[]{"default","1x","2x","3x","4x"}) {
            var fonts=platform.newTable();metrics.rawset(size,fonts);int index=0;
            for(String name:new String[]{"Small","Medium","Large"}) {
                Path folder=game.resolve("media/fonts");if(!size.equals("default"))folder=folder.resolve("EN").resolve(size);
                String fnt=Files.readString(folder.resolve("zomboid"+name+".fnt"));
                var font=platform.newTable();fonts.rawset((double)++index,font);
                var height=Pattern.compile("lineHeight=(\\d+)").matcher(fnt);height.find();font.rawset("height",Double.parseDouble(height.group(1)));
                var chars=platform.newTable();font.rawset("chars",chars);
                var advances=Pattern.compile("(?m)^char id=(\\d+) +.*?xadvance=(-?\\d+)").matcher(fnt);
                while(advances.find())chars.rawset(new String(Character.toChars(Integer.parseInt(advances.group(1)))),Double.parseDouble(advances.group(2)));
            }
        }
        var locales=platform.newTable();env.rawset("MSTranslations",locales);
        Path translations=pack.resolve("Contents/mods/mod_studio/common/media/lua/shared/Translate");
        try(var dirs=Files.list(translations)) {
            for(Path dir:dirs.toList()) {
                Path file=dir.resolve("UI.json");if(!Files.exists(file))continue;
                var json=new JSONObject(Files.readString(file));var strings=platform.newTable();locales.rawset(dir.getFileName().toString(),strings);
                for(String key:json.keySet())strings.rawset(key,json.getString(key));
            }
        }
    }
    static String nativeGeometry(Path game) throws Exception {
        StringBuilder code=new StringBuilder();
        for(String spec:new String[]{"ISButton:new,setTitle","ISLabel:new,setName","ISScrollingListBox:new,setFont,rowAt","ISTickBox:new,addOption"}) {
            String[] pair=spec.split(":");String type=pair[0];code.append("do local mock=").append(type).append('\n');
            code.append(Files.readString(game.resolve("media/lua/client/ISUI/"+type+".lua"))).append('\n');
            for(String method:pair[1].split(","))code.append("mock.").append(method).append('=').append(type).append('.').append(method).append('\n');
            code.append(type).append("=mock end\n");
        }
        // Keep the real menu, including player lookup, input, scrolling and lifecycle.
        code.append(Files.readString(game.resolve("media/lua/client/ISUI/ISContextMenu.lua"))).append('\n');
        code.append(Files.readString(game.resolve("media/lua/client/ISUI/ISTabPanel.lua"))).append('\n');
        String uploader=Files.readString(game.resolve("media/lua/client/OptionScreens/WorkshopSubmitScreen.lua"));
        code.append("do local TagsList=ISScrollingListBox:derive('TagsList')\n");
        code.append(uploader.substring(uploader.indexOf("function TagsList:onMouseDown("),uploader.indexOf("function WorkshopSubmitScreen:create()")));
        code.append("MSTagsList=TagsList end\n");
        return code.toString();
    }
}
