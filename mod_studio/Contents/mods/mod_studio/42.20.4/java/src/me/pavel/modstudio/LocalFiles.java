package me.pavel.modstudio;

import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import javax.imageio.ImageIO;
import zombie.HiddenFromLua;
import zombie.core.znet.SteamWorkshopItem;
import zombie.gameStates.ChooseGameInfo;

@HiddenFromLua
final class LocalFiles {
    // PZ's conservative byte cap. Pixel/frame bounds below protect our decoder, not Steam API rules.
    static final long PREVIEW_UPLOAD_BYTES=1_024_000,PREVIEW_DOWNLOAD_BYTES=16*1024*1024;
    static Path root(SteamWorkshopItem item) {return Path.of(item.getContentFolder()).toAbsolutePath().getParent();}
    static String loadReleaseNotes(SteamWorkshopItem item) throws Exception {
        Path file=Path.of(item.getContentFolder()).resolve("release-notes.txt");
        if(Files.notExists(file)) return "";
        String notes=Files.readString(file,StandardCharsets.UTF_8);
        return notes.startsWith("\uFEFF")?notes.substring(1):notes;
    }
    static String validateContents(SteamWorkshopItem item) {
        String error=item.validateContents();
        if(!"FileNotAllowedInContents".equals(error)) return error;
        // Native validation forbids root files. Permit only our notes and keep native folder/type checks.
        Path root=Path.of(item.getContentFolder());
        boolean folder=false;
        try(var paths=Files.newDirectoryStream(root)) {
            for(Path path:paths) {
                String name=path.getFileName().toString();
                if(!Files.isDirectory(path)) {
                    if(name.equals("release-notes.txt") && Files.isRegularFile(path)) continue;
                    return "FileNotAllowedInContents";
                }
                String method=switch(name) {
                    case "mods" -> "validateModsFolder";
                    case "buildings" -> "validateBuildingsFolder";
                    case "creative" -> "validateCreativeFolder";
                    default -> null;
                };
                if(method==null) return "FolderNotAllowedInContents";
                error=validateNative(item,method,path);
                if(error!=null) return error;
                folder=true;
            }
            return folder?validateNative(item,"validateFileTypes",root):"EmptyContentsFolder";
        } catch(Exception e) {return "IOError";}
    }
    private static String validateNative(SteamWorkshopItem item,String name,Path path) throws Exception {
        var method=SteamWorkshopItem.class.getDeclaredMethod(name,Path.class);
        method.setAccessible(true);
        return (String)method.invoke(item,path);
    }
    static ArrayList<String> loadEnglish(SteamWorkshopItem item) throws Exception {
        String title="";List<String> description=new ArrayList<>();
        for(String line:Files.readAllLines(root(item).resolve("workshop.txt"),StandardCharsets.UTF_8)) {
            String key=line.stripLeading();
            if(key.startsWith("title=")) title=key.substring(6);
            if(key.startsWith("description=")) description.add(key.substring(12));
        }
        return new ArrayList<>(List.of(title,String.join("\n",description)));
    }
    static void replace(SteamWorkshopItem item,Map<String,List<String>> fields) throws Exception {
        Path file=root(item).resolve("workshop.txt");
        List<String> previous=Files.exists(file)?Files.readAllLines(file,StandardCharsets.UTF_8):List.of("version=1");
        List<String> result=new ArrayList<>();Set<String> written=new HashSet<>();
        for(String line:previous) {
            String key=line.stripLeading().split("=",2)[0];
            if(!fields.containsKey(key)) result.add(line);
            else if(written.add(key)) for(String value:fields.get(key)) result.add(key+"="+value);
        }
        for(String key:fields.keySet()) if(written.add(key)) for(String value:fields.get(key)) result.add(key+"="+value);
        Path temporary=Files.createTempFile(file.getParent(),".mod-studio-",".tmp");
        try {
            Files.write(temporary,result,StandardCharsets.UTF_8);
            try {Files.move(temporary,file,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);}
            catch(AtomicMoveNotSupportedException e) {Files.move(temporary,file,StandardCopyOption.REPLACE_EXISTING);}
        } finally {Files.deleteIfExists(temporary);}
    }
    static void saveEnglish(SteamWorkshopItem item,String title,String description) throws Exception {
        SteamWriter.checkedText(title,129);SteamWriter.checkedText(description,8000);
        if(title==null || description==null || title.contains("\n") || title.contains("\r")) throw new IllegalArgumentException("invalid_text");
        Map<String,List<String>> fields=new LinkedHashMap<>();fields.put("title",List.of(title));
        fields.put("description",Arrays.asList(description.replace("\r\n","\n").replace('\r','\n').split("\n",-1)));
        replace(item,fields);
    }
    static void saveId(SteamWorkshopItem item) throws Exception {
        if(item.getID()==null) throw new IllegalArgumentException("invalid_id");
        replace(item,Map.of("id",List.of(item.getID())));
    }
    static void checkPreview(Path path) throws Exception {
        inspectPreview(path,PREVIEW_UPLOAD_BYTES);
    }
    static PreviewInfo inspectPreview(Path path,long limit) throws Exception {
        return inspectPreview(path,limit,true);
    }
    static PreviewInfo inspectPreview(Path path,long limit,boolean requireRenderable) throws Exception {
        if(!Files.isRegularFile(path) || Files.size(path)>limit || Files.size(path)==0) throw new IllegalArgumentException("preview_size");
        long bytes=Files.size(path);
        try(var stream=ImageIO.createImageInputStream(path.toFile())) {
            var readers=ImageIO.getImageReaders(stream);
            if(!readers.hasNext()) throw new IllegalArgumentException("preview_format");
            var reader=readers.next();
            try {
                String format=reader.getFormatName().toLowerCase(Locale.ROOT);
                if(!List.of("png","jpeg","jpg","gif").contains(format)) throw new IllegalArgumentException("preview_format");
                reader.setInput(stream);
                int width=reader.getWidth(0),height=reader.getHeight(0),frames=1;
                if(format.equals("gif")) {
                    frames=reader.getNumImages(true);
                    if(reader.getStreamMetadata()!=null) {
                        var logical=PreviewAnimation.child(reader.getStreamMetadata().getAsTree("javax_imageio_gif_stream_1.0"),"LogicalScreenDescriptor");
                        width=PreviewAnimation.number(logical,"logicalScreenWidth",width);height=PreviewAnimation.number(logical,"logicalScreenHeight",height);
                    }
                }
                if(width<1 || height<1) throw new IllegalArgumentException("preview_dimensions");
                if(frames<1) throw new IllegalArgumentException("preview_frames");
                PreviewInfo info=new PreviewInfo(format.equals("jpeg")?"jpg":format,width,height,frames,bytes);
                if(info.getRenderError()!=null) {
                    if(requireRenderable) throw new IllegalArgumentException(info.getRenderError());
                    return info; // An existing remote preview can still be preserved locally without rendering it.
                }
                // Decode a small sample as well: a valid-looking header alone is not an image.
                var param=reader.getDefaultReadParam();int sample=Math.max(1,(Math.max(reader.getWidth(0),reader.getHeight(0))+255)/256);
                param.setSourceSubsampling(sample,sample,0,0);var image=reader.read(0,param);if(image==null) throw new IllegalArgumentException("preview_format");image.flush();
                return info;
            } finally {reader.dispose();}
        } catch(javax.imageio.IIOException e) {throw new IllegalArgumentException("preview_format",e);}
    }
    static String savePreviewCopy(SteamWorkshopItem item,PreviewDownload download) throws Exception {
        if(!download.getState().equals("loaded") || !Objects.equals(item.getID(),download.itemId)) throw new IllegalArgumentException("preview_not_loaded");
        byte[] data=Files.readAllBytes(download.file);Path base=root(item).toRealPath();
        for(int i=1;i<10000;i++) {
            String name="workshop-preview"+(i==1?"":"-"+i)+"."+download.info.format;
            Path target=base.resolve(name);
            if(Files.exists(target,LinkOption.NOFOLLOW_LINKS)) {
                if(Files.isSymbolicLink(target) || !target.toRealPath().startsWith(base) || !Files.isRegularFile(target)) continue;
                if(Files.size(target)==data.length && Arrays.equals(data,Files.readAllBytes(target))) return name;
                continue;
            }
            Path staged=Files.createTempFile(base,".mod-studio-preview-",".tmp");
            try {
                Files.write(staged,data);
                try {Files.move(staged,target);} catch(FileAlreadyExistsException e) {continue;}
                return name;
            } finally {Files.deleteIfExists(staged);}
        }
        throw new IllegalStateException("preview_save_failed");
    }
    static Path assetPath(SteamWorkshopItem item,String relative) throws Exception {
        Path base=root(item).toRealPath(),path=base.resolve(relative).normalize();
        if(!path.startsWith(base)) throw new IllegalArgumentException("outside_package");
        Path logical=base.relativize(path);
        if(logical.getNameCount()>0 && logical.getName(0).toString().equals("Contents")) {
            path=Path.of(item.getContentFolder());
            if(logical.getNameCount()>1)path=path.resolve(logical.subpath(1,logical.getNameCount()));
        }
        Path real=path.toRealPath();
        if(!real.startsWith(base)) throw new IllegalArgumentException("outside_package");
        return real;
    }
    static ArrayList<PackageEntry> listAssets(SteamWorkshopItem item,String relative) throws Exception {
        Path base=root(item).toRealPath(),dir=assetPath(item,relative);
        boolean release=Path.of(item.getContentFolder()).getFileName().toString().equals("Contents.release");
        ArrayList<PackageEntry> result=new ArrayList<>();
        try(var files=Files.list(dir)) {
            for(Path file:files.toList()) {
                String name=file.getFileName().toString();
                if(name.equals(".git")||name.equals(".build")) continue;
                if(dir.equals(base)&&release&&name.equals("Contents"))continue;
                String path=base.relativize(file).toString().replace('\\','/');
                if(release&&(path.equals("Contents.release")||path.startsWith("Contents.release/"))) {
                    path="Contents"+path.substring("Contents.release".length());
                    if(dir.equals(base))name="Contents (release)";
                }
                boolean directory=false,selectable=false;String reason="preview_format";long size=0;
                try {
                    Path safe=assetPath(item,path);directory=Files.isDirectory(safe);
                    if(directory) reason="";
                    else {
                        size=Files.size(safe);
                        if(name.toLowerCase(Locale.ROOT).matches(".*\\.(png|jpe?g|gif)")) {checkPreview(safe);selectable=true;reason="";}
                    }
                } catch(Exception e) {reason=e.getMessage();}
                result.add(new PackageEntry(name,path,directory,selectable,size,reason));
            }
        }
        result.sort(Comparator.comparing((PackageEntry e)->!e.directory).thenComparing(e->e.name,String.CASE_INSENSITIVE_ORDER));
        return result;
    }
    static ArrayList<String> dependencies(SteamWorkshopItem item) throws Exception {
        Path mods=Path.of(item.getContentFolder()).resolve("mods");
        Set<String> own=new HashSet<>(),required=new LinkedHashSet<>(),workshopIds=new LinkedHashSet<>();
        if(!Files.isDirectory(mods)) return new ArrayList<>();
        try(var folders=Files.list(mods)) {
            for(Path folder:folders.filter(Files::isDirectory).toList()) {
                var mod=ChooseGameInfo.readModInfo(folder.toString());
                if(mod!=null) {
                    own.add(mod.getId());
                    if(mod.getRequire()!=null) for(String id:mod.getRequire()) required.add(id.startsWith("\\")?id.substring(1):id);
                }
            }
        }
        required.removeAll(own);
        for(String id:required) {
            var mod=ChooseGameInfo.getModDetails(id);
            if(mod==null) continue;
            String workshop=mod.getWorkshopID();
            // A staged local package can override the installed Steam copy in the game's lookup.
            if((workshop==null || workshop.isBlank()) && "Workshop".equals(mod.getSource())) {
                Path metadata=Path.of(mod.dir).toAbsolutePath().getParent().getParent().getParent().resolve("workshop.txt");
                if(Files.isRegularFile(metadata)) for(String line:Files.readAllLines(metadata,StandardCharsets.UTF_8)) {
                    String value=line.trim();if(value.startsWith("id=")) {workshop=value.substring(3).trim();break;}
                }
            }
            if(workshop!=null && workshop.matches("[1-9][0-9]{0,19}") && !workshop.equals(item.getID())) {
                try {Long.parseUnsignedLong(workshop);workshopIds.add(workshop);} catch(NumberFormatException ignored) {}
            }
        }
        return new ArrayList<>(workshopIds);
    }
}
