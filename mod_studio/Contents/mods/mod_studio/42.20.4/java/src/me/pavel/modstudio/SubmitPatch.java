package me.pavel.modstudio;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.znet.SteamWorkshop;
import zombie.core.znet.SteamWorkshopItem;

@Patch(className="zombie.core.znet.SteamWorkshop", methodName="SubmitWorkshopItem", warmUp=true)
public class SubmitPatch {
    @Patch.OnEnter(skipOn=true)
    public static boolean enter(@Patch.This SteamWorkshop self, @Patch.Argument(0) SteamWorkshopItem item,
                                @Patch.Local("workshopGuardResult") boolean result) {
        result = Guard.submit(self, item);
        return true;
    }
    @Patch.OnExit
    public static void exit(@Patch.Local("workshopGuardResult") boolean result, @Patch.Return(readOnly=false) boolean returned) {
        returned = result;
    }
}
