package me.pavel.modstudio;

import java.util.Locale;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.entity.components.attributes.Attribute;
import zombie.scripting.objects.Item;

/** Small measured dispatch; all other parameters and error handling remain native. */
public final class ItemParameterDispatch {
    public static boolean apply(Item item,String parameter,String value) {
        if(parameter==null || value==null)return false;
        String key=parameter.trim();
        for(int i=0;i<key.length();i++)if(key.charAt(i)>127)return false;
        key=key.toLowerCase(Locale.ROOT);
        if(!key.equals("count") && !key.equals("canstack") && !key.equals("displaycategory") && !key.equals("conditionmax"))return false;
        if(Attribute.TypeFromName(parameter.trim())!=null)return false;
        try {
            switch(key) {
                case "count" -> item.setCount(Integer.parseInt(value));
                case "canstack" -> item.canStack=value.equalsIgnoreCase("true");
                case "displaycategory" -> item.displayCategory=value.trim();
                case "conditionmax" -> item.setConditionMax(Integer.parseInt(value));
                default -> {return false;}
            }
            return true;
        } catch(RuntimeException invalid){return false;}
    }
    @Patch(className="zombie.scripting.objects.Item",methodName="DoParam",warmUp=true,strictMatch=true)
    public static final class ParamPatch {
        @Patch.OnEnter(skipOn=true) public static boolean enter(@Patch.This Item item,@Patch.Argument(0) String parameter,@Patch.Argument(1) String value) {
            if(!StartupPreparationPolicy.enabled("itemDispatch") || !ItemParameterDispatch.apply(item,parameter,value))return false;
            StartupPreparationPolicy.record(StartupPreparationPolicy.ITEMS);return true;
        }
    }
}
