'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import * as THREE from 'three';
import { snapshotGifCamera, fitGifViewport } from './gif-camera';
import {prepareLootParts} from './loot-components';
import {makeLootHull,boxVertices,lootBottom,type LootHull} from './loot-collider';
import { GENERATION_STORAGE_KEY, defaultGenerationLocks, decodeGenerationSettings, encodeGenerationSettings, type GenerationSettings } from './generation-settings';
import { captureRigAttachment, updateRigAttachment, mountAxeOnBack, updateSurfaceAttachment } from './rig-attachment';
import { TransformControls } from 'three/examples/jsm/controls/TransformControls.js';
import { sampleCloth, type ClothBake, type ClothBakeInput, type Capsule } from './cloth-physics';
import ClothWorker from './cloth-worker?worker';
import QuickWorker from './cloth-worker?worker';
import { clothSurface } from './cloth-surface';
import { clothReleaseVelocities } from './cloth-release';
import { clothSceneKey, decodeBlenderCache } from './blender-cache';
import { clothNormals } from './cloth-normals';
import { type QuickPreview } from './cloth-rigid-preview';
import { clothPreviewLabels, invalidateClothPreview, type ClothPreviewState } from './cloth-preview-state';
import { type LootBake, type LootBodyInput } from './loot-physics';
import { defaultDropPoints, garmentReleaseFan, DROP_LAYOUT_KEY, decodeDropLayout, clampDropRadius, dropDiskSample } from './scene-layout';
import { sequencePropDefinitions, sequencePropLabels, sequencePropOptions, generatePocketLoot, normalizePocketId, type SequencePropKind } from './pocket-loot';
import { rigAssetPath, rigAssetSource, type ModelSet } from './pz-model-assets';
import {
  cloneObjectWithMaterial,
  cloneRigWithMaterial,
  compareRigSkeletons,
  createRigModel,
  disposeRigModel,
  loadObjectFromFbx,
  loadObjectFromPzX,
  type HandleKey,
  type PoseJson,
  type PzPoseState,
  PzRagdollPose,
  ragdollHandles,
  rigDiagnosticSegments,
  rigJointPositions,
  type RigJson,
  type RigModel,
  skinRigModel,
} from './pz-rig';
import {
  actionAt,
  buildSequence,
  smoothstep,
} from './sequence';
import catalogJson from './pz-catalog.json';

type Sex = 'm' | 'f';
type PoseKey = string;
type HairKey = string;
type GarmentType = keyof typeof catalogJson.garments;
type RigName = string;
type TransformMode = 'translate' | 'rotate';
type RandomLockKey = 'floor' | 'pose' | 'body' | 'hair' | 'hairColor' | 'clothing' | 'loot';
type DropPointKind = 'weapon' | 'clothing' | 'valuables';
type DropPointPosition = { x: number; z: number; radius:number };
type DropPointPositions = Record<DropPointKind, DropPointPosition>;

type Selection = {
  body: string;
  pose: PoseKey;
  hair: HairKey;
  hairColor: string;
};

type Garment = { id: number; type: GarmentType; variant: string; fabricStiffness?: number };
type LayeredGarment = Garment & { level: number };
type LootItem = { id: number; kind: SequencePropKind; layer: number };
type Option = { value: string; label: string };
type GifExportResult = { blob: Blob; frames: number; paletteColors: number };
type SkeletonDiagnostic = {
  id: string;
  label: string;
  color: string;
  model: RigName;
  bones: number;
  missingBones: number;
  maxJointDeltaMm: number;
  maxRotationDeltaDeg: number;
  posedJointDeltaMm: number;
  instanceRotationDeg: number;
  detached?: boolean;
};
type HairOption = Option & { model: string; texture: string };
type GarmentVariant = Option & {
  texture: string;
  model?: string;
  masks?: number[];
  maskFolder?: string;
  underlayMaskFolder?: string;
  hatCategory?: string;
};
type GarmentDefinition = {
  label: string;
  model: string;
  zones: string[];
  wearOrder: number;
  variants: Record<Sex, GarmentVariant[]>;
};

const bodyOptions: Option[] = [
  { value: 'm-1', label: 'Ванильный — мужской зомби 1' },
  { value: 'm-2', label: 'Ванильный — мужской зомби 2' },
  { value: 'm-3', label: 'Ванильный — мужской зомби 3' },
  { value: 'm-4', label: 'Ванильный — мужской зомби 4' },
  { value: 'f-1', label: 'Ванильный — женский зомби 1' },
  { value: 'f-2', label: 'Ванильный — женский зомби 2' },
  { value: 'f-3', label: 'Ванильный — женский зомби 3' },
  { value: 'f-4', label: 'Ванильный — женский зомби 4' },
];


const poseOptions: Option[] = [
  { value: 'back', label: 'На спине' },
  { value: 'front', label: 'На животе' },
  { value: 'hit-back', label: 'Удар, на спине' },
  { value: 'landing', label: 'Падение' },
  { value: 'getup-back-start', label: 'Подъём со спины: начало' },
  { value: 'getup-front-start', label: 'Подъём с живота: начало' },
  { value: 'death-running', label: 'Смерть на бегу' },
  { value: 'death-walking', label: 'Смерть в движении' },
  { value: 'death-backward', label: 'Падение назад' },
  { value: 'floor-front', label: 'Лёжа на животе' },
  { value: 'fall-idle-2', label: 'После падения 2' },
  { value: 'fall-idle-3', label: 'После падения 3' },
  { value: 'fall-idle-4', label: 'После падения 4' },
  { value: 'scramble-back', label: 'Ползёт на спине' },
  { value: 'scramble-front', label: 'Ползёт на животе' },
  { value: 'sit-death', label: 'Смерть сидя' },
];

const floorOptions: Option[] = [
  { value: 'asphalt', label: 'Асфальт' },
  { value: 'asphalt-rough', label: 'Шероховатый асфальт' },
  { value: 'grass', label: 'Трава' },
  { value: 'grass-dry', label: 'Сухая трава' },
  { value: 'stone-path', label: 'Каменная дорожка' },
  { value: 'stone-path-light', label: 'Светлая каменная дорожка' },
  { value: 'soil', label: 'Земля' },
  { value: 'concrete', label: 'Бетон' },
  { value: 'sand', label: 'Песок' },
  { value: 'gravel', label: 'Гравий' },
  { value: 'tile-blue', label: 'Голубая плитка' },
  { value: 'tile-slate', label: 'Сланцевая плитка' },
  { value: 'tile-beige', label: 'Бежевая плитка' },
  { value: 'brick-red', label: 'Красный кирпич' },
  { value: 'brick-black', label: 'Чёрный кирпич' },
  { value: 'wood', label: 'Доски' },
  { value: 'wood-dark', label: 'Тёмное дерево' },
  { value: 'parquet', label: 'Паркет' },
  { value: 'wood-white', label: 'Белёные доски' },
];

const handleLabels: Record<HandleKey, string> = {
  pelvis: 'Таз', waist: 'Поясница', chest: 'Грудь', neck: 'Шея', head: 'Голова',
  leftShoulder: 'Левое плечо', leftElbow: 'Левый локоть', leftHand: 'Левая кисть',
  rightShoulder: 'Правое плечо', rightElbow: 'Правый локоть', rightHand: 'Правая кисть',
  leftHip: 'Левое бедро', leftKnee: 'Левое колено', leftFoot: 'Левая стопа',
  rightHip: 'Правое бедро', rightKnee: 'Правое колено', rightFoot: 'Правая стопа',
};

const hairOptions = catalogJson.hair as Record<Sex, HairOption[]>;
const garmentDefinitions = catalogJson.garments as Record<GarmentType, GarmentDefinition>;
const garmentTypeOrder = Object.keys(garmentDefinitions) as GarmentType[];

const defaultCharacterMaskFolder = '/pz/masks/body-masks';
const characterMaskLeaves = [
  'Head', 'LeftArm', 'LeftHand', 'RightArm', 'RightHand', 'LeftLeg', 'LeftFoot',
  'RightLeg', 'RightFoot', 'Dress', 'Chest', 'Waist', 'Belt', 'Crotch',
] as const;
type CharacterMaskLeaf = (typeof characterMaskLeaves)[number];
const characterMaskParts: Record<number, readonly CharacterMaskLeaf[]> = {
  0: ['Head'],
  1: ['Chest', 'Waist'],
  2: ['Belt', 'Crotch'],
  3: ['LeftArm'],
  4: ['LeftHand'],
  5: ['RightArm'],
  6: ['RightHand'],
  7: ['LeftLeg'],
  8: ['LeftFoot'],
  9: ['RightLeg'],
  10: ['RightFoot'],
  11: ['Dress'],
  12: ['Chest'],
  13: ['Waist'],
  14: ['Belt'],
  15: ['Crotch'],
};

function hideCharacterParts(visible: Set<CharacterMaskLeaf>, parts: readonly number[]) {
  parts.forEach((part) => characterMaskParts[part]?.forEach((leaf) => visible.delete(leaf)));
}

function usesUnmaskedItemTexture(maskFolder: string) {
  return maskFolder === 'none' || maskFolder.includes('clothes-hat-masks');
}

const dropPointKinds: DropPointKind[] = ['weapon', 'clothing', 'valuables'];
const dropPointLabels: Record<DropPointKind, string> = {
  weapon: 'Оружие',
  clothing: 'Одежда',
  valuables: 'Ценности',
};
const dropPointColors: Record<DropPointKind, number> = {
  weapon: 0xff9d3f,
  clothing: 0x67d7ff,
  valuables: 0xf4df62,
};

const makeDefaultDropPoints = defaultDropPoints;

const initialSelection: Selection = {
  body: 'm-3',
  pose: 'front',
  hair: 'messy',
  hairColor: '#704322',
};

const initialGarments: Garment[] = [
  { id: 1, type: 'underpants', variant: 'male-boxers-white' },
  { id: 2, type: 'shirt', variant: 'tshirt-white' },
  { id: 3, type: 'trousers', variant: 'trousers-camo-dcu' },
];

const initialLootItems: LootItem[] = [
  { id: 1, kind: 'Base.Wallet_Male', layer: 0 },
  { id: 2, kind: 'Base.MoneyBundle', layer: 1 },
  { id: 3, kind: 'Base.CigarettePack', layer: 1 },
];

const defaultGenerationSettings: GenerationSettings<GarmentType> = {
  selection:initialSelection,modelSet:'tomb',garments:initialGarments,lootItems:initialLootItems,
  floor:'asphalt',locks:defaultGenerationLocks,lockedGarmentIds:[],addType:'shirt',addLootKind:'Base.Wallet_Male',
};
const generationCatalog = {
  bodies:bodyOptions.map(o=>o.value),poses:poseOptions.map(o=>o.value),floors:floorOptions.map(o=>o.value),
  hair:(sex:Sex)=>hairOptions[sex].map(o=>o.value),
  variants:(type:string,sex:Sex)=>Object.hasOwn(garmentDefinitions,type)?garmentDefinitions[type as GarmentType].variants[sex].map(o=>o.value):[],
  loot:(kind:string,sex:Sex)=>{
    const normalized=normalizePocketId(kind,sex);
    return normalized && Object.hasOwn(sequencePropDefinitions,normalized)?normalized:undefined;
  },
};

function randomItem<T>(items: readonly T[]) {
  return items[Math.floor(Math.random() * items.length)];
}

async function loadJson<T>(path: string) {
  const response = await fetch(path);
  if (!response.ok) throw new Error(`Не удалось загрузить ${path}: ${response.status}`);
  return response.json() as Promise<T>;
}

function loadLocalRig(name: RigName, sex: Sex, modelSet: ModelSet) {
  return loadJson<RigJson>(rigAssetPath(name, sex, modelSet));
}

function loadTexture(loader: THREE.TextureLoader, path: string) {
  return new Promise<THREE.Texture>((resolve, reject) => loader.load(path, resolve, undefined, reject));
}

function createMaterial(
  texture: THREE.Texture,
  color: THREE.ColorRepresentation = 0xffffff,
  flipY = false,
) {
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.flipY = flipY;
  texture.magFilter = THREE.NearestFilter;
  texture.minFilter = THREE.NearestFilter;
  return new THREE.MeshStandardMaterial({
    map: texture,
    color,
    // Project Zomboid's basicEffect.frag discards only texSample.w < 0.01.
    // A higher cutoff deletes the narrow masked wrist/ankle seams.
    alphaTest: 0.01,
    side: THREE.DoubleSide,
    roughness: 1,
    metalness: 0,
    flatShading: false,
  });
}

function selectedGarmentVariant(type: GarmentType, variant: string, sex: Sex) {
  const variants = garmentDefinitions[type].variants[sex];
  const selected = variants.find((option) => option.value === variant) ?? variants[0];
  if (!selected) throw new Error(`Нет текстур для ${type}/${sex}`);
  return selected;
}

function calculateLayers(garments: Garment[]) {
  const occupancy: Set<string>[] = [];
  const levelById = new Map<number, number>();
  garments
    .map((garment, index) => ({ garment, index }))
    .sort((a, b) => garmentDefinitions[a.garment.type].wearOrder - garmentDefinitions[b.garment.type].wearOrder || a.index - b.index)
    .forEach(({ garment }) => {
      const zones = garmentDefinitions[garment.type].zones;
      let level = occupancy.findIndex((used) => zones.every((zone) => !used.has(zone)));
      if (level < 0) {
        level = occupancy.length;
        occupancy.push(new Set());
      }
      zones.forEach((zone) => occupancy[level].add(zone));
      levelById.set(garment.id, level);
    });
  return garments.map((garment) => ({ ...garment, level: levelById.get(garment.id) ?? 0 }));
}

function LockButton({ locked, onChange, label }: { locked: boolean; onChange: () => void; label: string }) {
  return (
    <button
      className={`lock-button${locked ? ' locked' : ''}`}
      type="button"
      onClick={onChange}
      aria-label={`${locked ? 'Разблокировать' : 'Заблокировать'} ${label}`}
      title={locked ? 'Не менять при случайной генерации' : 'Разрешить случайную генерацию'}
    >{locked ? '🔒' : '🔓'}</button>
  );
}

function SelectControl({ label, value, options, onChange, wide = false, locked, onToggleLock }: {
  label: string;
  value: string;
  options: Option[];
  onChange: (value: string) => void;
  wide?: boolean;
  locked?: boolean;
  onToggleLock?: () => void;
}) {
  return (
    <div className={`field${wide ? ' wide' : ''}`}>
      <span className="field-title"><span>{label}</span>{onToggleLock && <LockButton locked={Boolean(locked)} onChange={onToggleLock} label={label} />}</span>
      <select aria-label={label} value={value} onChange={(event) => onChange(event.target.value)}>
        {options.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
      </select>
    </div>
  );
}

export default function Home() {
  const mountRef = useRef<HTMLDivElement>(null);
  const rendererRef = useRef<THREE.WebGLRenderer | null>(null);
  const sceneRef = useRef<THREE.Scene | null>(null);
  const cameraRef = useRef<THREE.OrthographicCamera | null>(null);
  const hairMaterialRef = useRef<THREE.MeshStandardMaterial | null>(null);
  const ragdollRef = useRef<PzRagdollPose | null>(null);
  const rigModelsRef = useRef<RigModel[]>([]);
  const handleMeshesRef = useRef<Partial<Record<HandleKey, THREE.Mesh>>>({});
  const ragdollEnabledRef = useRef(false);
  const lockedHandlesRef = useRef<Set<HandleKey>>(new Set());
  const selectedHandleRef = useRef<HandleKey | null>(null);
  const transformModeRef = useRef<TransformMode>('translate');
  const dropPointsVisibleRef = useRef(false);
  const selectedDropPointRef = useRef<DropPointKind | null>(null);
  const dropPointPositionsRef = useRef<DropPointPositions>(makeDefaultDropPoints());
  const dropPointMeshesRef = useRef<Partial<Record<DropPointKind, THREE.Group>>>({});
  const skeletonDebugVisibleRef = useRef(false);
  const skeletonDebugTargetRef = useRef('garment-0');
  const sequenceProgressRef = useRef(0);
  const sequenceScrubbingRef = useRef<number | null>(null);
  const playbackFrameRef = useRef<number | null>(null);
  const playingRef = useRef(false);
  const editorControllerRef = useRef<{
    setPhysics: (active: boolean) => void;
    resetMotion: () => void;
    refresh: () => void;
    setDropPointsVisible: (visible: boolean) => void;
    setDropPointPositions: (positions: DropPointPositions) => void;
    setSkeletonDebug: (visible: boolean, target: string) => void;
    setSequenceProgress: (progress: number) => void;
    calculateCloth: () => void;
    exportPhysicsSnapshot: () => void;
    importBlenderCache: (file: File) => Promise<void>;
    calculateBlender: () => Promise<void>;
    cancelCloth: () => void;
    showPreciseCloth: (precise: boolean) => void;
    exportGif: (
      targetBytes: number,
      onProgress: (message: string) => void,
      signal: AbortSignal,
    ) => Promise<GifExportResult>;
  } | null>(null);
  const exportAbortRef = useRef<AbortController | null>(null);
  const preservePoseOnReloadRef = useRef(false);
  const preservedPoseStateRef = useRef<PzPoseState | null>(null);
  const rotationRef = useRef(0);
  const cameraPanRef = useRef(0);
  const cameraPanLockedRef = useRef(false);
  const zoomRef = useRef(1);
  const nextGarmentIdRef = useRef(4);
  const nextLootIdRef = useRef(4);
  const [selection, setSelection] = useState(initialSelection);
  const [modelSet, setModelSet] = useState<ModelSet>('tomb');
  const [garments, setGarments] = useState(initialGarments);
  const [lootItems, setLootItems] = useState(initialLootItems);
  const [floor, setFloor] = useState('asphalt');
  const [ragdollEnabled, setRagdollEnabled] = useState(false);
  const [addType, setAddType] = useState<GarmentType>('shirt');
  const [addLootKind, setAddLootKind] = useState<SequencePropKind>('Base.Wallet_Male');
  const [selectedHandle, setSelectedHandle] = useState<HandleKey | null>(null);
  const [lockedHandles, setLockedHandles] = useState<Set<HandleKey>>(new Set());
  const [lockedGarmentIds, setLockedGarmentIds] = useState<Set<number>>(new Set());
  const [transformMode, setTransformMode] = useState<TransformMode>('translate');
  const [dropPointsVisible, setDropPointsVisible] = useState(false);
  const [selectedDropPoint, setSelectedDropPoint] = useState<DropPointKind | null>(null);
  const [skeletonDebugVisible, setSkeletonDebugVisible] = useState(false);
  const [skeletonDebugTarget, setSkeletonDebugTarget] = useState('garment-0');
  const [skeletonDiagnostics, setSkeletonDiagnostics] = useState<SkeletonDiagnostic[]>([]);
  const [cameraPanLocked, setCameraPanLocked] = useState(false);
  const [sequenceProgress, setSequenceProgress] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [loopPlayback, setLoopPlayback] = useState(false);
  const [simulationBusy, setSimulationBusy] = useState(true);
  const [simulationStatus, setSimulationStatus] = useState('Загрузка сцены…');
  const [clothMode, setClothMode] = useState<ClothPreviewState>('quick');
  const [clothMessage, setClothMessage] = useState('');
  const [exportOpen, setExportOpen] = useState(false);
  const [exportTargetMb, setExportTargetMb] = useState(1);
  const [exporting, setExporting] = useState(false);
  const [exportStatus, setExportStatus] = useState('');
  const [exportResult, setExportResult] = useState<(GifExportResult & { url: string }) | null>(null);
  const [exportPreviewVisible, setExportPreviewVisible] = useState(false);
  const [locks, setLocks] = useState<Record<RandomLockKey, boolean>>(defaultGenerationLocks);
  const [settingsLoaded,setSettingsLoaded] = useState(false);
  const [storageMessage,setStorageMessage] = useState('');
  const applyGenerationSettings = useCallback((settings:GenerationSettings<GarmentType>)=>{
    setSelection(settings.selection);setModelSet(settings.modelSet);setFloor(settings.floor);
    setGarments(settings.garments);setLootItems(settings.lootItems);
    setLocks(settings.locks);setLockedGarmentIds(new Set(settings.lockedGarmentIds));
    setAddType(settings.addType);setAddLootKind(settings.addLootKind);
    nextGarmentIdRef.current=Math.max(0,...settings.garments.map(g=>g.id))+1;
    nextLootIdRef.current=Math.max(0,...settings.lootItems.map(item=>item.id))+1;
  },[]);

  useEffect(()=>{
    try {
      dropPointPositionsRef.current=decodeDropLayout(localStorage.getItem(DROP_LAYOUT_KEY));
      applyGenerationSettings(decodeGenerationSettings(localStorage.getItem(GENERATION_STORAGE_KEY),defaultGenerationSettings,generationCatalog));
    } catch {setStorageMessage('Хранилище браузера недоступно: настройки сохраняются только до закрытия страницы.');}
    setSettingsLoaded(true);
  },[applyGenerationSettings]);

  const saveDropLayout = useCallback(()=>{
    try {localStorage.setItem(DROP_LAYOUT_KEY,JSON.stringify({version:1,points:dropPointPositionsRef.current}));}
    catch {setStorageMessage('Не удалось сохранить точки сброса в браузере.');}
  },[]);

  useEffect(()=>{
    // Hydrate first: initial server defaults must never overwrite saved settings.
    if(!settingsLoaded)return;
    try {
      localStorage.setItem(GENERATION_STORAGE_KEY,encodeGenerationSettings({selection,modelSet,garments,lootItems,floor,locks,
        lockedGarmentIds:[...lockedGarmentIds],addType,addLootKind}));
      setStorageMessage('');
    } catch {setStorageMessage('Не удалось сохранить настройки в браузере.');}
  },[settingsLoaded,selection,modelSet,garments,lootItems,floor,locks,lockedGarmentIds,addType,addLootKind]);

  const sex = selection.body.slice(0, 1) as Sex;
  const bodyVariant = selection.body.slice(2);
  const layeredGarments = useMemo(() => calculateLayers(garments), [garments]);
  const garmentLayers = useMemo(() => {
    const groups = new Map<number, LayeredGarment[]>();
    layeredGarments.forEach((garment) => {
      const group = groups.get(garment.level) ?? [];
      group.push(garment);
      groups.set(garment.level, group);
    });
    return [...groups.entries()].sort(([a], [b]) => a - b);
  }, [layeredGarments]);
  const lootLayerOptions = useMemo<Option[]>(() => (
    garmentLayers.length > 0
      ? garmentLayers.map(([level]) => ({ value: String(level), label: `Слой ${level + 1}` }))
      : [{ value: '0', label: 'Слой 1' }]
  ), [garmentLayers]);
  const normalizedLootItems = useMemo(() => {
    const levels = new Set(garmentLayers.map(([level]) => level));
    const fallback = garmentLayers[0]?.[0] ?? 0;
    return lootItems.flatMap((item) => {
      const kind=normalizePocketId(item.kind,sex);
      return kind ? [{...item,kind,layer:levels.has(item.layer)?item.layer:fallback}] : [];
    });
  }, [garmentLayers, lootItems, sex]);
  const sequenceActions = useMemo(
    () => buildSequence(garmentLayers.map(([level]) => level)),
    [garmentLayers],
  );
  const activeSequenceAction = actionAt(sequenceActions, sequenceProgress);
  const sequenceDurationSeconds = 0.45 + 0.65 + garmentLayers.length * 1.1 + 1.4;
  const sequenceDurationMs = sequenceDurationSeconds * 1000;

  useEffect(() => () => {
    if (exportResult) URL.revokeObjectURL(exportResult.url);
  }, [exportResult]);

  useEffect(() => () => exportAbortRef.current?.abort(), []);

  const availableGarmentTypes = useMemo<Option[]>(() => {
    return garmentTypeOrder
      .filter((type) => garmentDefinitions[type].variants[sex].length > 0)
      .map((type) => ({ value: type, label: garmentDefinitions[type].label }));
  }, [sex]);

  const render = useCallback(() => {
    if (rendererRef.current && sceneRef.current && cameraRef.current) {
      rendererRef.current.render(sceneRef.current, cameraRef.current);
    }
  }, []);

  const scrubSequence = useCallback((progress: number) => {
    const clamped = Math.max(0, Math.min(1, progress));
    sequenceProgressRef.current = clamped;
    setSequenceProgress(clamped);
    editorControllerRef.current?.setSequenceProgress(clamped);
  }, []);

  const stopPlayback = useCallback(() => {
    playingRef.current = false;
    if (playbackFrameRef.current !== null) {
      cancelAnimationFrame(playbackFrameRef.current);
      playbackFrameRef.current = null;
    }
    setPlaying(false);
  }, []);

  const togglePlayback = useCallback(() => {
    if (playingRef.current) {
      stopPlayback();
      return;
    }
    if (sequenceProgressRef.current >= 0.9999) scrubSequence(0);
    playingRef.current = true;
    setPlaying(true);
  }, [scrubSequence, stopPlayback]);

  useEffect(() => {
    if (!playing) return;
    playingRef.current = true;
    const startedAt = performance.now();
    const startProgress = sequenceProgressRef.current;
    const tick = (time: number) => {
      if (!playingRef.current) return;
      const elapsedProgress = (time - startedAt) / sequenceDurationMs;
      const absoluteProgress = startProgress + elapsedProgress;
      if (absoluteProgress >= 1 && !loopPlayback) {
        scrubSequence(1);
        stopPlayback();
        return;
      }
      scrubSequence(loopPlayback ? absoluteProgress % 1 : absoluteProgress);
      playbackFrameRef.current = requestAnimationFrame(tick);
    };
    playbackFrameRef.current = requestAnimationFrame(tick);
    return () => {
      if (playbackFrameRef.current !== null) cancelAnimationFrame(playbackFrameRef.current);
      playbackFrameRef.current = null;
    };
  }, [loopPlayback, playing, scrubSequence, stopPlayback, sequenceDurationMs]);

  useEffect(() => {
    ragdollEnabledRef.current = ragdollEnabled;
    Object.values(handleMeshesRef.current).forEach((handle) => {
      if (handle) handle.visible = ragdollEnabled;
    });
    rendererRef.current?.domElement.classList.toggle('ragdoll-active', ragdollEnabled);
    editorControllerRef.current?.setPhysics(ragdollEnabled);
    editorControllerRef.current?.refresh();
    render();
  }, [ragdollEnabled, render]);

  useEffect(() => {
    lockedHandlesRef.current = lockedHandles;
    editorControllerRef.current?.refresh();
  }, [lockedHandles]);

  useEffect(() => {
    selectedHandleRef.current = selectedHandle;
    transformModeRef.current = transformMode;
    editorControllerRef.current?.refresh();
  }, [selectedHandle, transformMode]);

  useEffect(() => {
    dropPointsVisibleRef.current = dropPointsVisible;
    if (!dropPointsVisible) {
      selectedDropPointRef.current = null;
    }
    editorControllerRef.current?.setDropPointsVisible(dropPointsVisible);
    editorControllerRef.current?.refresh();
  }, [dropPointsVisible]);

  useEffect(() => {
    selectedDropPointRef.current = selectedDropPoint;
    editorControllerRef.current?.refresh();
  }, [selectedDropPoint]);

  useEffect(() => {
    skeletonDebugVisibleRef.current = skeletonDebugVisible;
    skeletonDebugTargetRef.current = skeletonDebugTarget;
    editorControllerRef.current?.setSkeletonDebug(skeletonDebugVisible, skeletonDebugTarget);
    render();
  }, [render, skeletonDebugTarget, skeletonDebugVisible]);

  useEffect(() => {
    hairMaterialRef.current?.color.set(selection.hairColor);
    render();
  }, [render, selection.hairColor]);

  const resetRagdoll = useCallback(() => {
    stopPlayback();
    editorControllerRef.current?.setPhysics(false);
    ragdollEnabledRef.current = false;
    setRagdollEnabled(false);
    selectedHandleRef.current = null;
    setSelectedHandle(null);
    lockedHandlesRef.current = new Set();
    setLockedHandles(new Set());
    scrubSequence(0);
    const pose = ragdollRef.current;
    if (!pose) return;
    preservePoseOnReloadRef.current = false;
    preservedPoseStateRef.current = null;
    pose.reset();
    editorControllerRef.current?.resetMotion();
    ragdollHandles.forEach((key) => handleMeshesRef.current[key]?.position.copy(pose.getHandlePosition(key)));
    render();
  }, [render, stopPlayback, scrubSequence]);

  const toggleLock = (key: RandomLockKey) => {
    setLocks((current) => ({ ...current, [key]: !current[key] }));
  };

  const toggleSelectedHandleLock = () => {
    const handle = selectedHandleRef.current;
    if (!handle) return;
    setLockedHandles((current) => {
      const next = new Set(current);
      if (next.has(handle)) next.delete(handle);
      else next.add(handle);
      lockedHandlesRef.current = next;
      return next;
    });
  };

  const toggleCameraPanLock = () => {
    setCameraPanLocked((current) => {
      const next = !current;
      cameraPanLockedRef.current = next;
      return next;
    });
  };

  const toggleDropPoints = () => {
    const next = !dropPointsVisibleRef.current;
    dropPointsVisibleRef.current = next;
    setDropPointsVisible(next);
    if (!next) {
      selectedDropPointRef.current = null;
      setSelectedDropPoint(null);
    }
  };

  const toggleSkeletonDebug = () => {
    setSkeletonDebugVisible((current) => !current);
  };

  const resetGenerationSettings = () => {
    resetRagdoll();
    applyGenerationSettings(structuredClone(defaultGenerationSettings));
    // Write only our own key; never clear unrelated browser data.
    try {localStorage.setItem(GENERATION_STORAGE_KEY,encodeGenerationSettings(defaultGenerationSettings));setStorageMessage('');}
    catch {setStorageMessage('Не удалось сохранить сброс настроек в браузере.');}
  };

  const selectSkeletonDebugTarget = (target: string) => {
    skeletonDebugTargetRef.current = target;
    setSkeletonDebugTarget(target);
    editorControllerRef.current?.setSkeletonDebug(true, target);
  };

  useEffect(() => {
    if (!mountRef.current || !settingsLoaded) return;
    stopPlayback();
    exportAbortRef.current?.abort();
    setExportResult(null);
    setSimulationBusy(true);
    setSimulationStatus('Загрузка сцены…');
    setClothMode(invalidateClothPreview);
    setClothMessage('');
    const mount = mountRef.current;
    let cancelled = false;
    let detachInteractions = () => {};
    let disposeLoaded = () => {};

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x111311);
    const camera = new THREE.OrthographicCamera(-1.22, 1.22, 1.22, -1.22, 0.01, 100);
    const cameraOrigin = new THREE.Vector3(6, 4.899, 6);
    const cameraGroundDirection = new THREE.Vector3(1, 0, 1).normalize();
    const applyCameraPan = (pan: number) => {
      const target = cameraGroundDirection.clone().multiplyScalar(pan);
      const viewRotation = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), -rotationRef.current);
      target.applyQuaternion(viewRotation);
      camera.position.copy(cameraOrigin).applyQuaternion(viewRotation).add(target);
      camera.lookAt(target);
    };
    applyCameraPan(cameraPanRef.current);
    camera.zoom = zoomRef.current;
    camera.updateProjectionMatrix();
    scene.add(new THREE.HemisphereLight(0xd9ded2, 0x24271f, 1.8));
    const keyLight = new THREE.DirectionalLight(0xffefd8, 2.25);
    keyLight.position.set(0, 8, 0);
    keyLight.castShadow = true;
    keyLight.shadow.mapSize.set(4096, 4096);
    keyLight.shadow.camera.near = 0.1;
    keyLight.shadow.camera.far = 16;
    keyLight.shadow.camera.left = -4;
    keyLight.shadow.camera.right = 4;
    keyLight.shadow.camera.top = 4;
    keyLight.shadow.camera.bottom = -4;
    keyLight.shadow.bias = -0.00008;
    keyLight.shadow.normalBias = 0.0015;
    keyLight.target.position.set(0, 0, 0);
    scene.add(keyLight, keyLight.target);
    const fillLight = new THREE.DirectionalLight(0x8fa7bf, 0.55);
    fillLight.position.set(5, 3, -4);
    scene.add(fillLight);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFShadowMap;
    renderer.domElement.setAttribute('aria-label', 'Сцена');
    renderer.domElement.classList.toggle('ragdoll-active', ragdollEnabledRef.current);
    mount.replaceChildren(renderer.domElement);
    rendererRef.current = renderer;
    sceneRef.current = scene;
    cameraRef.current = camera;

    const resize = () => {
      const stage = mount.parentElement!;
      const { width, height } = fitGifViewport(stage.clientWidth, stage.clientHeight);
      mount.style.width = `${width}px`;
      mount.style.height = `${height}px`;
      const halfHeight = 1.22;
      const halfWidth = halfHeight * (width / height);
      camera.left = -halfWidth;
      camera.right = halfWidth;
      camera.top = halfHeight;
      camera.bottom = -halfHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(width, height, false);
      render();
    };
    const resizeObserver = new ResizeObserver(resize);
    resizeObserver.observe(mount.parentElement!);
    resize();

    const garmentAssets = layeredGarments.map((garment) => {
      const variant = selectedGarmentVariant(garment.type, garment.variant, sex);
      const sourceModel = variant.model ?? garmentDefinitions[garment.type].model;
      return {
        garment,
        label: variant.label,
        // Project Zomboid chooses a mesh per ClothingItem, not per broad UI
        // category. For example, the same trousers texture directory contains
        // body overlays, shorts and several dedicated trousers meshes.
        model: sourceModel as RigName,
        texture: variant.texture,
        wearOrder: garmentDefinitions[garment.type].wearOrder,
        masks: variant.masks ?? [],
        maskFolder: variant.maskFolder ?? defaultCharacterMaskFolder,
        underlayMaskFolder: variant.underlayMaskFolder ?? defaultCharacterMaskFolder,
        hatCategory: variant.hatCategory ?? '',
      };
    });
    const rigNames = new Set<RigName>(['body']);
    garmentAssets.forEach((asset) => rigNames.add(asset.model));
    const selectedHair = hairOptions[sex].find((option) => option.value === selection.hair) ?? hairOptions[sex][0];
    if (selectedHair.model) rigNames.add(selectedHair.model);
    const bodyTexture = `/pz/textures/body/${sex}-${bodyVariant}.png`;
    const hairTexture = selectedHair.texture ? `/pz/textures/hair-base/${selectedHair.texture}` : null;
    const modelTexturePaths = [...new Set([bodyTexture, ...garmentAssets.map((asset) => asset.texture)])];
    const characterMaskFolders = [...new Set([
      defaultCharacterMaskFolder,
      ...garmentAssets.flatMap((asset) => [asset.maskFolder, asset.underlayMaskFolder]),
    ].filter((folder) => !usesUnmaskedItemTexture(folder)))];
    const characterMaskTexturePaths = characterMaskFolders.flatMap((folder) => (
      characterMaskLeaves.map((leaf) => `${folder}/${leaf.toLowerCase()}.png`)
    ));
    const selectedProps=normalizedLootItems.map((item)=>sequencePropDefinitions[item.kind]);
    const sequenceModelPaths = [
      '/pz-game/models/handaxe.x',
      ...selectedProps.map((definition) => definition.model),
    ];
    const sequenceTexturePaths = [
      '/pz-game/textures/handaxe.png',
      ...selectedProps.map((definition) => definition.texture),
    ];
    const floorTexturePath = `/pz/floor-textures/${floor}.png?v=4`;
    const texturePaths = [...new Set([
      ...modelTexturePaths,
      ...characterMaskTexturePaths,
      ...sequenceTexturePaths,
      hairTexture,
      floorTexturePath,
    ].filter(Boolean) as string[])];
    const textureLoader = new THREE.TextureLoader();

    Promise.all([
      Promise.all([...rigNames].map(async (name) => [name, await loadLocalRig(name, sex, modelSet)] as const)),
      Promise.all(texturePaths.map(async (path) => [path, await loadTexture(textureLoader, path)] as const)),
      loadJson<PoseJson>(`/pz/rigs/poses/${selection.pose}.json`),
      Promise.all([...new Set(sequenceModelPaths)].map(async (path) => [
        path,
        await (path.endsWith('.x') ? loadObjectFromPzX(path) : loadObjectFromFbx(path)),
      ] as const)),
    ]).then(([rigEntries, textureEntries, poseJson, sequenceModelEntries]) => {
      if (cancelled) return;
      const rigModels = new Map(rigEntries.map(([name, json]) => [name, createRigModel(json)] as const));
      const textures = new Map(textureEntries);
      const sequenceModels = new Map(sequenceModelEntries);
      const sequenceMaterials = new Map(sequenceTexturePaths.map((path) => [
        path,
        createMaterial(textures.get(path)!, 0xffffff, true),
      ]));
      const hairMaterial = hairTexture ? createMaterial(textures.get(hairTexture)!, selection.hairColor) : null;
      hairMaterialRef.current = hairMaterial;
      const bodyImage = textures.get(bodyTexture)!.image as CanvasImageSource & { width: number; height: number };
      const bodyCompositeCanvas = document.createElement('canvas');
      bodyCompositeCanvas.width = bodyImage.width;
      bodyCompositeCanvas.height = bodyImage.height;
      const bodyCompositeTexture = new THREE.CanvasTexture(bodyCompositeCanvas);
      const bodyMaterial = createMaterial(bodyCompositeTexture);
      const dynamicTextures: THREE.Texture[] = [bodyCompositeTexture];
      const garmentMaterials: THREE.MeshStandardMaterial[] = [];
      const maskUnionCanvas = document.createElement('canvas');
      maskUnionCanvas.width = bodyImage.width;
      maskUnionCanvas.height = bodyImage.height;
      const paintMaskedAtlas = (
        target: HTMLCanvasElement,
        source: CanvasImageSource,
        visible: ReadonlySet<CharacterMaskLeaf>,
        maskFolder: string,
      ) => {
        const context = target.getContext('2d')!;
        context.globalCompositeOperation = 'source-over';
        context.clearRect(0, 0, target.width, target.height);
        if (visible.size === 0) return;
        context.drawImage(source, 0, 0, target.width, target.height);
        if (visible.size === characterMaskLeaves.length || usesUnmaskedItemTexture(maskFolder)) return;

        const maskContext = maskUnionCanvas.getContext('2d')!;
        maskContext.globalCompositeOperation = 'source-over';
        maskContext.clearRect(0, 0, maskUnionCanvas.width, maskUnionCanvas.height);
        visible.forEach((leaf) => {
          const mask = textures.get(`${maskFolder}/${leaf.toLowerCase()}.png`);
          if (mask) {
            maskContext.drawImage(
              mask.image as CanvasImageSource,
              0,
              0,
              maskUnionCanvas.width,
              maskUnionCanvas.height,
            );
          }
        });
        context.globalCompositeOperation = 'destination-in';
        context.drawImage(maskUnionCanvas, 0, 0, target.width, target.height);
        context.globalCompositeOperation = 'source-over';
      };
      const floorTexture = textures.get(floorTexturePath)!;
      floorTexture.colorSpace = THREE.SRGBColorSpace;
      floorTexture.wrapS = THREE.RepeatWrapping;
      floorTexture.wrapT = THREE.RepeatWrapping;
      floorTexture.repeat.set(120, 120);
      floorTexture.magFilter = THREE.NearestFilter;
      floorTexture.minFilter = THREE.NearestMipmapLinearFilter;
      const floorMaterial = new THREE.MeshStandardMaterial({ map: floorTexture, roughness: 1, metalness: 0 });
      const floorGeometry = new THREE.PlaneGeometry(120, 120);
      const floorPlane = new THREE.Mesh(floorGeometry, floorMaterial);
      floorPlane.rotation.x = -Math.PI / 2;
      floorPlane.position.y = -0.006;
      floorPlane.receiveShadow = true;
      scene.add(floorPlane);
      const pose = new PzRagdollPose(poseJson);
      if (preservedPoseStateRef.current) {
        pose.restoreState(preservedPoseStateRef.current);
        preservedPoseStateRef.current = null;
        preservePoseOnReloadRef.current = false;
      }
      rigModels.forEach((model) => skinRigModel(model, pose));

      const assembly = new THREE.Group();
      const content = new THREE.Group();
      const bodyRoot = cloneRigWithMaterial(rigModels.get('body')!, bodyMaterial);
      content.add(bodyRoot);

      let hairRoot: THREE.Group | null = null;
      if (selectedHair.model && hairMaterial) {
        const hairModel = rigModels.get(selectedHair.model);
        if (hairModel) {
          hairRoot = cloneRigWithMaterial(hairModel, hairMaterial);
          content.add(hairRoot);
        }
      }

      type ClothMeshState = {
        geometry: THREE.BufferGeometry;
        sourceGeometry: THREE.BufferGeometry;
      };
      type ClothInstance = {
        fabricStiffness: number;
        group: THREE.Group;
        level: number;
        index: number;
        model: RigName;
        texture: string;
        wearOrder: number;
        masks: number[];
        maskFolder: string;
        underlayMaskFolder: string;
        hatCategory: string;
        bodyOverlay: boolean;
        material: THREE.MeshStandardMaterial;
        atlasCanvas: HTMLCanvasElement;
        atlasTexture: THREE.CanvasTexture;
        sourceImage: CanvasImageSource;
        seed: number;
        center: THREE.Vector3;
        dressedPosition: THREE.Vector3;
        meshes: ClothMeshState[];
        appliedJoints: Map<string, THREE.Vector3>;
      };
      const clothInstances: ClothInstance[] = [];
      let renderedSequenceProgress = sequenceProgressRef.current;
      garmentAssets.forEach(({
        garment,
        model,
        texture,
        wearOrder,
        masks,
        maskFolder,
        underlayMaskFolder,
        hatCategory,
      }, index) => {
        const group = new THREE.Group();
        const sourceImage = textures.get(texture)!.image as CanvasImageSource & { width: number; height: number };
        const atlasCanvas = document.createElement('canvas');
        atlasCanvas.width = sourceImage.width;
        atlasCanvas.height = sourceImage.height;
        const atlasTexture = new THREE.CanvasTexture(atlasCanvas);
        dynamicTextures.push(atlasTexture);
        const garmentMaterial = createMaterial(atlasTexture);
        garmentMaterials.push(garmentMaterial);
        const visual = cloneRigWithMaterial(rigModels.get(model)!, garmentMaterial);
        const meshes: ClothMeshState[] = [];
        visual.traverse((object) => {
          const mesh = object as THREE.Mesh;
          if (!mesh.isMesh) return;
          const sourceGeometry = mesh.geometry;
          const geometry = sourceGeometry.clone();
          mesh.geometry = geometry;
          mesh.renderOrder = 20 + garment.level;
          const material = mesh.material as THREE.MeshStandardMaterial;
          material.depthFunc = THREE.LessEqualDepth;
          meshes.push({ geometry, sourceGeometry });
        });
        const center = new THREE.Box3().setFromObject(visual).getCenter(new THREE.Vector3());
        // Garments are skinned against the same Project Zomboid pose as the
        // body. Their dressed transform must therefore be exactly the source
        // transform; moving whole layers upward breaks sleeves and limbs.
        const dressedPosition = center.clone();
        visual.position.copy(center).multiplyScalar(-1);
        group.userData.level = garment.level;
        group.position.copy(dressedPosition);
        group.add(visual);
        content.add(group);
        clothInstances.push({
          fabricStiffness: garment.fabricStiffness ?? 1,
          group,
          level: garment.level,
          index,
          model,
          texture,
          wearOrder,
          masks,
          maskFolder,
          underlayMaskFolder,
          hatCategory,
          bodyOverlay: model === 'body',
          material: garmentMaterial,
          atlasCanvas,
          atlasTexture,
          sourceImage,
          seed: garment.id * 1.731 + garment.level * 2.417,
          center,
          dressedPosition,
          meshes,
          appliedJoints: rigJointPositions(rigModels.get(model)!, pose),
        });
      });

      type SkeletonVisual = {
        id: string;
        model: RigModel;
        getJoints: () => Map<string, THREE.Vector3>;
        line: THREE.LineSegments;
        positions: Float32Array;
      };
      const skeletonDebugRoot = new THREE.Group();
      skeletonDebugRoot.renderOrder = 250;
      content.add(skeletonDebugRoot);
      const skeletonDebugDisposables: Array<THREE.BufferGeometry | THREE.Material> = [];
      const bodyRig = rigModels.get('body')!;
      const skeletonEntries = [
        {
          id: 'body',
          label: 'Тело зомби',
          modelName: 'body',
          model: bodyRig,
          getJoints: () => rigJointPositions(bodyRig, pose),
          color: '#ffffff',
        },
        ...garmentAssets.map((asset, index) => ({
          id: `garment-${index}`,
          label: `${asset.garment.level + 1}: ${asset.label}`,
          modelName: asset.model,
          model: rigModels.get(asset.model)!,
          getJoints: () => {
            const instance = clothInstances[index];
            return new Map([...instance.appliedJoints].map(([name, point]) => [
              name,
              point.clone()
                .sub(instance.center)
                .applyQuaternion(instance.group.quaternion)
                .add(instance.group.position),
            ]));
          },
          color: ['#4de7ff', '#ff5edb', '#ffbd4a', '#8dff65', '#ae8cff', '#ff6a6a'][index % 6],
        })),
      ];
      const skeletonVisuals: SkeletonVisual[] = [];
      const createSkeletonVisual = (
        entry: (typeof skeletonEntries)[number],
        dashed: boolean,
      ) => {
        const availableBones = new Set(entry.model.parts.flatMap((part) => part.boneNames));
        const visibleSegments = rigDiagnosticSegments.filter(([start, end]) => (
          availableBones.has(start) && availableBones.has(end)
        ));
        const positions = new Float32Array(visibleSegments.length * 6);
        const geometry = new THREE.BufferGeometry();
        geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3).setUsage(THREE.DynamicDrawUsage));
        const material = dashed
          ? new THREE.LineDashedMaterial({
            color: entry.color,
            dashSize: 0.016,
            gapSize: 0.009,
            depthTest: false,
            depthWrite: false,
            transparent: true,
            opacity: 1,
          })
          : new THREE.LineBasicMaterial({
            color: entry.color,
            depthTest: false,
            depthWrite: false,
            transparent: true,
            opacity: 0.78,
          });
        const line = new THREE.LineSegments(geometry, material);
        line.renderOrder = dashed ? 252 : 251;
        line.userData.visibleSegments = visibleSegments;
        line.visible = false;
        skeletonDebugRoot.add(line);
        skeletonDebugDisposables.push(geometry, material);
        skeletonVisuals.push({
          id: entry.id,
          model: entry.model,
          getJoints: entry.getJoints,
          line,
          positions,
        });
      };
      skeletonEntries.forEach((entry) => createSkeletonVisual(entry, entry.id !== 'body'));
      const baseSkeletonDiagnostics = skeletonEntries.map((entry) => {
        const comparison = compareRigSkeletons(bodyRig, entry.model);
        return {
          id: entry.id,
          label: entry.label,
          color: entry.color,
          model: entry.modelName,
          bones: comparison.commonBones,
          missingBones: comparison.missingBones.length,
          maxJointDeltaMm: comparison.maxJointDelta * 1000,
          maxRotationDeltaDeg: THREE.MathUtils.radToDeg(comparison.maxRotationDelta),
        };
      });
      let skeletonDiagnosticSignature = '';
      const updateSkeletonVisuals = () => {
        const bodyJoints = skeletonEntries[0].getJoints();
        const diagnostics: SkeletonDiagnostic[] = [];
        skeletonVisuals.forEach((visual, visualIndex) => {
          // Garment lines use the last pose that was actually baked into that
          // instance's private sequencer geometry, not merely the requested
          // body pose.  A frozen clothing clone is therefore visible here as
          // a real skeleton divergence instead of a misleading overlap.
          const joints = visual.getJoints();
          const instance = visualIndex > 0 ? clothInstances[visualIndex - 1] : null;
          const poseDelta = Math.max(0, ...[...joints].flatMap(([name, point]) => {
            if (name === '__identity') return [];
            const bodyPoint = bodyJoints.get(name);
            return bodyPoint ? [point.distanceTo(bodyPoint)] : [];
          }));
          const action = instance ? sequenceActions.find((a) => a.kind === 'layer' && a.layer === instance.level) : null;
          const peers = instance ? clothInstances.filter((other) => other.level === instance.level) : [];
          const delay = instance ? garmentReleaseFan(peers.indexOf(instance), peers.length, instance.level).delay : 0;
          const detached = !!action && renderedSequenceProgress * sequenceDurationSeconds > action.start * sequenceDurationSeconds + delay;
          visual.line.visible = skeletonDebugRoot.visible && !detached && (visual.id === 'body' || visual.id === skeletonDebugTargetRef.current);
          diagnostics.push({
            detached,
            ...baseSkeletonDiagnostics[visualIndex],
            posedJointDeltaMm: poseDelta * 1000,
            instanceRotationDeg: instance
              ? THREE.MathUtils.radToDeg(instance.group.quaternion.angleTo(new THREE.Quaternion()))
              : 0,
          });
          const visibleSegments = visual.line.userData.visibleSegments as ReadonlyArray<readonly [string, string]>;
          visibleSegments.forEach(([start, end], index) => {
            const startPoint = joints.get(start)!;
            const endPoint = joints.get(end)!;
            startPoint.toArray(visual.positions, index * 6);
            endPoint.toArray(visual.positions, index * 6 + 3);
          });
          const attribute = visual.line.geometry.getAttribute('position') as THREE.BufferAttribute;
          attribute.needsUpdate = true;
          visual.line.computeLineDistances();
          visual.line.geometry.computeBoundingSphere();
        });
        if (skeletonDebugRoot.visible) {
          const signature = diagnostics.map((item) => (
            `${item.id}:${item.detached}:${item.posedJointDeltaMm.toFixed(2)}:${item.instanceRotationDeg.toFixed(2)}`
          )).join('|');
          if (signature !== skeletonDiagnosticSignature) {
            skeletonDiagnosticSignature = signature;
            setSkeletonDiagnostics(diagnostics);
          }
        }
      };
      const setSkeletonDebug = (visible: boolean, target: string) => {
        skeletonDebugRoot.visible = visible;
        skeletonVisuals.forEach((visual) => {
          visual.line.visible = visible && (visual.id === 'body' || visual.id === target);
        });
        if (visible) updateSkeletonVisuals();
      };
      const availableSkeletonTarget = baseSkeletonDiagnostics.some(({ id }) => id === skeletonDebugTargetRef.current)
        ? skeletonDebugTargetRef.current
        : baseSkeletonDiagnostics[1]?.id ?? 'body';
      skeletonDebugTargetRef.current = availableSkeletonTarget;
      setSkeletonDebugTarget(availableSkeletonTarget);
      setSkeletonDebug(skeletonDebugVisibleRef.current, availableSkeletonTarget);

      const createStaticProp = (modelPath: string, texturePath: string, scale: number, center = true) => {
        const source = sequenceModels.get(modelPath)!;
        const root = new THREE.Group();
        const model = cloneObjectWithMaterial(source, sequenceMaterials.get(texturePath)!);
        if (center) {
          const bounds = new THREE.Box3().setFromObject(model);
          model.position.sub(bounds.getCenter(new THREE.Vector3()));
        }
        root.add(model);
        root.scale.setScalar(scale);
        return root;
      };

      // Select an anatomical upper-back point in the unposed body, then mount
      // the blade on that same skinned triangle in the current ragdoll pose.
      const axe = createStaticProp('/pz-game/models/handaxe.x', '/pz-game/textures/handaxe.png', 1, false);
      const axeLocalBounds = new THREE.Box3().setFromObject(axe);
      const spineTransform = pose.boneGlobals().get('Bip01_Spine1')!;
      const axeOriginPosition = new THREE.Vector3();
      const axeOriginQuaternion = new THREE.Quaternion();
      const axeSurfaceAttachment = mountAxeOnBack(rigModels.get('body')!,bodyRoot,content,
        axeOriginPosition,axeOriginQuaternion);
      axe.position.copy(axeOriginPosition);
      axe.quaternion.copy(axeOriginQuaternion);
      const axeBoneLocal = captureRigAttachment(spineTransform,axeOriginPosition,axeOriginQuaternion);
      content.add(axe);

      type LootInstance = {
        targetIndex:number;
        partSpread:number;
        hull?:LootHull;
        supportVertices:LootHull['vertices'];
        group: THREE.Group;
        kind: SequencePropKind;
        layer: number;
        index: number;
        origin: THREE.Vector3;
        originQuaternion: THREE.Quaternion;
        bounds: THREE.Box3;
        mass: number;
        airDrag: number;
        restitution: number;
      };
      const lootInstances: LootInstance[] = [];
      normalizedLootItems.forEach((lootItem, targetIndex) => {
        const level = lootItem.layer;
        const items = garmentLayers.find(([candidate]) => candidate === level)?.[1] ?? [];
        const origin = pose.getHandlePosition(
          items.some((item) => ['trousers', 'shorts', 'shortshorts', 'suittrousers', 'underpants'].includes(item.type))
            ? 'waist'
            : 'chest',
        );
        const kind = lootItem.kind;
        const definition = sequencePropDefinitions[kind];
        const sourceGroup = createStaticProp(definition.model, definition.texture, definition.scale);
        const components=prepareLootParts(sourceGroup,definition.model);
        const totalArea=components.reduce((sum,component)=>sum+Math.max(component.area,1e-12),0);
        components.forEach(({group,area},partIndex)=>{
        const index = lootInstances.length;
        const originOffset = new THREE.Vector3(
          Math.cos(targetIndex * 2.399963) * 0.012,
          0.012 + (targetIndex % 2) * 0.008,
          Math.sin(targetIndex * 2.399963) * 0.012,
        );
        group.position.copy(origin).add(originOffset);
        group.visible = false;
        content.add(group);
        const bounds = new THREE.Box3().setFromObject(group).translate(group.position.clone().multiplyScalar(-1));
        const colliderPoints:THREE.Vector3[]=[],colliderCenter=bounds.getCenter(new THREE.Vector3());
        group.updateWorldMatrix(true,true);
        group.traverse(object=>{
          const mesh=object as THREE.Mesh;if(!mesh.isMesh)return;
          const position=mesh.geometry.getAttribute('position');
          for(let i=0;i<position.count;i++)colliderPoints.push(new THREE.Vector3().fromBufferAttribute(position,i)
            .applyMatrix4(mesh.matrixWorld).sub(group.position).sub(colliderCenter));
        });
        const hull=makeLootHull(colliderPoints);
        lootInstances.push({
          targetIndex,
          partSpread:components.length>1?(partIndex/(components.length-1)-.5)*.024:0,
          hull,
          supportVertices:hull?.vertices??boxVertices(bounds.getSize(new THREE.Vector3()).multiplyScalar(.5).toArray().map(n=>Math.max(.00015,n))),
          group,
          kind,
          layer: level,
          index,
          origin: group.position.clone(),
          originQuaternion: group.quaternion.clone(),
          bounds,
          mass: definition.mass*Math.max(area,1e-12)/totalArea,
          airDrag: definition.airDrag,
          restitution: definition.restitution,
        });
        });
      });

      const bodyBounds = new THREE.Box3().setFromObject(bodyRoot);
      const bodyCenter = bodyBounds.getCenter(new THREE.Vector3());
      const sequenceFloorHeight = bodyBounds.min.y + floorPlane.position.y / 1.9;
      content.position.set(-bodyCenter.x, -bodyBounds.min.y, -bodyCenter.z);
      assembly.add(content);
      assembly.scale.setScalar(1.9);
      assembly.rotation.y = 0;
      scene.add(assembly);

      const dropPointGroup = new THREE.Group();
      dropPointGroup.visible = dropPointsVisibleRef.current;
      const dropPointMeshes: Partial<Record<DropPointKind, THREE.Group>> = {};
      const dropPointDisposables: Array<THREE.BufferGeometry | THREE.Material | THREE.Texture> = [];
      const createDropPointMarker = (kind: DropPointKind) => {
        const marker = new THREE.Group();
        marker.userData.dropPoint = kind;
        const color = dropPointColors[kind];
        const ringGeometry = new THREE.RingGeometry(0.94, 1, 64);
        const ringMaterial = new THREE.MeshBasicMaterial({
          color,
          transparent: true,
          opacity: 0.92,
          side: THREE.DoubleSide,
          depthTest: false,
          depthWrite: false,
        });
        const ring = new THREE.Mesh(ringGeometry, ringMaterial);
        ring.rotation.x = -Math.PI / 2;
        ring.scale.setScalar(dropPointPositionsRef.current[kind].radius);
        ring.name='spread-ring';
        ring.userData.resizeDropPoint=true;
        ring.renderOrder = 210;
        ring.userData.dropPoint = kind;
        ring.userData.dropPointColor = color;
        marker.add(ring);
        // A wider invisible hit band makes the thin visible circumference easy
        // to grab without turning the entire disk into a resize handle.
        const hitGeometry=new THREE.RingGeometry(.8,1.2,64);
        const hitMaterial=new THREE.MeshBasicMaterial({transparent:true,opacity:0,side:THREE.DoubleSide,depthWrite:false});
        const hitRing=new THREE.Mesh(hitGeometry,hitMaterial);
        hitRing.userData.resizeDropPoint=true;
        ring.add(hitRing);
        dropPointDisposables.push(hitGeometry,hitMaterial);

        const dotGeometry = new THREE.CircleGeometry(0.02, 20);
        const dotMaterial = new THREE.MeshBasicMaterial({
          color,
          side: THREE.DoubleSide,
          depthTest: false,
          depthWrite: false,
        });
        const dot = new THREE.Mesh(dotGeometry, dotMaterial);
        dot.rotation.x = -Math.PI / 2;
        dot.position.y = 0.001;
        dot.renderOrder = 211;
        dot.userData.dropPoint = kind;
        dot.userData.dropPointColor = color;
        marker.add(dot);

        const labelCanvas = document.createElement('canvas');
        labelCanvas.width = 256;
        labelCanvas.height = 64;
        const context = labelCanvas.getContext('2d')!;
        context.fillStyle = 'rgba(17,19,17,.88)';
        context.fillRect(0, 0, 256, 64);
        context.strokeStyle = `#${color.toString(16).padStart(6, '0')}`;
        context.lineWidth = 3;
        context.strokeRect(2, 2, 252, 60);
        context.fillStyle = '#f1f3ee';
        context.font = '600 27px Arial';
        context.textAlign = 'center';
        context.textBaseline = 'middle';
        context.fillText(dropPointLabels[kind], 128, 33);
        const labelTexture = new THREE.CanvasTexture(labelCanvas);
        labelTexture.colorSpace = THREE.SRGBColorSpace;
        const labelMaterial = new THREE.SpriteMaterial({
          map: labelTexture,
          transparent: true,
          depthTest: false,
          depthWrite: false,
        });
        const label = new THREE.Sprite(labelMaterial);
        label.position.set(0, 0.075, 0);
        label.scale.set(0.28, 0.07, 1);
        label.renderOrder = 212;
        label.userData.dropPoint = kind;
        marker.add(label);

        const position = dropPointPositionsRef.current[kind];
        marker.position.set(position.x, floorPlane.position.y + 0.012, position.z);
        marker.traverse((object) => { object.userData.dropPoint = kind; });
        dropPointDisposables.push(ringGeometry, ringMaterial, dotGeometry, dotMaterial, labelTexture, labelMaterial);
        dropPointGroup.add(marker);
        dropPointMeshes[kind] = marker;
      };
      dropPointKinds.forEach(createDropPointMarker);
      scene.add(dropPointGroup);
      dropPointMeshesRef.current = dropPointMeshes;

      const isGarmentAttached = (instance: ClothInstance, progress: number) => {
        const action = sequenceActions.find((candidate) => candidate.kind === 'layer' && candidate.layer === instance.level);
        const peers=clothInstances.filter((other)=>other.level===instance.level);
        const delay=garmentReleaseFan(peers.indexOf(instance),peers.length,instance.level).delay;
        return !action || progress * sequenceDurationSeconds <= action.start * sequenceDurationSeconds + delay;
      };
      // A real empty signature is valid at the final frame, so use a sentinel
      // to force the first atlas paint after every scene rebuild.
      let dressedTextureSignature = '\u0000';
      const updateDressedTextures = (progress: number) => {
        const attached = clothInstances.filter((instance) => isGarmentAttached(instance, progress));
        const signature = attached.map((instance) => instance.index).join(',');
        if (signature === dressedTextureSignature) return;
        dressedTextureSignature = signature;

        const allParts = new Set<CharacterMaskLeaf>(characterMaskLeaves);
        const outsideToInside = [...attached].sort((left, right) => (
          right.level - left.level
          || right.wearOrder - left.wearOrder
          || right.index - left.index
        ));
        const visibleClothingParts = new Set<CharacterMaskLeaf>(characterMaskLeaves);
        let overlayMaskFolder = defaultCharacterMaskFolder;
        outsideToInside.forEach((instance) => {
          const effectiveMaskFolder = instance.maskFolder === defaultCharacterMaskFolder
            ? overlayMaskFolder
            : instance.maskFolder;
          const itemVisible = usesUnmaskedItemTexture(effectiveMaskFolder)
            ? allParts
            : visibleClothingParts;
          paintMaskedAtlas(instance.atlasCanvas, instance.sourceImage, itemVisible, effectiveMaskFolder);
          instance.atlasTexture.needsUpdate = true;
          hideCharacterParts(visibleClothingParts, instance.masks);
          if (instance.underlayMaskFolder !== defaultCharacterMaskFolder) {
            overlayMaskFolder = instance.underlayMaskFolder;
          }
        });
        clothInstances
          .filter((instance) => !attached.includes(instance))
          .forEach((instance) => {
            paintMaskedAtlas(instance.atlasCanvas, instance.sourceImage, allParts, 'none');
            instance.atlasTexture.needsUpdate = true;
          });

        // Project Zomboid hides the body atlas regions covered by the complete
        // attached clothing stack. Keeping the whole body visible makes skin
        // intersect sleeves and trouser meshes in every bent pose.
        paintMaskedAtlas(bodyCompositeCanvas, bodyImage, visibleClothingParts, overlayMaskFolder);
        const composite = bodyCompositeCanvas.getContext('2d')!;
        [...outsideToInside].reverse()
          .filter((instance) => instance.bodyOverlay)
          .forEach((instance) => composite.drawImage(
            instance.atlasCanvas,
            0,
            0,
            bodyCompositeCanvas.width,
            bodyCompositeCanvas.height,
          ));
        bodyCompositeTexture.needsUpdate = true;
        if (hairRoot) {
          hairRoot.visible = !attached.some((instance) => (
            instance.hatCategory === 'nohair' || instance.hatCategory === 'nohairnobeard'
          ));
        }
      };
      const localDropPoint = (kind: DropPointKind, offsetX = 0, offsetZ = 0) => {
        const point = dropPointPositionsRef.current[kind];
        return content.worldToLocal(new THREE.Vector3(
          point.x + offsetX,
          floorPlane.position.y + 0.006,
          point.z + offsetZ,
        ));
      };
      let clothWorker: Worker | null = null;
      let quickWorker: Worker | null = null;
      let quickPending: Promise<void> | null = null;
      let finishQuick: (()=>void) | null = null;
      const stopQuickWorker=()=>{quickWorker?.terminate();quickWorker=null;finishQuick?.();finishQuick=null;quickPending=null;};
      let bakeTimer: ReturnType<typeof setTimeout> | null = null;
      let clothBake: ClothBake | null = null;
      let preciseLootBake: LootBake | null = null;
      let quickPreview: QuickPreview | null = null;
      let usePreciseCloth = false;
      let preciseSourceMessage = '';
      let exportUsesPrecise: boolean | null = null;
      let bakeVersion = 0;
      let blenderJob: string | null = null;
      const detachedMeshes: THREE.Mesh[] = [];
      const quickMeshes: THREE.Mesh[] = [];
      const preciseActive = () => (exportUsesPrecise ?? usePreciseCloth) && !!clothBake;

      const clearDetachedMeshes = () => {
        detachedMeshes.forEach((mesh) => { content.remove(mesh); mesh.geometry.dispose(); });
        detachedMeshes.length = 0;
      };
      const clearQuickMeshes = () => {
        quickMeshes.forEach((mesh) => { content.remove(mesh); mesh.geometry.dispose(); });
        quickMeshes.length = 0;
      };
      const updateWornCloth = (instance: ClothInstance) => {
        instance.group.position.copy(instance.dressedPosition);
        instance.group.quaternion.identity();
        instance.group.scale.setScalar(1);
        instance.meshes.forEach(({ geometry, sourceGeometry }) => {
          const positions = geometry.getAttribute('position') as THREE.BufferAttribute;
          positions.copy(sourceGeometry.getAttribute('position') as THREE.BufferAttribute);
          positions.needsUpdate = true;
          const normals = geometry.getAttribute('normal') as THREE.BufferAttribute;
          normals.copy(sourceGeometry.getAttribute('normal') as THREE.BufferAttribute);
          normals.needsUpdate = true;
          geometry.computeBoundingBox();
          geometry.computeBoundingSphere();
        });
        instance.appliedJoints = rigJointPositions(rigModels.get(instance.model)!, pose);
      };
      const makePhysicsInput = (): ClothBakeInput & { loot: LootBodyInput[] } => {
        const capsuleLinks: Array<[HandleKey, HandleKey, number]> = [
          ['pelvis', 'waist', 0.055], ['waist', 'chest', 0.06], ['neck', 'head', 0.04],
          ['leftShoulder', 'leftElbow', 0.021], ['leftElbow', 'leftHand', 0.015],
          ['rightShoulder', 'rightElbow', 0.021], ['rightElbow', 'rightHand', 0.015],
          ['leftHip', 'leftKnee', 0.033], ['leftKnee', 'leftFoot', 0.024],
          ['rightHip', 'rightKnee', 0.033], ['rightKnee', 'rightFoot', 0.024],
        ];
        const capsules: Capsule[] = capsuleLinks.map(([a, b, radius]) => ({
          a: pose.getHandlePosition(a).toArray() as [number, number, number],
          b: pose.getHandlePosition(b).toArray() as [number, number, number], radius,
        }));
        return {
          floor: sequenceFloorHeight, duration: sequenceDurationSeconds, capsules,
          items: clothInstances.map((instance) => {
            const canvas = document.createElement('canvas');
            const source = instance.sourceImage as CanvasImageSource & { width: number; height: number };
            canvas.width = source.width; canvas.height = source.height;
            const context = canvas.getContext('2d', { willReadFrequently: true })!;
            context.drawImage(source, 0, 0);
            const image = context.getImageData(0, 0, canvas.width, canvas.height);
            const action = sequenceActions.find((a) => a.kind === 'layer' && a.layer === instance.level);
            const peers=clothInstances.filter((other)=>other.level===instance.level);
            const fan=garmentReleaseFan(peers.indexOf(instance),peers.length,instance.level);
            return {
              surfaces: instance.meshes.map(({ sourceGeometry }) => clothSurface(sourceGeometry, image)),
              layerId: instance.level,
              fabricStiffness: instance.fabricStiffness,
              releaseTime: (action?.start ?? 1) * sequenceDurationSeconds + fan.delay,
              flightTime: fan.flight, spin: fan.spin,
              target: (()=>{const offset=dropDiskSample(instance.level+100,dropPointPositionsRef.current.clothing.radius);return localDropPoint('clothing',offset.x,offset.z).toArray() as [number,number,number];})(),
              seed: instance.seed,
            };
          }),
          loot: lootInstances.map((instance) => {
            const action = sequenceActions.find((a) => a.kind === 'layer' && a.layer === instance.layer);
            const center = instance.bounds.getCenter(new THREE.Vector3()).applyQuaternion(instance.originQuaternion).add(instance.origin);
            const offset = dropDiskSample(instance.targetIndex,dropPointPositionsRef.current.valuables.radius*.7);
            return {
              center: center.toArray() as [number, number, number],
              hull:instance.hull,
              halfExtents: instance.bounds.getSize(new THREE.Vector3()).multiplyScalar(0.5).toArray() as [number, number, number],
              quaternion: instance.originQuaternion.toArray() as [number, number, number, number],
              target: localDropPoint('valuables', offset.x+instance.partSpread, offset.z).toArray() as [number, number, number],
              landingArea:{center:localDropPoint('valuables').toArray() as [number,number,number],radius:localDropPoint('valuables',dropPointPositionsRef.current.valuables.radius,0).distanceTo(localDropPoint('valuables'))},
              releaseTime: (action?.start ?? 1) * sequenceDurationSeconds + 0.07,
              flightTime: 0.5,
              mass: instance.mass, index: instance.index,
            };
          }).concat([(()=>{
            const action=sequenceActions.find(a=>a.kind==='axe')!;
            const center=axeLocalBounds.getCenter(new THREE.Vector3()).applyQuaternion(axeOriginQuaternion).add(axeOriginPosition).add(new THREE.Vector3(0,.15,0));
            const offset=dropDiskSample(200,dropPointPositionsRef.current.weapon.radius*.35);
            return {center:center.toArray() as [number,number,number],halfExtents:axeLocalBounds.getSize(new THREE.Vector3()).multiplyScalar(.5).toArray() as [number,number,number],quaternion:axeOriginQuaternion.toArray() as [number,number,number,number],hull:undefined,
              target:localDropPoint('weapon',offset.x,offset.z).toArray() as [number,number,number],landingArea:{center:localDropPoint('weapon').toArray() as [number,number,number],radius:localDropPoint('weapon',dropPointPositionsRef.current.weapon.radius,0).distanceTo(localDropPoint('weapon'))},releaseTime:action.start*sequenceDurationSeconds+.11,flightTime:.5,mass:.9,index:lootInstances.length};
          })()]),
        };
      };
      const stopClothWorker = () => {
        ++bakeVersion;
        clothWorker?.terminate(); clothWorker = null;
        if(blenderJob){void fetch('/__blender/jobs/'+blenderJob,{method:'DELETE',headers:{'x-cloth-client':'1'},keepalive:true}).catch(()=>{});blenderJob=null;}
      };
      const makePhysicsSnapshotJson = async () => {
        // Capture the same posed, alpha-filtered input the workers receive.
        // Never reset pose, regenerate clothing, or start a simulation here.
        const input = makePhysicsInput();
        scene.updateMatrixWorld(true);
        const cameraLocal = content.matrixWorld.clone().invert().multiply(camera.matrixWorld);
        const snapshot = {
          format: 'pz-cloth-scene-v1', capturedAt: new Date().toISOString(),
          sceneKey: await clothSceneKey(input),
          selection, modelSet, fps: 60, ...input,
          velocities: clothReleaseVelocities(input.items).map(v => v.toArray()),
          camera: { matrix: cameraLocal.toArray(), left: camera.left, right: camera.right,
            top: camera.top, bottom: camera.bottom, zoom: camera.zoom,
            contentWorldScale: content.getWorldScale(new THREE.Vector3()).toArray() },
          garments: clothInstances.map(instance => ({ model: instance.model, texture: instance.texture,
            level: instance.level, index: instance.index,
            restSurfaces: rigModels.get(instance.model)!.parts.map(part => ({ positions: part.positions })) })),
          body: rigModels.get('body')!.parts.map(({ geometry }) => ({
            positions: geometry.getAttribute('position').array, uvs: geometry.getAttribute('uv').array,
            indices: geometry.index!.array,
          })),
        };
        const json = JSON.stringify(snapshot, (_key, value) => ArrayBuffer.isView(value)
          ? Array.from(value as unknown as ArrayLike<number>) : value);
        return json;
      };
      const exportPhysicsSnapshot = async () => {
        const json = await makePhysicsSnapshotJson();
        const url = URL.createObjectURL(new Blob([json], { type: 'application/json' }));
        const link = document.createElement('a'); link.href = url;
        link.download = 'pz-cloth-scene-' + Date.now() + '.json'; link.click();
        setTimeout(() => URL.revokeObjectURL(url), 1000);
      };
      const rebuildQuickPreview = ():Promise<void> => {
        if (bakeTimer) clearTimeout(bakeTimer);
        bakeTimer = null;
        if (cancelled) return Promise.resolve();
        if(quickPending)return quickPending;
        const worker=new QuickWorker();quickWorker=worker;
        quickPending=new Promise<void>(resolve=>{finishQuick=resolve;});
        const pending=quickPending;
        const fail=(message:string)=>{if(quickWorker!==worker)return;setSimulationBusy(false);setSimulationStatus('Ошибка предпросмотра: '+message);stopQuickWorker();};
        worker.onerror=event=>fail(event.message);
        worker.onmessage=(event:MessageEvent<{bake?:ClothBake;loot?:LootBake;error?:string}>)=>{
          if(cancelled||quickWorker!==worker)return;
          if(event.data.error){fail(event.data.error);return;}
          if(!event.data.bake||!event.data.loot)return;
          quickPreview = {...event.data.bake,loot:event.data.loot};
          if((event.data.loot.landingError??0)>.0001)setClothMessage('Подбор броска не уложил все предметы в окружность. Попробуйте увеличить её радиус.');
          clearQuickMeshes();
          quickPreview.tracks.forEach((track,index) => {
            const geometry = new THREE.BufferGeometry();
            geometry.setAttribute('position',new THREE.BufferAttribute(track.positions.slice(),3));
            geometry.setAttribute('uv',new THREE.BufferAttribute(track.uvs,2));
            geometry.setAttribute('normal',new THREE.BufferAttribute(new Float32Array(track.positions.length),3));
            geometry.setIndex(new THREE.BufferAttribute(track.indices,1));
            geometry.computeVertexNormals();
            geometry.userData.normalScratch = new Float32Array(track.particleCount*3);
            const mesh = new THREE.Mesh(geometry,clothInstances[index].material);
            mesh.castShadow = true; mesh.receiveShadow = true; mesh.visible = false;
            content.add(mesh); quickMeshes.push(mesh);
          });
          setSimulationBusy(false); setSimulationStatus('');
          applySequence(sequenceProgressRef.current);
          stopQuickWorker();
        };
        try{
          const input=makePhysicsInput();
          // Reproducible local diagnostics of exactly the currently loaded scene.
          canvas.dataset.lootInput=JSON.stringify({loot:input.loot,floor:input.floor,duration:input.duration});
          worker.postMessage({...input,quality:'quick'});
        }catch(error){fail(String(error));}
        return pending;
      };
      // Scene edits only rebuild original-resolution cloth, never the final bake.
      let dropEditActive = false;
      let dropEditDirty = false;
      const scheduleQuickPreview = (delay = 120) => {
        if (dropEditActive) { dropEditDirty = true; return; }
        stopPlayback();
        exportAbortRef.current?.abort();
        setExportResult(null);
        stopClothWorker();
        stopQuickWorker();
        if (bakeTimer) clearTimeout(bakeTimer);
        clothBake = null; preciseLootBake = null; quickPreview = null; usePreciseCloth = false;
        preciseSourceMessage = '';
        clearDetachedMeshes(); clearQuickMeshes();
        setClothMode(invalidateClothPreview); setClothMessage('');
        setSimulationBusy(true); setSimulationStatus('Подготовка быстрого сброса…');
        bakeTimer = setTimeout(rebuildQuickPreview,delay);
      };
      // The expensive worker is created only by the explicit UI action.
      const calculateCloth = async () => {
          stopPlayback();
          setPhysics(false); ragdollEnabledRef.current = false; setRagdollEnabled(false);
          if (!quickPreview) await rebuildQuickPreview();
          if (!quickPreview) return;
          stopClothWorker();
          const version = bakeVersion;
          setClothMode('calculating'); setClothMessage('Расчёт ткани · 0%');
          setExportResult(null);
          const worker = new ClothWorker(); clothWorker = worker;
          const fail = (message: string) => {
            if (cancelled || version !== bakeVersion) return;
            setClothMode('error'); setClothMessage('Ошибка расчёта ткани: ' + message);
            worker.terminate(); clothWorker = null;
          };
          worker.onerror = (event) => fail(event.message);
          worker.onmessage = (event: MessageEvent<{ progress?: number; error?: string; bake?: ClothBake; loot?: LootBake }>) => {
            if (cancelled || version !== bakeVersion) return;
            if (event.data.error) { fail(event.data.error); return; }
            if (event.data.bake && event.data.loot) {
              clothBake = event.data.bake; preciseLootBake = event.data.loot;
              preciseSourceMessage = '';
              clearDetachedMeshes();
              clothBake.tracks.forEach((track, index) => {
                const geometry = new THREE.BufferGeometry();
                geometry.setAttribute('position', new THREE.BufferAttribute(track.positions.slice(), 3));
                geometry.setAttribute('uv', new THREE.BufferAttribute(track.uvs, 2));
                geometry.setIndex(new THREE.BufferAttribute(track.indices, 1));
                geometry.computeVertexNormals();
                geometry.userData.normalScratch = new Float32Array(track.particleCount * 3);
                const mesh = new THREE.Mesh(geometry, clothInstances[index].material);
                mesh.castShadow = true; mesh.receiveShadow = true; mesh.visible = false;
                content.add(mesh); detachedMeshes.push(mesh);
              });
              usePreciseCloth = true;
              setClothMode('ready'); setClothMessage('');
              worker.terminate(); clothWorker = null;
              applySequence(sequenceProgressRef.current);
            } else if (event.data.progress !== undefined) {
              setClothMessage('Расчёт ткани · ' + Math.round(event.data.progress * 100) + '%');
            }
          };
          try { worker.postMessage({...makePhysicsInput(),reuseLoot:quickPreview.loot}); } catch (error) { fail(String(error)); }
      };
      const cancelCloth = () => {
        stopClothWorker(); usePreciseCloth = false;
        setClothMode('stale'); setClothMessage('Расчёт отменён · быстрый сброс');
        applySequence(sequenceProgressRef.current);
      };
      const showPreciseCloth = (precise: boolean) => {
        if (!clothBake) return;
        usePreciseCloth = precise;
        setClothMode(precise ? 'ready' : 'cached'); setClothMessage(precise ? preciseSourceMessage : '');
        setExportResult(null);
        applySequence(sequenceProgressRef.current);
      };
      const importBlenderCache = async (file: File) => {
        stopPlayback(); stopClothWorker();
        const version = bakeVersion;
        try {
          if(file.size>512*1024*1024)throw new Error('Кэш больше 512 МБ');
          const input = makePhysicsInput(), key = await clothSceneKey(input);
          const {bake,warnings} = decodeBlenderCache(await file.arrayBuffer(),key,input);
          if(!quickPreview)await rebuildQuickPreview();
          if(cancelled || version!==bakeVersion || !quickPreview || key!==await clothSceneKey(makePhysicsInput()))return;
          setPhysics(false); ragdollEnabledRef.current=false; setRagdollEnabled(false);
          clothBake=bake; preciseLootBake=quickPreview.loot;
          clearDetachedMeshes();
          bake.tracks.forEach((track,index)=>{
            const geometry=new THREE.BufferGeometry();
            geometry.setAttribute('position',new THREE.BufferAttribute(track.positions.slice(),3));
            geometry.setAttribute('uv',new THREE.BufferAttribute(track.uvs,2));
            geometry.setIndex(new THREE.BufferAttribute(track.indices,1));
            geometry.computeVertexNormals();
            geometry.userData.normalScratch=new Float32Array(track.particleCount*3);
            const mesh=new THREE.Mesh(geometry,clothInstances[index].material);
            mesh.castShadow=true;mesh.receiveShadow=true;mesh.visible=false;
            content.add(mesh);detachedMeshes.push(mesh);
          });
          usePreciseCloth=true;setClothMode('ready');setExportResult(null);
          preciseSourceMessage='Blender · '+bake.tracks.length+' вещей · '+bake.frameCount+' кадров'+(warnings.length?' · '+warnings.join('; '):'');
          setClothMessage(preciseSourceMessage);
          applySequence(sequenceProgressRef.current);
        } catch(error) {
          if(!cancelled && version===bakeVersion){setClothMessage(String(error));setClothMode(mode=>mode==='calculating'?'error':mode);}
        }
      };
      const calculateBlender = async () => {
        stopPlayback();stopClothWorker();
        setPhysics(false);ragdollEnabledRef.current=false;setRagdollEnabled(false);
        const version=bakeVersion;
        const current=()=>!cancelled && version===bakeVersion;
        setClothMode('calculating');setClothMessage('Blender · подготовка снимка');setExportResult(null);
        try{
          const snapshot=await makePhysicsSnapshotJson();if(!current())return;
          const response=await fetch('/__blender/jobs',{method:'POST',headers:{'Content-Type':'application/json','x-cloth-client':'1'},
            body:'{"snapshot":'+snapshot+'}'});
          if(!response.headers.get('content-type')?.includes('application/json'))throw new Error('Blender доступен через локальный dev-сервер. Перезапустите сервер после обновления.');
          const started=await response.json() as {id:string;error?:string};if(!response.ok)throw new Error(started.error);
          if(!/^[\da-f-]{36}$/.test(started.id))throw new Error('Неверный ответ сервиса Blender');
          if(!current()){void fetch('/__blender/jobs/'+started.id,{method:'DELETE',headers:{'x-cloth-client':'1'}});return;}
          blenderJob=started.id;
          while(current()){
            const statusResponse=await fetch('/__blender/jobs/'+started.id);const status=await statusResponse.json() as {state:string;message:string;error?:string;code?:string};
            if(!current())return;
            if(!statusResponse.ok || status.state==='error' || status.state==='cancelled')throw new Error(status.message??status.error);
            setClothMessage(status.message);
            if(status.state==='ready'){
              const cache=await fetch('/__blender/jobs/'+started.id+'/cache');if(!cache.ok)throw new Error('Не удалось получить кэш Blender');
              const blob=await cache.blob();if(!current())return;
              blenderJob=null;
              await importBlenderCache(new File([blob],'scene.pzcloth'));
              return;
            }
            await new Promise(resolve=>setTimeout(resolve,1500));
          }
        }catch(error){if(current()){stopClothWorker();setClothMode('error');setClothMessage(error instanceof Error?error.message:String(error));}}
      };
      const simulateLootWorld = (time: number) => {
        const lootBake = preciseActive() ? preciseLootBake : quickPreview?.loot;
        lootInstances.forEach((instance, index) => {
          if (!lootBake || time < lootBake.releaseTimes[index]) { instance.group.visible = false; return; }
          const frame = THREE.MathUtils.clamp(time * lootBake.fps, 0, lootBake.frameCount - 1);
          const low = Math.floor(frame), high = Math.min(low + 1, lootBake.frameCount - 1), mix = frame - low;
          const data = lootBake.frames[index];
          const a = new THREE.Vector3().fromArray(data, low * 7);
          const b = new THREE.Vector3().fromArray(data, high * 7);
          const qa = new THREE.Quaternion().fromArray(data, low * 7 + 3);
          const qb = new THREE.Quaternion().fromArray(data, high * 7 + 3);
          instance.group.quaternion.copy(qa).slerp(qb, mix);
          const offset = instance.bounds.getCenter(new THREE.Vector3()).applyQuaternion(instance.group.quaternion);
          instance.group.position.copy(a).lerp(b, mix);
          // Rotation interpolation can lower a corner even if both cached
          // frames are valid. Apply the same non-penetration support constraint.
          instance.group.position.y=Math.max(instance.group.position.y,sequenceFloorHeight-lootBottom(instance.supportVertices,instance.group.quaternion));
          instance.group.position.sub(offset);
          instance.group.visible = true;
        });
      };
      const applySequence = (progress: number) => {
        const clamped = THREE.MathUtils.clamp(progress, 0, 1);
        renderedSequenceProgress = clamped;
        const sequenceTime = clamped * sequenceDurationSeconds;

        const axeAction = sequenceActions.find((action) => action.kind === 'axe')!;
        const axeActionStart = axeAction.start * sequenceDurationSeconds;
        const axeReleaseTime = axeActionStart + 0.11;
        const extraction = smoothstep(THREE.MathUtils.clamp(
          (sequenceTime - axeActionStart) / Math.max(0.001, axeReleaseTime - axeActionStart),
          0,
          1,
        ));
        const axeReleaseOrigin = axeOriginPosition.clone().add(new THREE.Vector3(0, 0.15, 0));
        if (sequenceTime < axeReleaseTime) {
          axe.position.lerpVectors(axeOriginPosition, axeReleaseOrigin, extraction);
          axe.quaternion.copy(axeOriginQuaternion);
        } else {
          const bake=preciseActive()?preciseLootBake:quickPreview?.loot;
          if(bake){
            const frame=THREE.MathUtils.clamp(sequenceTime*bake.fps,0,bake.frameCount-1);
            const lo=Math.floor(frame),hi=Math.min(lo+1,bake.frameCount-1),mix=frame-lo;
            const data=bake.frames[lootInstances.length];
            axe.quaternion.fromArray(data,lo*7+3).slerp(new THREE.Quaternion().fromArray(data,hi*7+3),mix);
            axe.position.fromArray(data,lo*7).lerp(new THREE.Vector3().fromArray(data,hi*7),mix);
            const vertices=boxVertices(axeLocalBounds.getSize(new THREE.Vector3()).multiplyScalar(.5).toArray());
            axe.position.y=Math.max(axe.position.y,sequenceFloorHeight-lootBottom(vertices,axe.quaternion));
            axe.position.sub(axeLocalBounds.getCenter(new THREE.Vector3()).applyQuaternion(axe.quaternion));
          }else{axe.position.copy(axeOriginPosition);axe.quaternion.copy(axeOriginQuaternion);}
        }

        updateDressedTextures(clamped);
        clothInstances.forEach((instance, index) => {
          const precise = preciseActive();
          const track = precise ? clothBake?.tracks[index] : quickPreview?.tracks[index];
          const detached = !!track && sequenceTime > track.releaseTime;
          instance.group.visible = !instance.bodyOverlay && !detached;
          // Worn geometry stays on the shared rig with an identity instance
          // transform. Detached geometry is solely the cached physical surface.
          instance.group.position.copy(instance.dressedPosition);
          instance.group.quaternion.identity(); instance.group.scale.setScalar(1);
          const mesh = detachedMeshes[index];
          if (mesh && clothBake) {
            mesh.visible = detached && precise;
            if (mesh.visible) {
              const position = mesh.geometry.getAttribute('position') as THREE.BufferAttribute;
              sampleCloth(clothBake.tracks[index], clothBake, sequenceTime, position.array as Float32Array);
              position.needsUpdate = true;
              const normals = mesh.geometry.getAttribute('normal') as THREE.BufferAttribute;
              clothNormals(clothBake.tracks[index], position.array as Float32Array, normals.array as Float32Array, mesh.geometry.userData.normalScratch);
              normals.needsUpdate = true;
              mesh.geometry.computeBoundingBox(); mesh.geometry.computeBoundingSphere();
            }
          }
          const quick = quickMeshes[index];
          if (quick && quickPreview) {
            quick.visible = detached && !precise;
            if (quick.visible) {
              const position = quick.geometry.getAttribute('position') as THREE.BufferAttribute;
              sampleCloth(quickPreview.tracks[index],quickPreview,sequenceTime,position.array as Float32Array);
              position.needsUpdate = true;
              const normals = quick.geometry.getAttribute('normal') as THREE.BufferAttribute;
              clothNormals(quickPreview.tracks[index],position.array as Float32Array,normals.array as Float32Array,quick.geometry.userData.normalScratch);
              normals.needsUpdate = true;
              quick.geometry.computeBoundingBox(); quick.geometry.computeBoundingSphere();
            }
          }
        });

        simulateLootWorld(sequenceTime);
        // Diagnose the very same completed frame that is about to be rendered.
        updateSkeletonVisuals();
        renderer.render(scene, camera);
      };

      const canvas = renderer.domElement;
      const handleGroup = new THREE.Group();
      const handleGeometry = new THREE.SphereGeometry(0.016, 14, 10);
      const handleMeshes: Partial<Record<HandleKey, THREE.Mesh>> = {};
      ragdollHandles.forEach((key) => {
        const handle = new THREE.Mesh(handleGeometry, new THREE.MeshBasicMaterial({ color: 0xc4ea39, depthTest: false, depthWrite: false }));
        handle.position.copy(pose.getHandlePosition(key));
        handle.userData.handle = key;
        handle.renderOrder = 100;
        handle.visible = ragdollEnabledRef.current;
        handleGroup.add(handle);
        handleMeshes[key] = handle;
      });
      content.add(handleGroup);

      const transformProxy = new THREE.Object3D();
      content.add(transformProxy);
      const transformControls = new TransformControls(camera, canvas);
      transformControls.setMode(transformModeRef.current);
      transformControls.setSpace('local');
      transformControls.setSize(0.72);
      const transformHelper = transformControls.getHelper();
      scene.add(transformHelper);
      const dropTransformControls = new TransformControls(camera, canvas);
      dropTransformControls.setMode('translate');
      dropTransformControls.setSpace('world');
      dropTransformControls.setSize(0.68);
      dropTransformControls.showX = true;
      dropTransformControls.showY = false;
      dropTransformControls.showZ = true;
      const dropTransformHelper = dropTransformControls.getHelper();
      scene.add(dropTransformHelper);

      ragdollRef.current = pose;
      rigModelsRef.current = [...rigModels.values()];
      handleMeshesRef.current = handleMeshes;

      const floorY = bodyBounds.min.y;
      const projectSurfaceFloor = (positions: Map<HandleKey, THREE.Vector3>, fixed: ReadonlySet<HandleKey>) => {
        // Re-evaluate toe support after articulation: rotating a calf rotates
        // the toe too. Solve bones, never clamp/render-warp the garment mesh.
        for(let pass=0;pass<3;pass++) {
          pose.setHandlePositions(positions);
          rigModels.forEach(model=>skinRigModel(model,pose));
          pose.updateFootSupports(rigModels.values());
          pose.projectHandles(positions,fixed,floorY);
        }
      };
      const skinModels = () => {
        rigModels.forEach((model) => skinRigModel(model, pose));
        if (!axeSurfaceAttachment) {
          updateRigAttachment(pose.boneGlobals().get('Bip01_Spine1')!,axeBoneLocal,axeOriginPosition,axeOriginQuaternion);
        } else {
          // Keep the last valid frame if a triangle briefly degenerates; never
          // switch reference frames and jump to a different place on the body.
          updateSurfaceAttachment(axeSurfaceAttachment,axeOriginPosition,axeOriginQuaternion);
        }
        // Sequencer garments use private geometry clones so they can deform
        // after being torn off.  Rebuild every clone from its newly skinned
        // source after each ragdoll edit; otherwise the body follows the new
        // pose while sleeves and trouser legs remain frozen in the old one.
        clothInstances.forEach(updateWornCloth);
        scheduleQuickPreview();
        applySequence(sequenceProgressRef.current);
        updateSkeletonVisuals();
      };
      const keepAboveFloor = () => {
        const positions = new Map<HandleKey, THREE.Vector3>(
          ragdollHandles.map((handle) => [
            handle,
            pose.clampHandleTarget(handle, pose.getHandlePosition(handle), floorY),
          ]),
        );
        const fixed = new Set(lockedHandlesRef.current);
        if ((transformControls.dragging || pointerDraggingHandle) && selectedHandleRef.current) {
          fixed.add(selectedHandleRef.current);
        }
        projectSurfaceFloor(positions,fixed);
        pose.setHandlePositions(positions);
        skinModels();
      };

      const updateHandles = () => {
        ragdollHandles.forEach((key) => handleMeshes[key]?.position.copy(pose.getHandlePosition(key)));
      };
      let hoveredHandle: HandleKey | null = null;
      let hoveredDropPoint: DropPointKind | null = null;
      const previousProxyQuaternion = new THREE.Quaternion();
      const refreshEditor = () => {
        ragdollHandles.forEach((key) => {
          const mesh = handleMeshes[key];
          if (!mesh) return;
          mesh.visible = ragdollEnabledRef.current;
          const material = mesh.material as THREE.MeshBasicMaterial;
          material.color.set(
            selectedHandleRef.current === key && lockedHandlesRef.current.has(key) ? 0xffa63d
              : selectedHandleRef.current === key ? 0x67e8f9
              : hoveredHandle === key ? 0xf4ff72
                : lockedHandlesRef.current.has(key) ? 0xffa63d : 0xc4ea39,
          );
          mesh.scale.setScalar(selectedHandleRef.current === key ? 1.3 : 1);
        });
        const selected = selectedHandleRef.current;
        if (ragdollEnabledRef.current && selected) {
          transformControls.enabled = true;
          transformControls.setMode(transformModeRef.current);
          if (transformControls.object !== transformProxy) transformControls.attach(transformProxy);
          if (!transformControls.dragging) {
            const position = transformModeRef.current === 'rotate'
              ? pose.getRotationPivot(selected)
              : pose.getHandlePosition(selected);
            transformProxy.position.copy(position);
            transformProxy.quaternion.identity();
            previousProxyQuaternion.identity();
          }
        } else {
          transformControls.enabled = false;
          transformControls.detach();
        }
        dropPointGroup.visible = dropPointsVisibleRef.current;
        dropPointKinds.forEach((kind) => {
          const marker = dropPointMeshes[kind];
          if (!marker) return;
          const highlighted = selectedDropPointRef.current === kind || hoveredDropPoint === kind;
          marker.traverse((object) => {
            if (!object.userData.dropPointColor) return;
            const material = (object as THREE.Mesh).material as THREE.MeshBasicMaterial;
            material.color.set(highlighted ? 0xffffff : Number(object.userData.dropPointColor));
          });
        });
        const selectedDrop = selectedDropPointRef.current;
        const selectedDropMesh = selectedDrop ? dropPointMeshes[selectedDrop] : null;
        if (dropPointsVisibleRef.current && selectedDropMesh) {
          dropTransformControls.enabled = true;
          if (dropTransformControls.object !== selectedDropMesh) dropTransformControls.attach(selectedDropMesh);
        } else {
          dropTransformControls.enabled = false;
          dropTransformControls.detach();
        }
        render();
      };
      let pointerDraggingHandle = false;
      const physicsPositions = new Map<HandleKey, THREE.Vector3>(
        ragdollHandles.map((handle) => [handle, pose.getHandlePosition(handle)]),
      );
      const previousPhysicsPositions = new Map<HandleKey, THREE.Vector3>(
        [...physicsPositions].map(([handle, position]) => [handle, position.clone()]),
      );
      const syncPhysicsFromPose = () => {
        ragdollHandles.forEach((handle) => {
          const position = pose.getHandlePosition(handle);
          physicsPositions.set(handle, position);
          previousPhysicsPositions.set(handle, position.clone());
        });
      };
      const resetMotion = () => {
        skinModels();
        syncPhysicsFromPose();
        updateHandles();
        refreshEditor();
      };
      const skinAll = (syncGizmo = true) => {
        keepAboveFloor();
        syncPhysicsFromPose();
        updateHandles();
        applySequence(sequenceProgressRef.current);
        if (syncGizmo) refreshEditor();
      };

      let transformChanged = false;
      const onTransformObjectChange = () => {
        const handle = selectedHandleRef.current;
        if (!handle) return;
        transformChanged = true;
        if (transformControls.mode === 'translate') {
          const target = pose.clampHandleTarget(handle, transformProxy.position, floorY);
          pose.dragHandle(handle, target, lockedHandlesRef.current, floorY);
        } else {
          const delta = transformProxy.quaternion.clone().multiply(previousProxyQuaternion.clone().invert()).normalize();
          const angle = 2 * Math.acos(THREE.MathUtils.clamp(delta.w, -1, 1));
          const divisor = Math.sqrt(Math.max(1e-8, 1 - delta.w * delta.w));
          if (angle > 1e-5) {
            const axis = new THREE.Vector3(delta.x / divisor, delta.y / divisor, delta.z / divisor).normalize();
            pose.rotateHandle(handle, axis, angle > Math.PI ? angle - Math.PI * 2 : angle);
          }
          previousProxyQuaternion.copy(transformProxy.quaternion);
        }
        skinAll(false);
        if (transformControls.mode === 'translate') transformProxy.position.copy(pose.getHandlePosition(handle));
      };
      const onTransformMouseDown = () => {
        transformChanged = false;
        syncPhysicsFromPose();
        previousProxyQuaternion.copy(transformProxy.quaternion);
      };
      const onTransformMouseUp = () => {
        if (transformChanged) syncPhysicsFromPose();
        transformChanged = false;
        transformProxy.quaternion.identity();
        previousProxyQuaternion.identity();
        refreshEditor();
      };
      transformControls.addEventListener('change', render);
      transformControls.addEventListener('objectChange', onTransformObjectChange);
      transformControls.addEventListener('mouseDown', onTransformMouseDown);
      transformControls.addEventListener('mouseUp', onTransformMouseUp);
      const beginDropEdit = () => {
        if (dropEditActive) return;
        dropEditActive = true;
        dropEditDirty = !!bakeTimer || !!clothWorker;
        if (bakeTimer) clearTimeout(bakeTimer);
        bakeTimer = null;
        stopPlayback();
        exportAbortRef.current?.abort();
        stopClothWorker();
      };
      const finishDropEdit = () => {
        if (!dropEditActive) return;
        dropEditActive = false;
        if (dropEditDirty) {
          dropEditDirty = false;
          saveDropLayout();
          scheduleQuickPreview(0);
        }
      };
      const onDropTransformChange = () => {
        const kind = selectedDropPointRef.current;
        const marker = kind ? dropPointMeshes[kind] : null;
        if (!kind || !marker) return;
        marker.position.y = floorPlane.position.y + 0.012;
        dropPointPositionsRef.current[kind] = { ...dropPointPositionsRef.current[kind], x: marker.position.x, z: marker.position.z };
        dropEditDirty = true;
        render();
      };
      dropTransformControls.addEventListener('change', render);
      dropTransformControls.addEventListener('objectChange', onDropTransformChange);
      dropTransformControls.addEventListener('mouseDown', beginDropEdit);
      dropTransformControls.addEventListener('mouseUp', finishDropEdit);

      let physicsFrame = 0;
      let physicsActive = false;
      let previousPhysicsTime = performance.now();
      const physicsStep = (time: number) => {
        if (!physicsActive || cancelled) return;
        const dt = Math.min(0.032, Math.max(0.001, (time - previousPhysicsTime) / 1000));
        previousPhysicsTime = time;
        {
          // The grabbed point is a temporary anchor; the rest of the body
          // continues to fall and solve constraints while the pointer is held.
          const locked = new Set(lockedHandlesRef.current);
          if ((transformControls.dragging || pointerDraggingHandle) && selectedHandleRef.current) {
            locked.add(selectedHandleRef.current);
          }
          const before = new Map<HandleKey, THREE.Vector3>(
            [...physicsPositions].map(([handle, position]) => [handle, position.clone()]),
          );
          ragdollHandles.forEach((handle) => {
            const position = physicsPositions.get(handle)!;
            const previous = previousPhysicsPositions.get(handle)!;
            if (locked.has(handle)) {
              previous.copy(position);
              return;
            }
            const velocity = position.clone().sub(previous).multiplyScalar(0.985).clampLength(0, 0.12);
            previous.copy(position);
            position.add(velocity);
            position.y -= 10.5 * dt * dt;
          });

          projectSurfaceFloor(physicsPositions,locked);

          const moved = ragdollHandles.some((handle) =>
            physicsPositions.get(handle)!.distanceToSquared(before.get(handle)!) > 1e-10);
          if (moved) {
            pose.setHandlePositions(physicsPositions);
            skinModels();
            updateHandles();
            refreshEditor();
          }
        }
        physicsFrame = requestAnimationFrame(physicsStep);
      };
      const setPhysics = (active: boolean) => {
        if (active === physicsActive) return;
        physicsActive = active;
        syncPhysicsFromPose();
        if (active) {
          previousPhysicsTime = performance.now();
          physicsFrame = requestAnimationFrame(physicsStep);
        } else if (physicsFrame) {
          cancelAnimationFrame(physicsFrame);
          physicsFrame = 0;
        }
      };

      const exportGif = async (
        targetBytes: number,
        onProgress: (message: string) => void,
        signal: AbortSignal,
      ): Promise<GifExportResult> => {
        const assertNotAborted = () => {
          if (signal.aborted || cancelled) throw new DOMException('Экспорт остановлен', 'AbortError');
        };
        assertNotAborted();
        // Capture before asynchronous imports: this is the view at button press.
        const { camera: exportCamera, width, height } = snapshotGifCamera(camera, targetBytes);
        const { GIFEncoder, quantize, applyPalette } = await import('gifenc');
        const { default: gifsicle } = await import('gifsicle-wasm-browser');
        assertNotAborted();
        const durationMs = sequenceDurationMs;
        const originalSequenceProgress = sequenceProgressRef.current;
        const handlesVisible = handleGroup.visible;
        const helperVisible = transformHelper.visible;
        const dropPointsWereVisible = dropPointGroup.visible;
        const dropHelperWasVisible = dropTransformHelper.visible;
        const skeletonsWereVisible = skeletonDebugRoot.visible;
        const wasPhysicsActive = physicsActive;
        const renderTarget = new THREE.WebGLRenderTarget(width, height, {
          minFilter: THREE.LinearFilter,
          magFilter: THREE.LinearFilter,
          format: THREE.RGBAFormat,
          type: THREE.UnsignedByteType,
          depthBuffer: true,
          stencilBuffer: false,
        });
        renderTarget.texture.colorSpace = THREE.SRGBColorSpace;
        const sourcePixels = new Uint8Array(width * height * 4);
        const pixels = new Uint8Array(sourcePixels.length);
        const rowBytes = width * 4;

        const capture = () => {
          const previousTarget = renderer.getRenderTarget();
          try {
            renderer.setRenderTarget(renderTarget);
            renderer.clear();
            renderer.render(scene, exportCamera);
            renderer.readRenderTargetPixels(renderTarget, 0, 0, width, height, sourcePixels);
          } finally {
            renderer.setRenderTarget(previousTarget);
          }
          for (let row = 0; row < height; row += 1) {
            const sourceOffset = (height - row - 1) * rowBytes;
            pixels.set(sourcePixels.subarray(sourceOffset, sourceOffset + rowBytes), row * rowBytes);
          }
          return pixels;
        };

        const optimizeGif = async (source: Blob, frameCount: number) => {
          assertNotAborted();
          onProgress(`${frameCount} кадров · оптимизация`);
          const outputs = await gifsicle.run({
            input: [{ file: source, name: 'source.gif' }],
            command: ['-O3 source.gif -o /out/optimized.gif'],
          });
          const optimized = outputs.find((file) => file.name.endsWith('optimized.gif')) ?? outputs[0];
          if (!optimized) throw new Error('Не удалось оптимизировать GIF');
          assertNotAborted();
          return new Blob([await optimized.arrayBuffer()], { type: 'image/gif' });
        };

        const encodeAttempt = async (frameCount: number, paletteColors: number) => {
          assertNotAborted();
          onProgress(`${frameCount} кадров`);
          const gif = GIFEncoder({ initialCapacity: Math.min(targetBytes * 2, 16 * 1024 * 1024) });
          const delay = Math.max(20, Math.round(durationMs / frameCount));
          for (let frame = 0; frame < frameCount; frame += 1) {
            assertNotAborted();
            const progress = frame / Math.max(1, frameCount - 1);
            applySequence(progress);
            const rgba = capture();
            const palette = quantize(rgba, paletteColors, { format: 'rgb444' });
            const index = applyPalette(rgba, palette, 'rgb444');
            gif.writeFrame(index, width, height, { palette, delay, repeat: 0, dispose: 1 });
            if (frame % 3 === 2) await new Promise<void>((resolve) => setTimeout(resolve, 0));
          }
          gif.finish();
          const bytes = gif.bytes();
          const data = new Uint8Array(bytes.byteLength);
          data.set(bytes);
          const encoded = new Blob([data.buffer], { type: 'image/gif' });
          const optimized = await optimizeGif(encoded, frameCount);
          return {
            blob: optimized,
            frames: frameCount,
            paletteColors,
          } satisfies GifExportResult;
        };

        setPhysics(false);
        handleGroup.visible = false;
        transformHelper.visible = false;
        dropPointGroup.visible = false;
        dropTransformHelper.visible = false;
        skeletonDebugRoot.visible = false;

        try {
          // Export the currently selected preview mode. It never requests cloth
          // calculation; a worker finishing mid-export cannot mix the two modes.
          if (!quickPreview) await rebuildQuickPreview();
          if (!quickPreview) throw new Error('Быстрый предпросмотр ещё не готов');
          exportUsesPrecise = usePreciseCloth && !!clothBake;
          assertNotAborted();
          let low = 24;
          let high = 200;
          let best: GifExportResult | null = null;
          while (low <= high) {
            assertNotAborted();
            const frameCount = Math.floor((low + high) / 2);
            const attempt = await encodeAttempt(frameCount, 256);
            if (attempt.blob.size < targetBytes) {
              best = attempt;
              low = frameCount + 1;
            } else {
              high = frameCount - 1;
            }
          }

          if (!best) {
            for (const paletteColors of [192, 128, 96, 64, 48, 32, 24, 16]) {
              assertNotAborted();
              const attempt = await encodeAttempt(12, paletteColors);
              if (attempt.blob.size < targetBytes) {
                best = attempt;
                break;
              }
            }
          }
          if (!best) throw new Error('Лимит слишком мал');
          return best;
        } finally {
          exportUsesPrecise = null;
          renderer.setRenderTarget(null);
          renderTarget.dispose();
          handleGroup.visible = handlesVisible;
          transformHelper.visible = helperVisible;
          dropPointGroup.visible = dropPointsWereVisible;
          dropTransformHelper.visible = dropHelperWasVisible;
          skeletonDebugRoot.visible = skeletonsWereVisible;
          if (!cancelled) {
            applySequence(originalSequenceProgress);
            if (wasPhysicsActive) setPhysics(true);
          }
        }
      };

      editorControllerRef.current = {
        setPhysics,
        resetMotion,
        refresh: refreshEditor,
        setDropPointsVisible: (visible) => {
          dropPointGroup.visible = visible;
          if (!visible) dropTransformControls.detach();
          refreshEditor();
        },
        setDropPointPositions: (positions) => {
          scheduleQuickPreview();
          dropPointKinds.forEach((kind) => {
            const marker = dropPointMeshes[kind];
            marker?.getObjectByName('spread-ring')?.scale.setScalar(positions[kind].radius);
            if (marker) marker.position.set(
              positions[kind].x,
              floorPlane.position.y + 0.012,
              positions[kind].z,
            );
          });
          applySequence(sequenceProgressRef.current);
          refreshEditor();
        },
        setSkeletonDebug,
        setSequenceProgress: applySequence,
        calculateCloth,
        exportPhysicsSnapshot,
        importBlenderCache,
        calculateBlender,
        cancelCloth,
        showPreciseCloth,
        exportGif,
      };
      refreshEditor();
      setPhysics(ragdollEnabledRef.current);
      applySequence(sequenceProgressRef.current);
      scheduleQuickPreview(0);

      const raycaster = new THREE.Raycaster();
      const pointer = new THREE.Vector2();
      const planeIntersection = new THREE.Vector3();
      type DragState =
        | {
          kind: 'scene';
          startX: number;
          startY: number;
          startRotation: number;
          startCameraPan: number;
          pointerId: number;
        }
        | { kind: 'handle'; handle: HandleKey; plane: THREE.Plane; startLocalHit: THREE.Vector3; startPosition: THREE.Vector3; pointerId: number; moved: boolean }
        | { kind: 'drop-point'; point: DropPointKind; resize:boolean; plane: THREE.Plane; grabOffset: THREE.Vector3; pointerId: number }
        | null;
      let drag: DragState = null;

      const updateRay = (event: PointerEvent) => {
        const bounds = canvas.getBoundingClientRect();
        pointer.x = ((event.clientX - bounds.left) / bounds.width) * 2 - 1;
        pointer.y = -((event.clientY - bounds.top) / bounds.height) * 2 + 1;
        raycaster.setFromCamera(pointer, camera);
      };
      const onPointerDown = (event: PointerEvent) => {
        if (transformControls.dragging || transformControls.axis || dropTransformControls.dragging || dropTransformControls.axis) return;
        updateRay(event);
        if (dropPointsVisibleRef.current) {
          const dropHits = raycaster.intersectObjects(
            Object.values(dropPointMeshes).filter(Boolean) as THREE.Group[],
            true,
          );
          const point = dropHits[0]?.object.userData.dropPoint as DropPointKind | undefined;
          const marker = point ? dropPointMeshes[point] : null;
          if (point && marker) {
            selectedDropPointRef.current = point;
            setSelectedDropPoint(point);
            selectedHandleRef.current = null;
            setSelectedHandle(null);
            const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), -marker.position.y);
            if (raycaster.ray.intersectPlane(plane, planeIntersection)) {
              beginDropEdit();
              drag = {
                kind: 'drop-point',
                resize:!!dropHits[0]?.object.userData.resizeDropPoint,
                point,
                plane,
                grabOffset: marker.position.clone().sub(planeIntersection),
                pointerId: event.pointerId,
              };
            }
            refreshEditor();
          } else if (selectedDropPointRef.current) {
            selectedDropPointRef.current = null;
            setSelectedDropPoint(null);
            refreshEditor();
          }
        }
        if (!drag && ragdollEnabledRef.current) {
          const hits = raycaster.intersectObjects(Object.values(handleMeshes).filter(Boolean) as THREE.Mesh[], false);
          const handle = hits[0]?.object.userData.handle as HandleKey | undefined;
          if (handle) {
            pointerDraggingHandle = true;
            syncPhysicsFromPose();
            selectedHandleRef.current = handle;
            setSelectedHandle(handle);
            const worldPoint = hits[0].object.getWorldPosition(new THREE.Vector3());
            const plane = new THREE.Plane().setFromNormalAndCoplanarPoint(camera.getWorldDirection(new THREE.Vector3()), worldPoint);
            if (raycaster.ray.intersectPlane(plane, planeIntersection)) {
              drag = {
                kind: 'handle',
                handle,
                plane,
                startLocalHit: content.worldToLocal(planeIntersection.clone()),
                startPosition: pose.getHandlePosition(handle),
                pointerId: event.pointerId,
                moved: false,
              };
            }
            refreshEditor();
          } else {
            selectedHandleRef.current = null;
            setSelectedHandle(null);
            refreshEditor();
          }
        }
        if (!drag) {
          drag = {
            kind: 'scene',
            startX: event.clientX,
            startY: event.clientY,
            startRotation: rotationRef.current,
            startCameraPan: cameraPanRef.current,
            pointerId: event.pointerId,
          };
        }
        canvas.setPointerCapture(event.pointerId);
        canvas.classList.add('dragging');
        event.preventDefault();
      };
      const onPointerMove = (event: PointerEvent) => {
        if (!drag) {
          if (transformControls.axis || dropTransformControls.axis) {
            canvas.classList.add('gizmo-hover');
            return;
          }
          canvas.classList.remove('gizmo-hover');
          updateRay(event);
          const dropHits = dropPointsVisibleRef.current
            ? raycaster.intersectObjects(Object.values(dropPointMeshes).filter(Boolean) as THREE.Group[], true)
            : [];
          const nextDropHover = dropHits[0]?.object.userData.dropPoint as DropPointKind | undefined;
          if ((nextDropHover ?? null) !== hoveredDropPoint) {
            hoveredDropPoint = nextDropHover ?? null;
            canvas.classList.toggle('drop-point-hover', Boolean(hoveredDropPoint));
            refreshEditor();
          }
          const hits = ragdollEnabledRef.current
            ? raycaster.intersectObjects(Object.values(handleMeshes).filter(Boolean) as THREE.Mesh[], false)
            : [];
          const nextHover = hits[0]?.object.userData.handle as HandleKey | undefined;
          if ((nextHover ?? null) !== hoveredHandle) {
            hoveredHandle = nextHover ?? null;
            canvas.classList.toggle('handle-hover', Boolean(hoveredHandle));
            refreshEditor();
          }
          return;
        }
        if (drag.kind === 'scene') {
          const rotation = drag.startRotation + (event.clientX - drag.startX) * 0.012;
          rotationRef.current = rotation;
          applyCameraPan(cameraPanRef.current);
          if (!cameraPanLockedRef.current) {
            const bounds = canvas.getBoundingClientRect();
            const cameraPan = drag.startCameraPan - ((event.clientY - drag.startY) / bounds.height) * (3.85 / zoomRef.current);
            cameraPanRef.current = cameraPan;
            applyCameraPan(cameraPan);
          }
          render();
        } else if (drag.kind === 'handle') {
          updateRay(event);
          if (raycaster.ray.intersectPlane(drag.plane, planeIntersection)) {
            const currentLocalHit = content.worldToLocal(planeIntersection.clone());
            const target = drag.startPosition.clone().add(currentLocalHit.sub(drag.startLocalHit));
            if (target.distanceToSquared(drag.startPosition) > 1e-7) drag.moved = true;
            pose.dragHandle(drag.handle, target, lockedHandlesRef.current, floorY);
            skinAll();
          }
        } else {
          updateRay(event);
          const marker = dropPointMeshes[drag.point];
          if (marker && raycaster.ray.intersectPlane(drag.plane, planeIntersection)) {
            if(drag.resize) {
              const radius=clampDropRadius(Math.hypot(planeIntersection.x-marker.position.x,planeIntersection.z-marker.position.z));
              dropPointPositionsRef.current[drag.point].radius=radius;
              marker.getObjectByName('spread-ring')?.scale.setScalar(radius);
            } else {
              marker.position.copy(planeIntersection).add(drag.grabOffset);
              marker.position.y = floorPlane.position.y + 0.012;
              dropPointPositionsRef.current[drag.point] = { ...dropPointPositionsRef.current[drag.point], x: marker.position.x, z: marker.position.z };
            }
            dropEditDirty = true;
            render();
          }
        }
        event.preventDefault();
      };
      const finishPointer = (event: PointerEvent) => {
        if (!drag || drag.pointerId !== event.pointerId) return;
        const handleWasMoved = drag.kind === 'handle' && drag.moved;
        const dropWasEdited = drag.kind === 'drop-point';
        drag = null;
        if (dropWasEdited) finishDropEdit();
        pointerDraggingHandle = false;
        if (handleWasMoved) syncPhysicsFromPose();
        canvas.classList.remove('dragging');
        canvas.classList.toggle('handle-hover', Boolean(hoveredHandle));
        canvas.classList.toggle('drop-point-hover', Boolean(hoveredDropPoint));
        if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
      };
      const onPointerLeave = () => {
        if (!drag) {
          hoveredHandle = null;
          hoveredDropPoint = null;
          canvas.classList.remove('handle-hover', 'drop-point-hover', 'gizmo-hover');
          refreshEditor();
        }
      };
      const onWheel = (event: WheelEvent) => {
        const zoom = THREE.MathUtils.clamp(zoomRef.current * Math.exp(-event.deltaY * 0.001), 0.55, 2.8);
        zoomRef.current = zoom;
        camera.zoom = zoom;
        camera.updateProjectionMatrix();
        render();
        event.preventDefault();
      };

      canvas.addEventListener('pointerdown', onPointerDown);
      canvas.addEventListener('pointermove', onPointerMove);
      canvas.addEventListener('pointerup', finishPointer);
      canvas.addEventListener('pointercancel', finishPointer);
      canvas.addEventListener('pointercancel', finishDropEdit);
      canvas.addEventListener('lostpointercapture', finishDropEdit);
      canvas.addEventListener('pointerleave', onPointerLeave);
      canvas.addEventListener('wheel', onWheel, { passive: false });
      detachInteractions = () => {
        setPhysics(false);
        transformControls.removeEventListener('change', render);
        transformControls.removeEventListener('objectChange', onTransformObjectChange);
        transformControls.removeEventListener('mouseDown', onTransformMouseDown);
        transformControls.removeEventListener('mouseUp', onTransformMouseUp);
        transformControls.dispose();
        dropTransformControls.removeEventListener('change', render);
        dropTransformControls.removeEventListener('objectChange', onDropTransformChange);
        dropTransformControls.removeEventListener('mouseDown', beginDropEdit);
        dropTransformControls.removeEventListener('mouseUp', finishDropEdit);
        dropTransformControls.dispose();
        canvas.removeEventListener('pointerdown', onPointerDown);
        canvas.removeEventListener('pointermove', onPointerMove);
        canvas.removeEventListener('pointerup', finishPointer);
        canvas.removeEventListener('pointercancel', finishPointer);
        canvas.removeEventListener('pointercancel', finishDropEdit);
        canvas.removeEventListener('lostpointercapture', finishDropEdit);
        canvas.removeEventListener('pointerleave', onPointerLeave);
        canvas.removeEventListener('wheel', onWheel);
      };
      disposeLoaded = () => {
        stopClothWorker();
        stopQuickWorker();
        if (bakeTimer) clearTimeout(bakeTimer);
        clearDetachedMeshes(); clearQuickMeshes();
        if (preservePoseOnReloadRef.current && ragdollRef.current === pose) {
          preservedPoseStateRef.current = pose.captureState();
        }
        rigModels.forEach(disposeRigModel);
        bodyMaterial.dispose();
        garmentMaterials.forEach((material) => material.dispose());
        dynamicTextures.forEach((texture) => texture.dispose());
        sequenceMaterials.forEach((material) => material.dispose());
        hairMaterial?.dispose();
        if (hairMaterialRef.current === hairMaterial) hairMaterialRef.current = null;
        textures.forEach((texture) => texture.dispose());
        floorGeometry.dispose();
        floorMaterial.dispose();
        handleGeometry.dispose();
        clothInstances.forEach((instance) => instance.meshes.forEach(({ geometry }) => geometry.dispose()));
        lootInstances.forEach(instance=>instance.group.traverse(object=>{const mesh=object as THREE.Mesh;if(mesh.isMesh)mesh.geometry.dispose();}));
        dropPointDisposables.forEach((resource) => resource.dispose());
        skeletonDebugDisposables.forEach((resource) => resource.dispose());
        Object.values(handleMeshes).forEach((handle) => (handle?.material as THREE.Material | undefined)?.dispose());
      };
      render();
    }).catch((error: unknown) => {
      if (cancelled) return;
      console.error(error);
      setSimulationBusy(false); setSimulationStatus('Ошибка загрузки сцены: ' + String(error));
    });

    return () => {
      cancelled = true;
      exportAbortRef.current?.abort();
      detachInteractions();
      resizeObserver.disconnect();
      disposeLoaded();
      ragdollRef.current = null;
      rigModelsRef.current = [];
      handleMeshesRef.current = {};
      dropPointMeshesRef.current = {};
      editorControllerRef.current = null;
      renderer.dispose();
      renderer.domElement.remove();
      if (rendererRef.current === renderer) rendererRef.current = null;
      if (sceneRef.current === scene) sceneRef.current = null;
      if (cameraRef.current === camera) cameraRef.current = null;
    };
  }, [settingsLoaded, bodyVariant, floor, layeredGarments, modelSet, normalizedLootItems, render, selection.hair, selection.pose, sequenceActions, sequenceDurationSeconds, sex, stopPlayback]);

  const updateSelection = <K extends keyof Selection>(key: K, value: Selection[K]) => {
    setSelection((current) => ({ ...current, [key]: value }));
  };

  const changeBody = (value: string) => {
    const nextSex = value.slice(0, 1) as Sex;
    setSelection((current) => ({
      ...current,
      body: value,
      hair: hairOptions[nextSex].some((option) => option.value === current.hair)
        ? current.hair
        : (hairOptions[nextSex][1]?.value ?? 'none'),
    }));
    setGarments((current) => current.flatMap((garment) => {
      const variants = garmentDefinitions[garment.type].variants[nextSex];
      if (variants.length === 0) return [];
      const variant = variants.some((option) => option.value === garment.variant) ? garment.variant : variants[0].value;
      return [{ ...garment, variant }];
    }));
    if (garmentDefinitions[addType].variants[nextSex].length === 0) {
      setAddType(garmentTypeOrder.find((type) => garmentDefinitions[type].variants[nextSex].length > 0) ?? 'shirt');
    }
  };

  const addGarment = () => {
    const variant = garmentDefinitions[addType].variants[sex][0]?.value;
    if (!variant) return;
    setGarments((current) => [...current, { id: nextGarmentIdRef.current++, type: addType, variant }]);
  };

  const updateGarment = (id: number, variant: string) => {
    setGarments((current) => current.map((garment) => garment.id === id ? { ...garment, variant } : garment));
  };

  const removeGarment = (id: number) => {
    setGarments((current) => current.filter((garment) => garment.id !== id));
    setLockedGarmentIds((current) => {
      const next = new Set(current);
      next.delete(id);
      return next;
    });
  };

  const toggleGarmentLock = (id: number) => {
    setLockedGarmentIds((current) => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const addLootItem = () => {
    const layer = garmentLayers.at(-1)?.[0] ?? 0;
    setLootItems((current) => [...current, {
      id: nextLootIdRef.current++,
      kind: normalizePocketId(addLootKind,sex) ?? 'Base.Wallet_Male',
      layer,
    }]);
  };

  const updateLootItem = (id: number, patch: Partial<Pick<LootItem, 'kind' | 'layer'>>) => {
    setLootItems((current) => current.map((item) => item.id === id ? { ...item, ...patch } : item));
  };

  const removeLootItem = (id: number) => {
    setLootItems((current) => current.filter((item) => item.id !== id));
  };

  const randomize = () => {
    stopPlayback();
    sequenceProgressRef.current = 0;
    setSequenceProgress(0);
    editorControllerRef.current?.setSequenceProgress(0);
    preservePoseOnReloadRef.current = locks.pose;
    if (!locks.pose) preservedPoseStateRef.current = null;
    const constrainedSex = locks.hair || locks.clothing || lockedGarmentIds.size > 0 ? sex : null;
    const bodyPool = constrainedSex ? bodyOptions.filter((option) => option.value.startsWith(`${constrainedSex}-`)) : bodyOptions;
    const body = locks.body ? selection.body : randomItem(bodyPool).value;
    const nextSex = body.slice(0, 1) as Sex;
    const pieces: Omit<Garment, 'id'>[] = [];
    const addRandom = (type: GarmentType) => {
      const variants = garmentDefinitions[type].variants[nextSex];
      if (variants.length > 0) pieces.push({ type, variant: randomItem(variants).value });
    };
    addRandom('underpants');
    if (nextSex === 'f' && Math.random() < 0.8) addRandom('bra');
    if (Math.random() < 0.9) addRandom('shirt');
    addRandom(randomItem(['trousers', 'shorts', 'shortshorts', 'suittrousers'] as GarmentType[]));
    if (Math.random() < 0.55) addRandom(randomItem(['jumper', 'hoodie'] as GarmentType[]));
    if (Math.random() < 0.7) addRandom(randomItem(['jacket', 'suitjacket', 'longcoat', 'apron', 'bulletvest'] as GarmentType[]));
    setSelection({
      body,
      pose: locks.pose ? selection.pose : 'front',
      hair: locks.hair ? selection.hair : randomItem(hairOptions[nextSex]).value as HairKey,
      hairColor: locks.hairColor ? selection.hairColor : `#${Math.floor(Math.random() * 0xffffff).toString(16).padStart(6, '0')}`,
    });
    if (!locks.floor) setFloor(randomItem(floorOptions).value);
    let nextGarments = garments;
    if (!locks.clothing) {
      const preserved = garments.filter((garment) => lockedGarmentIds.has(garment.id));
      const preservedTypes = new Set(preserved.map((garment) => garment.type));
      const randomized = pieces
        .filter((piece) => !preservedTypes.has(piece.type))
        .map((piece) => ({ ...piece, id: nextGarmentIdRef.current++ }));
      nextGarments = [...preserved, ...randomized];
      setGarments(nextGarments);
      setLockedGarmentIds(new Set(preserved.map((garment) => garment.id)));
    }
    if (!locks.loot) {
      const nextLoot: LootItem[] = [];
      const grouped = new Map<number, LayeredGarment[]>();
      calculateLayers(nextGarments).forEach((garment) => {
        const group = grouped.get(garment.level) ?? [];
        group.push(garment);
        grouped.set(garment.level, group);
      });
      const layers=[...grouped.keys()];
      const pocket=generatePocketLoot(nextSex,Math.min(5,layers.length+2));
      pocket.items.forEach((kind,index)=>{
        if(layers.length) nextLoot.push({id:nextLootIdRef.current++,kind,layer:layers[index%layers.length]});
      });
      setLootItems(nextLoot);
    }
  };

  const runGifExport = async () => {
    stopPlayback();
    const exporter = editorControllerRef.current?.exportGif;
    if (!exporter || exporting) return;
    const abortController = new AbortController();
    exportAbortRef.current = abortController;
    setExporting(true);
    setExportPreviewVisible(false);
    setExportResult(null);
    setExportStatus('Подготовка');
    try {
      const result = await exporter(
        Math.round(exportTargetMb * 1_000_000),
        (message) => {
          if (!abortController.signal.aborted) setExportStatus(message);
        },
        abortController.signal,
      );
      if (abortController.signal.aborted) return;
      setExportResult({ ...result, url: URL.createObjectURL(result.blob) });
      setExportStatus(`${result.frames} кадров · ${Math.round(result.blob.size / 1000)} КБ`);
    } catch (error) {
      setExportStatus(abortController.signal.aborted
        ? 'Остановлено'
        : error instanceof Error ? error.message : 'Ошибка экспорта');
    } finally {
      if (exportAbortRef.current === abortController) {
        exportAbortRef.current = null;
        setExporting(false);
      }
    }
  };

  const stopGifExport = () => {
    if (!exportAbortRef.current) return;
    exportAbortRef.current.abort();
    setExportStatus('Остановка…');
  };

  const toggleExportPanel = () => {
    if (exportOpen) {
      stopGifExport();
      setExportOpen(false);
      setExportPreviewVisible(false);
      return;
    }
    setExportOpen(true);
    void runGifExport();
  };

  return (
    <main className="tool">
      <section className="viewport" aria-label="Предпросмотр">
        <div className="scene-stage" aria-label="Кадр GIF 16:9">
          <div className="scene" ref={mountRef} />
        </div>
        <div className="viewport-tools" aria-label="Инструменты вьюпорта">
          <button
            className={cameraPanLocked ? 'locked' : ''}
            type="button"
            onClick={toggleCameraPanLock}
            aria-pressed={cameraPanLocked}
            aria-label={`${cameraPanLocked ? 'Разблокировать' : 'Заблокировать'} перемещение центра камеры`}
            title={`${cameraPanLocked ? 'Разблокировать' : 'Заблокировать'} перемещение центра камеры`}
          >
            <svg viewBox="0 0 24 24" aria-hidden="true">
              <circle cx="9" cy="9" r="4" />
              <path d="M9 2v2M9 14v2M2 9h2M14 9h2" />
              <rect x="13.5" y="14" width="7.5" height="6.5" rx="1.2" />
              <path d={cameraPanLocked ? 'M15.5 14v-1.5a1.75 1.75 0 0 1 3.5 0V14' : 'M15.5 14v-1.5a1.75 1.75 0 0 1 3.25-1'} />
            </svg>
          </button>
          <button
            className={dropPointsVisible ? 'active' : ''}
            type="button"
            onClick={toggleDropPoints}
            aria-pressed={dropPointsVisible}
            aria-label={`${dropPointsVisible ? 'Скрыть' : 'Показать'} точки сброса`}
            title={`${dropPointsVisible ? 'Скрыть' : 'Показать'} точки сброса`}
          >
            <svg viewBox="0 0 24 24" aria-hidden="true">
              <circle cx="6" cy="7" r="2.5" />
              <circle cx="18" cy="7" r="2.5" />
              <circle cx="12" cy="17" r="2.5" />
              <path d="M8.5 7h7M7.6 9l3 5.5M16.4 9l-3 5.5" />
            </svg>
          </button>
          <button
            className={skeletonDebugVisible ? 'active' : ''}
            type="button"
            onClick={toggleSkeletonDebug}
            aria-pressed={skeletonDebugVisible}
            aria-label={`${skeletonDebugVisible ? 'Скрыть' : 'Показать'} сравнение скелетов`}
            title={`${skeletonDebugVisible ? 'Скрыть' : 'Показать'} скелеты тела и одежды`}
          >
            <svg viewBox="0 0 24 24" aria-hidden="true">
              <circle cx="7" cy="6" r="2" /><circle cx="17" cy="6" r="2" />
              <circle cx="7" cy="18" r="2" /><circle cx="17" cy="18" r="2" />
              <path d="M8.5 7.5l7 9M15.5 7.5l-7 9M9 6h6M9 18h6" />
            </svg>
          </button>
          <button
            className={exportOpen ? 'active' : ''}
            type="button"
            onClick={toggleExportPanel}
            aria-pressed={exportOpen}
            aria-label={exportOpen ? 'Закрыть экспорт GIF' : 'Открыть экспорт GIF'}
            title={exportOpen ? 'Закрыть экспорт GIF' : 'Экспорт GIF'}
          >
            <svg viewBox="0 0 24 24" aria-hidden="true">
              <rect x="3" y="4" width="18" height="16" rx="2" />
              <path d="M7 8h10M12 9v7m0 0-3-3m3 3 3-3" />
            </svg>
          </button>
          <span className="tool-divider" />
          <button
            className={ragdollEnabled ? 'active' : ''}
            type="button"
            onClick={() => {
              stopPlayback();
              if (!ragdollEnabled) scrubSequence(0);
              setRagdollEnabled((current) => !current);
            }}
            aria-pressed={ragdollEnabled}
            aria-label={`${ragdollEnabled ? 'Выключить' : 'Включить'} рэгдолл`}
            title={`${ragdollEnabled ? 'Выключить' : 'Включить'} рэгдолл`}
          >
            <svg viewBox="0 0 24 24" aria-hidden="true">
              <circle cx="12" cy="4" r="2" />
              <path d="M12 6v6m0-3L7 12m5-3 5 3m-5 0-4 7m4-7 4 7" />
              <circle cx="7" cy="12" r="1" /><circle cx="17" cy="12" r="1" />
              <circle cx="8" cy="19" r="1" /><circle cx="16" cy="19" r="1" />
            </svg>
          </button>
          <button type="button" onClick={resetRagdoll} aria-label="Сбросить позу" title="Сбросить позу и остановить рэгдолл">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 8V3m0 5h5M5.5 7A8 8 0 1 1 4 15" /></svg>
          </button>
          {ragdollEnabled && (
            <>
              <span className="tool-divider" />
              <button
                className={transformMode === 'translate' ? 'active' : ''}
                type="button"
                onClick={() => setTransformMode('translate')}
                aria-label="Перемещение"
                title="Перемещение"
              >
                <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2v20M2 12h20M12 2l-3 3m3-3 3 3m7 7-3-3m3 3-3 3M12 22l-3-3m3 3 3-3M2 12l3-3m-3 3 3 3" /></svg>
              </button>
              <button
                className={transformMode === 'rotate' ? 'active' : ''}
                type="button"
                onClick={() => setTransformMode('rotate')}
                aria-label="Вращение"
                title="Вращение"
              >
                <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 7v5h-5M4 17v-5h5M18.5 10A7 7 0 0 0 6 7.5L4 10m2 4a7 7 0 0 0 12 2.5L20 14" /></svg>
              </button>
              <span className="tool-divider" />
              <button
                className={selectedHandle && lockedHandles.has(selectedHandle) ? 'locked' : ''}
                type="button"
                onClick={toggleSelectedHandleLock}
                disabled={!selectedHandle}
                aria-label={selectedHandle ? `${lockedHandles.has(selectedHandle) ? 'Освободить' : 'Зафиксировать'} ${handleLabels[selectedHandle]} ${lockedHandles.has(selectedHandle) ? 'для гравитации' : 'от гравитации'}` : 'Сначала выберите точку'}
                title={selectedHandle ? `${lockedHandles.has(selectedHandle) ? 'Освободить для гравитации' : 'Зафиксировать от гравитации'}: ${handleLabels[selectedHandle]}` : 'Сначала выберите точку'}
              >{selectedHandle && lockedHandles.has(selectedHandle) ? '🔒' : '🔓'}</button>
            </>
          )}
        </div>
        {skeletonDebugVisible && (
          <section className="skeleton-debug-float" aria-label="Сравнение скелетов тела и одежды">
            <header>
              <strong>Скелеты: тело ↔ одежда</strong>
              <button type="button" onClick={toggleSkeletonDebug} aria-label="Закрыть сравнение скелетов">×</button>
            </header>
            <p>Белый — тело, пунктир — выбранная одежда. Δ — расстояние между суставами в текущем кадре с учётом поворота одежды.</p>
            <div className="skeleton-debug-list">
              {skeletonDiagnostics.filter(({ id }) => id !== 'body').map((diagnostic) => (
                <button
                  key={diagnostic.id}
                  className={skeletonDebugTarget === diagnostic.id ? 'active' : ''}
                  type="button"
                  title={`Исходный bind: ${diagnostic.maxJointDeltaMm.toFixed(2)} мм. Поворот экземпляра: ${diagnostic.instanceRotationDeg.toFixed(2)}°.`}
                  onClick={() => selectSkeletonDebugTarget(diagnostic.id)}
                >
                  <span className="skeleton-swatch" style={{ background: diagnostic.color }} />
                  <span className="skeleton-debug-name">{diagnostic.label}</span>
                  <span className="skeleton-debug-delta">
                    {diagnostic.detached ? 'Ткань' : `Δ ${diagnostic.posedJointDeltaMm < 0.01 ? '0' : diagnostic.posedJointDeltaMm.toFixed(2)} мм`}
                  </span>
                </button>
              ))}
            </div>
            {skeletonDiagnostics.filter(({ id }) => id === skeletonDebugTarget).map((diagnostic) => (
              <p key={diagnostic.id}>
                Исходный bind: {diagnostic.maxJointDeltaMm.toFixed(2)} мм · Поворот одежды: {diagnostic.instanceRotationDeg.toFixed(2)}°
                <br />Источник модели: {rigAssetSource(diagnostic.model, sex, modelSet)}
              </p>
            ))}
            {skeletonDiagnostics.length <= 1 && <span className="skeleton-debug-empty">На теле нет отдельных моделей одежды.</span>}
          </section>
        )}
        {exportOpen && (
          <section className="export-float" aria-label="Экспорт GIF">
            <header>
              <strong>Экспорт GIF</strong>
              <button type="button" onClick={toggleExportPanel} aria-label="Закрыть экспорт">×</button>
            </header>
            <label className="export-limit">
              <span>Максимальный размер</span>
              <span className="export-size-input">
                <input
                  type="number"
                  min="0.1"
                  max="4"
                  step="0.1"
                  value={exportTargetMb}
                  disabled={exporting}
                  onChange={(event) => setExportTargetMb(Math.max(0.1, Math.min(4, Number(event.target.value) || 1)))}
                  aria-label="Максимальный размер GIF в мегабайтах"
                />
                <span>МБ</span>
              </span>
            </label>
            <button
              className={`export-action${exporting ? ' stop' : ''}`}
              type="button"
              onClick={exporting ? stopGifExport : runGifExport}
            >
              {exporting ? 'Остановить' : exportResult ? 'Пересобрать' : 'Собрать GIF'}
            </button>
            <output className="export-status">{exportStatus || 'Готово к экспорту'}</output>
            {exportResult && (
              <div
                className="export-result"
                onMouseEnter={() => setExportPreviewVisible(true)}
                onMouseLeave={() => setExportPreviewVisible(false)}
              >
                <img src={exportResult.url} alt="GIF секвенции снятия одежды" />
                <a href={exportResult.url} download="project-zomboid-layer-teardown.gif">Скачать GIF</a>
              </div>
            )}
          </section>
        )}
        {dropPointsVisible && <div className="drop-point-help">Центр — перемещение · край окружности — разброс</div>}
        <div className="sequencer" aria-label="Секвенсор снятия одежды">
          <div
            className="sequence-track"
            onPointerDown={(event) => {
              if (simulationBusy) return;
              stopPlayback();
              sequenceScrubbingRef.current = event.pointerId;
              event.currentTarget.setPointerCapture(event.pointerId);
              const bounds = event.currentTarget.getBoundingClientRect();
              scrubSequence((event.clientX - bounds.left) / bounds.width);
            }}
            onPointerMove={(event) => {
              if (sequenceScrubbingRef.current !== event.pointerId) return;
              const bounds = event.currentTarget.getBoundingClientRect();
              scrubSequence((event.clientX - bounds.left) / bounds.width);
            }}
            onPointerUp={(event) => {
              if (sequenceScrubbingRef.current !== event.pointerId) return;
              sequenceScrubbingRef.current = null;
              event.currentTarget.releasePointerCapture(event.pointerId);
            }}
            onPointerCancel={(event) => {
              if (sequenceScrubbingRef.current === event.pointerId) sequenceScrubbingRef.current = null;
            }}
          >
            <div className="sequence-progress" style={{ width: `${sequenceProgress * 100}%` }} />
            {sequenceActions.map((action) => (
              <div
                className={`sequence-segment${action.id === activeSequenceAction.id ? ' active' : ''}`}
                key={action.id}
                style={{ left: `${action.start * 100}%`, width: `${(action.end - action.start) * 100}%` }}
              >
                <span>{action.label}</span>
              </div>
            ))}
            {sequenceActions.map((action) => (
              <i className="sequence-key" key={`${action.id}-key`} style={{ left: `${action.start * 100}%` }} />
            ))}
            <i className="sequence-playhead" style={{ left: `${sequenceProgress * 100}%` }} />
          </div>
          <div className="sequence-inspector">
            <div className="sequence-transport" aria-label="Проигрывание секвенсора">
              <button
                className={playing ? 'active' : ''}
                type="button"
                onClick={togglePlayback}
                disabled={simulationBusy || !!simulationStatus}
                aria-label={playing ? 'Стоп' : 'Play'}
                title={playing ? 'Стоп' : 'Play'}
              >{playing ? '■' : '▶'}</button>
              <button
                className={loopPlayback ? 'active' : ''}
                type="button"
                onClick={() => setLoopPlayback((current) => !current)}
                aria-pressed={loopPlayback}
                aria-label={`${loopPlayback ? 'Выключить' : 'Включить'} повтор секвенции`}
                title={`${loopPlayback ? 'Выключить' : 'Включить'} повтор`}
              >↻</button>
            </div>
            <strong>{activeSequenceAction.label}</strong>
          </div>
        </div>
      </section>

      <aside className="controls" aria-label="Настройки сцены">
        <section className="blender-tools" aria-label="Инструменты Blender" data-mode={clothMode}>
          <div className="section-title">Blender · кадр 16:9</div>
          <button type="button" disabled={simulationBusy || exporting}
            onClick={() => clothMode === 'calculating'
              ? editorControllerRef.current?.cancelCloth()
              : void editorControllerRef.current?.calculateBlender()}>
            {clothMode === 'calculating' ? 'Отменить расчёт' : 'Рассчитать в Blender'}
          </button>
          <output role="status">{simulationStatus || clothMessage || (clothMode === 'quick' ? 'Предпросмотр · Blender ещё не рассчитан' : clothPreviewLabels[clothMode])}</output>
        </section>
        <button className="random" type="button" onClick={randomize}>Случайный зомби</button>
        <button className="reset-generation" type="button" disabled={!settingsLoaded} onClick={resetGenerationSettings}
          title="Вернуть параметры генерации по умолчанию и снять все замочки генерации">Сбросить настройки генерации</button>
        {storageMessage && <p role="status">{storageMessage}</p>}

        <div className="base-controls">
          <SelectControl label="Модели" value={modelSet} options={[
            { value: 'tomb', label: 'Tomb — тело и совместимая одежда' },
            { value: 'vanilla', label: 'Project Zomboid — ванильные' },
          ]} onChange={(value) => {
            stopPlayback();
            preservePoseOnReloadRef.current = true;
            setModelSet(value as ModelSet);
          }} wide />
          <SelectControl label="Поверхность" value={floor} options={floorOptions} onChange={setFloor} locked={locks.floor} onToggleLock={() => toggleLock('floor')} />
          <SelectControl label="Поза" value={selection.pose} options={poseOptions} onChange={(value) => {
            preservePoseOnReloadRef.current = false;
            preservedPoseStateRef.current = null;
            updateSelection('pose', value as PoseKey);
          }} locked={locks.pose} onToggleLock={() => toggleLock('pose')} />
          <SelectControl label="Тело" value={selection.body} options={bodyOptions.map((option) => ({
            ...option, label: modelSet === 'tomb' ? option.label.replace('Ванильный', 'Tomb') : option.label,
          }))} onChange={changeBody} wide locked={locks.body} onToggleLock={() => toggleLock('body')} />
          <SelectControl label="Волосы" value={selection.hair} options={hairOptions[sex]} onChange={(value) => updateSelection('hair', value as HairKey)} locked={locks.hair} onToggleLock={() => toggleLock('hair')} />
          <label className="field color-field">
            <span className="field-title"><span>Цвет RGB</span><LockButton locked={locks.hairColor} onChange={() => toggleLock('hairColor')} label="цвет волос" /></span>
            <span className="color-control">
              <input
                type="color"
                value={selection.hairColor}
                onChange={(event) => updateSelection('hairColor', event.target.value)}
                aria-label="Цвет волос RGB"
              />
              <output>{selection.hairColor.toUpperCase()}</output>
            </span>
          </label>
        </div>

        <div className="garment-controls">
          <div className="section-title"><span>Одежда</span><LockButton locked={locks.clothing} onChange={() => toggleLock('clothing')} label="одежду" /></div>
          <div className="add-garment">
            <select value={addType} onChange={(event) => setAddType(event.target.value as GarmentType)} aria-label="Добавляемая одежда">
              {availableGarmentTypes.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
            </select>
            <button type="button" onClick={addGarment}>Добавить</button>
          </div>

          <div className="garment-layers" aria-label="Слои одежды">
            {garmentLayers.map(([level, items]) => (
              <div className="garment-layer" key={level}>
                <div className="layer-label">Слой {level + 1}</div>
                {items.map((garment) => (
                  <div className="garment-row" key={garment.id}>
                    <span>{garmentDefinitions[garment.type].label}</span>
                    <select
                      value={garment.variant}
                      onChange={(event) => updateGarment(garment.id, event.target.value)}
                      aria-label={`${garmentDefinitions[garment.type].label}, вариант`}
                    >
                      {garmentDefinitions[garment.type].variants[sex].map((option) => (
                        <option key={option.value} value={option.value}>{option.label}</option>
                      ))}
                    </select>
                    <label title="Условная жёсткость изгиба в Blender: 0.3 — мягкая, 1 — средняя, 3 — жёсткая. Это не измеренные пресеты тканей; толщина не меняется.">
                      Жёсткость (Blender)
                      <input type="number" min="0.2" max="5" step="0.1" style={{width:55}}
                        key={`${garment.id}-${garment.fabricStiffness ?? 1}`} defaultValue={garment.fabricStiffness ?? 1}
                        aria-label={`Жёсткость Blender, ${garmentDefinitions[garment.type].label}`}
                        onBlur={event=>{const v=Number(event.currentTarget.value);if(Number.isFinite(v)){const value=Math.max(.2,Math.min(5,v));if(value!==(garment.fabricStiffness??1))setGarments(current=>current.map(g=>g.id===garment.id?{...g,fabricStiffness:value}:g));}}} />
                    </label>
                    <LockButton locked={lockedGarmentIds.has(garment.id)} onChange={() => toggleGarmentLock(garment.id)} label={garmentDefinitions[garment.type].label} />
                    <button type="button" onClick={() => removeGarment(garment.id)} aria-label={`Удалить ${garmentDefinitions[garment.type].label}`}>×</button>
                  </div>
                ))}
              </div>
            ))}
          </div>
        </div>

        <div className="loot-controls">
          <div className="section-title"><span>Выпадающие предметы</span><LockButton locked={locks.loot} onChange={() => toggleLock('loot')} label="выпадающие предметы" /></div>
          <div className="add-loot">
            <select
              value={normalizePocketId(addLootKind,sex) ?? 'Base.Wallet_Male'}
              onChange={(event) => setAddLootKind(event.target.value as SequencePropKind)}
              aria-label="Добавляемый предмет"
            >
              {sequencePropOptions.map((option) => <option key={option.value} value={option.value} title={option.title}>{option.label}</option>)}
            </select>
            <button type="button" onClick={addLootItem}>Добавить</button>
          </div>
          <div className="loot-list" aria-label="Выпадающие предметы">
            {normalizedLootItems.map((item) => (
              <div className="loot-row" key={item.id}>
                <select
                  value={item.kind}
                  onChange={(event) => updateLootItem(item.id, { kind: event.target.value as SequencePropKind })}
                  aria-label={`Предмет ${sequencePropLabels[item.kind]}`}
                >
                  {sequencePropOptions.map((option) => <option key={option.value} value={option.value} title={option.title}>{option.label}</option>)}
                </select>
                <select
                  value={String(item.layer)}
                  onChange={(event) => updateLootItem(item.id, { layer: Number(event.target.value) })}
                  aria-label={`Слой выпадения ${sequencePropLabels[item.kind]}`}
                >
                  {lootLayerOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
                </select>
                <button type="button" onClick={() => removeLootItem(item.id)} aria-label={`Удалить ${sequencePropLabels[item.kind]}`}>×</button>
              </div>
            ))}
          </div>
        </div>

      </aside>
      {exportPreviewVisible && exportResult && (
        <div className="gif-preview-overlay" aria-hidden="true">
          <img src={exportResult.url} alt="" />
        </div>
      )}
    </main>
  );
}
