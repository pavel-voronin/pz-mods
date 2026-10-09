package me.pavel.modstudio;

import java.io.File;
import java.util.*;
import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;

/** Fresh native save listing; filesystem timestamps are read once before sorting. */
public final class SaveDirectoryPreparation {
    private record Dated(File file,long modified){}
    static void sort(ArrayList<File> files){
        ArrayList<Dated> dated=new ArrayList<>(files.size());
        for(File file:files)dated.add(new Dated(file,file.lastModified()));
        dated.sort(Comparator.comparingLong(Dated::modified).reversed());
        for(int i=0;i<files.size();i++)files.set(i,dated.get(i).file());
    }
    public static KahluaTable list(String saveDir){
        KahluaTable table=LuaManager.platform.newTable();
        File root=new File(saveDir+File.separator);
        if(!root.exists())root.mkdir();
        String[] names=root.list();if(names==null)return table;
        ArrayList<File> files=new ArrayList<>();
        for(String name:names){
            File mode=new File(saveDir+File.separator+name);
            if(!mode.isDirectory() || "Multiplayer".equals(name))continue;
            files.addAll(LuaManager.GlobalObject.getSaveDirectory(saveDir+File.separator+name));
        }
        sort(files);
        for(int i=0;i<files.size();i++)table.rawset(Double.valueOf(i+1),LuaManager.GlobalObject.getSaveName(files.get(i)));
        return table;
    }
    @Patch(className="zombie.Lua.LuaManager$GlobalObject",methodName="getFullSaveDirectoryTable",warmUp=true,strictMatch=true)
    public static final class ListPatch {
        @Patch.OnEnter(skipOn=true) public static boolean enter(@Patch.Local("table") KahluaTable table,@Patch.Local("handled") boolean handled){
            if(!StartupPreparationPolicy.enabled("menuData"))return false;
            table=SaveDirectoryPreparation.list(ZomboidFileSystem.instance.getSaveDir());handled=true;
            StartupPreparationPolicy.record(StartupPreparationPolicy.SAVE_LISTS);return true;
        }
        @Patch.OnExit public static void exit(@Patch.Local("table") KahluaTable table,@Patch.Local("handled") boolean handled,@Patch.Return(readOnly=false) KahluaTable result){if(handled)result=table;}
    }
}
