package me.pavel.modstudio;

import java.nio.file.*;
import zombie.HiddenFromLua;
import me.zed_0xff.zombie_buddy.Patch;

/** Keep native validation/upload semantics; only replace the physical content root. */
@HiddenFromLua
@Patch(className="zombie.core.znet.SteamWorkshopItem",methodName="getContentFolder",warmUp=true)
public final class ContentSource {
    public static String select(String original) {
        Path contents=Path.of(original);
        if(!contents.getFileName().toString().equals("Contents"))return original;
        Path release=contents.resolveSibling("Contents.release");
        return Files.isDirectory(release)?release.toString():original;
    }
    @Patch.OnExit public static void exit(@Patch.Return(readOnly=false) String value){value=select(value);}
}
