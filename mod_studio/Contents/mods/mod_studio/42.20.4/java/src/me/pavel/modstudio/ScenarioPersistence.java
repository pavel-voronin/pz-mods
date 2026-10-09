package me.pavel.modstudio;

import java.io.*;
import java.nio.file.*;
import java.util.*;

/** Native save/load acceptance in a runner-owned profile. Never opens a user's
 * ordinary cache/save: both launch ownership and the active native path match. */
final class ScenarioPersistence {
    record Profile(Path directory,String mode,String world) {}
    static String mode(Map<String,Object> definition)throws IOException {
        if(!definition.containsKey("persistence"))return "";
        var values=ScenarioJson.object(definition.get("persistence"));String mode=ScenarioJson.string(values,"mode");
        if(!Set.of("new","resume").contains(mode)||!Set.of("mode","readOnly").containsAll(values.keySet())||values.containsKey("readOnly")&&(!(values.get("readOnly") instanceof Boolean)||!mode.equals("resume")))throw new IllegalArgumentException("Persistence requires mode new or resume; readOnly is a resume boolean");
        if(definition.containsKey("multiplayer")||Boolean.TRUE.equals(definition.get("manual"))||definition.get("repeats") instanceof Number n&&n.doubleValue()!=1)throw new IllegalArgumentException("Persistent acceptance requires one owned single-player run");
        return mode;
    }
    static Map<String,Object> read(Path file)throws IOException {
        if(Files.size(file)>8192)throw new IOException("Oversized profile record");return ScenarioJson.parse(Files.readString(file));
    }
    static Profile open(Map<String,Object> definition,Path output,Path cache,String profileProperty,String token)throws IOException {
        String mode=mode(definition);if(mode.isEmpty()){if(!profileProperty.isEmpty())throw new IOException("Unexpected persistent profile");return null;}
        Path artifacts=output.toRealPath().getParent(),profile=Path.of(profileProperty).toRealPath();
        if(!profile.startsWith(artifacts)||artifacts.relativize(profile).getNameCount()!=2||!profile.getFileName().toString().equals("native-profile")||!profile.getParent().getFileName().toString().matches("[0-9]{8}-T[0-9]{6}Z-[a-f0-9]{32}")||!profile.equals(cache.toRealPath()))throw new IOException("Native cache is not the owned scenario profile");
        var owner=read(profile.resolve("profile-owner.json"));
        if(!(owner.get("schema") instanceof Number schema)||schema.doubleValue()!=1||!token.equals(owner.get("token"))||!profile.toString().equals(owner.get("profile")))throw new IOException("Profile ownership record mismatch");
        var launch=read(profile.getParent().resolve("launch.json"));if(!profile.toString().equals(launch.get("nativeProfile"))||!token.equals(launch.get("profileToken")))throw new IOException("Profile launch ownership mismatch");
        String world="";
        if(mode.equals("resume")){
            var saved=read(profile.resolve("native-save.json"));world=ScenarioJson.string(saved,"world");
            if(!world.matches("[A-Za-z0-9_-]{1,128}")||!"Sandbox".equals(saved.get("gameMode"))||!profile.toString().equals(saved.get("profile"))||!Boolean.TRUE.equals(saved.get("nativeSave")))throw new IOException("No accepted native Sandbox save in profile");
            if(!Files.isRegularFile(profile.resolve("Saves/Sandbox").resolve(world).resolve("map_ver.bin")))throw new IOException("Native saved world is missing");
        }else if(!profile.getParent().equals(output.toRealPath()))throw new IOException("New persistent world requires this run's fresh profile");
        return new Profile(profile,mode,world);
    }
    static boolean current(Profile profile,Path cache,Path save){
        try{return profile!=null&&profile.directory().equals(cache.toRealPath())&&save.toRealPath().startsWith(profile.directory().resolve("Saves/Sandbox"));}
        catch(IOException invalid){return false;}
    }
    static boolean packageMatches(Path version,Path jar,String hash)throws IOException {
        Path loaded=version.toRealPath(),expected=jar.toRealPath();
        if(!expected.startsWith(loaded))return false;
        try(var input=Files.newInputStream(expected)){
            var digest=java.security.MessageDigest.getInstance("SHA-256");var bytes=new byte[65536];int count;
            while((count=input.read(bytes))!=-1)digest.update(bytes,0,count);
            return HexFormat.of().formatHex(digest.digest()).equals(hash);
        }catch(java.security.NoSuchAlgorithmException impossible){throw new IllegalStateException(impossible);}
    }
    static void saved(Profile profile,String world,Path save)throws IOException {
        if(!current(profile,profile.directory(),save)||!world.matches("[A-Za-z0-9_-]{1,128}")||!save.toRealPath().equals(profile.directory().resolve("Saves/Sandbox").resolve(world).toRealPath()))throw new IOException("Native save identity escaped profile");
        if(Files.size(save.resolve("map_ver.bin"))==0||Files.size(save.resolve("map.bin"))==0)throw new IOException("Native save files are incomplete");
        var record=new LinkedHashMap<String,Object>();record.put("schema",1);record.put("profile",profile.directory().toString());record.put("world",world);record.put("gameMode","Sandbox");record.put("nativeSave",true);record.put("utc",java.time.Instant.now().toString());
        Path temporary=profile.directory().resolve("native-save.tmp");Files.writeString(temporary,ScenarioJson.write(record));Files.move(temporary,profile.directory().resolve("native-save.json"),StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);
    }
}
