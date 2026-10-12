package me.pavel.modstudio;

import java.nio.ByteBuffer;
import java.nio.file.*;
import java.util.*;
import java.util.zip.CRC32;
import zombie.GameTime;
import zombie.characters.IsoPlayer;
import zombie.core.Core;
import zombie.iso.*;
import zombie.iso.weather.ClimateManager;

/** Native serialization of a bounded visual scene, without saving the scenario world. */
final class ScenarioRenderSnapshot {
    static void write(Path output,int x,int y,int z)throws Exception {
        Files.createDirectories(output.resolve("chunks"));
        var cell=IsoWorld.instance.currentCell;var player=IsoPlayer.getInstance();var map=cell.chunkMap[player.getPlayerNum()];
        var chunks=new ArrayList<List<Integer>>();
        for(var chunk:map.getChunks())if(chunk!=null&&chunk.loaded){
            ByteBuffer buffer=chunk.Save(ByteBuffer.allocate(65536),new CRC32(),false);
            Files.write(output.resolve("chunks/"+chunk.wx+"_"+chunk.wy+".bin"),Arrays.copyOf(buffer.array(),buffer.position()));
            chunks.add(List.of(chunk.wx,chunk.wy));
        }
        var climate=ClimateManager.getInstance();var floats=new ArrayList<Float>();var colors=new ArrayList<List<Float>>();
        for(int i=0;i<ClimateManager.FLOAT_MAX;i++)floats.add(climate.getClimateFloat(i).getFinalValue());
        for(int i=0;i<ClimateManager.COLOR_MAX;i++){
            var color=climate.getClimateColor(i).getFinalValue();var a=color.getExterior();var b=color.getInterior();
            colors.add(List.of(a.r,a.g,a.b,a.a,b.r,b.g,b.b,b.a));
        }
        var camera=IsoCamera.cameras[player.getPlayerNum()];var time=GameTime.getInstance();
        var state=new LinkedHashMap<String,Object>();state.put("schema",1);state.put("gameVersion",Core.getInstance().getVersionNumber());
        state.put("origin",List.of(x,y,z));state.put("chunks",chunks);state.put("chunkGridWidth",IsoChunkMap.chunkGridWidth);
        state.put("player",List.of(player.getX(),player.getY(),player.getZ()));state.put("forward",List.of(player.getForwardDirection().x,player.getForwardDirection().y));
        state.put("camera",List.of(camera.offX,camera.offY,camera.zoom));state.put("width",Core.getInstance().getScreenWidth());state.put("height",Core.getInstance().getScreenHeight());
        state.put("date",List.of(time.getYear(),time.getMonth(),time.getDay()));state.put("hour",time.getTimeOfDay());state.put("climateFloats",floats);state.put("climateColors",colors);
        ByteBuffer visual=ByteBuffer.allocate(1024*1024);player.getHumanVisual().save(visual);state.put("humanVisual",Base64.getEncoder().encodeToString(Arrays.copyOf(visual.array(),visual.position())));
        ByteBuffer items=ByteBuffer.allocate(1024*1024);var itemVisuals=new zombie.core.skinnedmodel.visual.ItemVisuals();player.getItemVisuals(itemVisuals);itemVisuals.save(items);state.put("itemVisuals",Base64.getEncoder().encodeToString(Arrays.copyOf(items.array(),items.position())));
        state.put("female",player.isFemale());
        var coreOptions=new LinkedHashMap<String,String>();for(int i=0;i<Core.getInstance().getOptionCount();i++){var option=Core.getInstance().getOptionByIndex(i);coreOptions.put(option.getName(),option.getValueAsString());}state.put("coreOptions",coreOptions);
        var debugOptions=new LinkedHashMap<String,String>();for(int i=0;i<zombie.debug.DebugOptions.instance.getOptionCount();i++){var option=zombie.debug.DebugOptions.instance.getOptionByIndex(i);debugOptions.put(option.getName(),option.getValueAsString());}state.put("debugOptions",debugOptions);
        state.put("fboRenderChunk",zombie.core.PerformanceSettings.fboRenderChunk);state.put("newRoofHiding",zombie.core.PerformanceSettings.newRoofHiding);
        state.put("textureCompression",zombie.core.textures.TextureID.useCompressionOption);
        var cameraFields=new LinkedHashMap<String,Number>();for(var field:camera.getClass().getFields())if(!java.lang.reflect.Modifier.isStatic(field.getModifiers())&&(field.getType()==float.class||field.getType()==int.class))cameraFields.put(field.getName(),(Number)field.get(camera));state.put("cameraFields",cameraFields);
        ByteBuffer stats=ByteBuffer.allocate(4096);player.getStats().save(stats);state.put("stats",Base64.getEncoder().encodeToString(Arrays.copyOf(stats.array(),stats.position())));
        var vision=new LinkedHashMap<String,Number>();for(String name:List.of("lumaInvertedLerp","visionConeLerp")){var field=LightingJNI.class.getDeclaredField(name);field.setAccessible(true);vision.put(name,(Number)field.get(null));}state.put("vision",vision);
        var visibility=new ArrayList<List<Object>>();for(var chunk:map.getChunks())if(chunk!=null)for(int level=chunk.minLevel;level<=chunk.maxLevel;level++)for(int yy=0;yy<8;yy++)for(int xx=0;xx<8;xx++){var square=chunk.getGridSquare(xx,yy,level);if(square!=null)visibility.add(List.of(square.x,square.y,square.z,square.lighting[0].bSeen(),square.lighting[0].bCanSee(),square.lighting[0].bCouldSee(),square.lighting[0].darkMulti()));}state.put("visibility",visibility);
        var animation=player.getAnimationPlayer();var bones=new ArrayList<List<Float>>();
        for(int i=0;i<animation.getModelTransformsCount();i++){var buffer=java.nio.FloatBuffer.allocate(16);animation.getModelTransformAt(i).store(buffer);var values=new ArrayList<Float>();for(float value:buffer.array())values.add(value);bones.add(values);}state.put("bones",bones);state.put("animationAngle",animation.getAngle());
        state.put("mapCenter",List.of(map.worldX,map.worldY));
        try{var main=Class.forName("com.pavelvoronin.pz3d.Main");state.put("productionView",ScenarioJson.parse((String)main.getMethod("scenarioRenderView").invoke(null)));}catch(ClassNotFoundException absent){}
        try(var stream=new java.io.DataOutputStream(Files.newOutputStream(output.resolve("time.bin")))){time.save(stream);}
        Files.writeString(output.resolve("state.json"),ScenarioJson.write(state));
    }
    private ScenarioRenderSnapshot(){}
}
