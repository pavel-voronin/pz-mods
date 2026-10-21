package me.pavel.modstudio;

import me.zed_0xff.zombie_buddy.Patch;

@Patch(className="zombie.core.znet.SteamWorkshopItem", methodName="validatePreviewImage", warmUp=true)
public class PreviewPatch {
    @Patch.OnEnter(skipOn=true)
    public static boolean enter() { return Guard.isPreviewOmitted(); }
}
