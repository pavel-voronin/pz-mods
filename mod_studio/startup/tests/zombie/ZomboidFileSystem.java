package zombie;

import java.io.File;
import java.net.URI;
import java.util.*;

/** Only the native method shapes exercised by the early agent. */
public final class ZomboidFileSystem {
    private final List<String> loadList=new ArrayList<>();
    public final Map<String,String> indexed=new LinkedHashMap<>();
    public int nativeScans;
    public int directoryEntries;
    public void init(File root){
        searchFolders(root);
        URI base=new File(root.getAbsolutePath().toLowerCase(Locale.ENGLISH)).toURI();
        for(String path:loadList){
            if(new File(path).isDirectory())directoryEntries++;
            indexed.put(getRelativeFile(base,path),path);
        }
        loadList.clear();
    }
    public void searchFolders(File root){
        nativeScans++;
        zombie.core.Core.getInstance().DoFrameReady();
        String path=root.getAbsolutePath().replace("\\","/").replace("./","");
        if(root.isDirectory()){
            if(path.contains("media/maps/"))loadList.add(path);
            for(String name:root.list())searchFolders(new File(root.getAbsolutePath()+File.separator+name));
        }else loadList.add(path);
    }
    public String getRelativeFile(URI root,String path){
        URI uri=new File(path.toLowerCase(Locale.ENGLISH)).toURI();
        URI relative=root.relativize(uri);
        return relative.equals(uri)?path:relative.getPath();
    }
    public void getAllModFolders(List<String> roots){
        for(String root:roots)DebugFileWatcher.instance.registerDirRecursive(java.nio.file.Path.of(root));
    }
}
