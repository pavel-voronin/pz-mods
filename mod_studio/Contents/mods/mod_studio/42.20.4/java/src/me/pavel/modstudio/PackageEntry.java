package me.pavel.modstudio;

import me.zed_0xff.zombie_buddy.Exposer;

@Exposer.LuaClass(name="ModStudioPackageEntry")
public final class PackageEntry {
    final String name,path,reason;
    final boolean directory,selectable;
    final long size;
    PackageEntry(String name,String path,boolean directory,boolean selectable,long size,String reason) {
        this.name=name;this.path=path;this.directory=directory;this.selectable=selectable;this.size=size;this.reason=reason;
    }
    public String getName(){return name;}
    public String getPath(){return path;}
    public String getReason(){return reason;}
    public boolean isDirectory(){return directory;}
    public boolean isSelectable(){return selectable;}
    public long getSize(){return size;}
}
