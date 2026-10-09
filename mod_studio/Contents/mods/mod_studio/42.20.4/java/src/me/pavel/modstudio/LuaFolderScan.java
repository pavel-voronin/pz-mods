package me.pavel.modstudio;

import java.io.*;
import java.net.URI;
import java.util.*;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;

/** Preserve native File.list order; canonicalize each directory once instead of per child. */
public final class LuaFolderScan {
    public static void search(URI base,File root,List<String> output)throws IOException {
        Deque<File> pending=new ArrayDeque<>();pending.push(root);
        while(!pending.isEmpty()) {
            File file=pending.pop();
            if(file.isDirectory()) {
                String[] names=file.list();
                if(names.length==0)continue;
                String parent=file.getCanonicalFile().getAbsolutePath()+File.separator;
                for(int i=names.length-1;i>=0;i--)pending.push(new File(parent+names[i]));
            } else if(file.getAbsolutePath().toLowerCase().endsWith(".lua")) {
                output.add(ZomboidFileSystem.instance.getRelativeFile(base,file.getAbsolutePath()).toLowerCase(Locale.ENGLISH));
            }
        }
    }
    @Patch(className="zombie.Lua.LuaManager",methodName="searchFolders",warmUp=true,strictMatch=true)
    public static final class FolderPatch {
        @Patch.OnEnter(skipOn=true) public static boolean enter(@Patch.Argument(0) URI base,@Patch.Argument(1) File root)throws IOException {
            if(!StartupPreparationPolicy.enabled("lua"))return false;
            LuaFolderScan.search(base,root,LuaManager.loadList);StartupPreparationPolicy.record(StartupPreparationPolicy.FOLDERS);return true;
        }
    }
}
