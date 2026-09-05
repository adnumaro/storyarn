export type SequenceEntityId = string | number;

export interface SequenceLayerOrigin {
  nodeId?: SequenceEntityId | null;
  sequenceId?: SequenceEntityId | null;
  label?: string | null;
  inherited?: boolean;
}

export interface SequenceVisualLayerRecord {
  id: SequenceEntityId;
  key?: SequenceEntityId | null;
  layer_key?: SequenceEntityId | null;
  row_id?: SequenceEntityId | null;
  rowId?: SequenceEntityId | null;
  local_row_id?: SequenceEntityId | null;
  localRowId?: SequenceEntityId | null;
  sequence_id?: SequenceEntityId | null;
  sequenceId?: SequenceEntityId | null;
  sequence_depth?: number | null;
  sequenceDepth?: number | null;
  inherited?: boolean;
  overridden_fields?: string[] | null;
  overriddenFields?: string[] | null;
  kind: "backdrop" | "character" | "prop" | "overlay" | string;
  label?: string | null;
  asset_id?: SequenceEntityId | null;
  assetId?: SequenceEntityId | null;
  url?: string | null;
  z_index?: number | null;
  zIndex?: number | null;
  slot?: string | null;
  x?: number | null;
  y?: number | null;
  width?: number | null;
  height?: number | null;
  anchor_x?: number | null;
  anchorX?: number | null;
  anchor_y?: number | null;
  anchorY?: number | null;
  fit?: "cover" | "contain" | "fill" | null;
  opacity?: number | null;
  visible?: boolean | null;
  removed?: boolean;
  origin?: SequenceLayerOrigin | null;
  propertyOrigins?: Record<string, SequenceLayerOrigin | null>;
}

export interface SequenceVisualLayer extends SequenceVisualLayerRecord {
  url: string;
}

export interface SequenceAudioTrackRecord {
  id?: SequenceEntityId;
  continuity_key?: SequenceEntityId | null;
  continuityKey?: SequenceEntityId | null;
  track_key?: SequenceEntityId | null;
  trackKey?: SequenceEntityId | null;
  local_row_id?: SequenceEntityId | null;
  localRowId?: SequenceEntityId | null;
  sequence_id?: SequenceEntityId | null;
  sequenceId?: SequenceEntityId | null;
  is_override?: boolean;
  isOverride?: boolean;
  inherited?: boolean;
  overridden_fields?: string[] | null;
  overriddenFields?: string[] | null;
  kind: "music" | "ambience" | "sfx" | string;
  position?: number | null;
  asset_id?: SequenceEntityId | null;
  assetId?: SequenceEntityId | null;
  url?: string | null;
  volume?: number | null;
  content_type?: string | null;
  contentType?: string | null;
  filename?: string | null;
  depth?: number | null;
  removed?: boolean;
  propertyOrigins?: Record<string, SequenceLayerOrigin | null>;
}

export interface SequenceAudioTrack extends SequenceAudioTrackRecord {
  id: SequenceEntityId;
  url: string;
}

export interface SequenceAssetEntry {
  id: SequenceEntityId;
  filename: string;
  url?: string | null;
  content_type?: string | null;
  contentType?: string | null;
}

export interface SequenceCompositionSource {
  id: SequenceEntityId;
  type: "sequence" | "dialogue" | string;
  label: string;
}

export interface SequenceConfig {
  name?: string | null;
  width?: number | null;
  height?: number | null;
}

export interface SequenceConfigPanelData {
  sequence_id?: SequenceEntityId;
  owner_id?: SequenceEntityId;
  owner_type?: "sequence" | "dialogue" | string;
  composition_source_id?: SequenceEntityId | null;
  composition_sources?: SequenceCompositionSource[];
  config?: SequenceConfig | null;
  visual_layers?: SequenceVisualLayerRecord[];
  removed_visual_layers?: SequenceVisualLayerRecord[];
  tracks?: SequenceAudioTrackRecord[];
  removed_tracks?: SequenceAudioTrackRecord[];
  diagnostics?: SequenceCompositionDiagnostic[];
  image_assets?: SequenceAssetEntry[];
  audio_assets?: SequenceAssetEntry[];
}

export interface SequenceDialogueVoice {
  id?: SequenceEntityId | null;
  continuity_key?: SequenceEntityId | null;
  continuityKey?: SequenceEntityId | null;
  node_id?: SequenceEntityId | null;
  nodeId?: SequenceEntityId | null;
  asset_id?: SequenceEntityId | null;
  assetId?: SequenceEntityId | null;
  url?: string | null;
  volume?: number | null;
  content_type?: string | null;
  contentType?: string | null;
  filename?: string | null;
  available?: boolean;
}

export interface SequenceCompositionDiagnostic {
  code: string;
  severity?: "info" | "warning" | "error";
  message?: string | null;
  nodeId?: SequenceEntityId | null;
  layerId?: SequenceEntityId | null;
}

export interface SequenceStageIntervention {
  nodeId: SequenceEntityId;
  speakerName?: string | null;
  speakerInitials?: string | null;
  speakerAvatarUrl?: string | null;
  speakerColor?: string | null;
  text?: string | null;
  stageDirections?: string | null;
  voice?: SequenceDialogueVoice | null;
}

export interface SequenceStageOwner {
  nodeId: SequenceEntityId;
  type: "sequence" | "dialogue" | string;
  compositionSourceId?: SequenceEntityId | null;
}

export interface SequenceStageComposition {
  layers: SequenceVisualLayer[];
  audioTracks?: SequenceAudioTrack[];
  diagnostics?: SequenceCompositionDiagnostic[];
}

export type SequenceStageState =
  | {
      status: "empty";
      owner?: null;
      intervention?: null;
      composition?: null;
      voice?: null;
      errorMessage?: null;
    }
  | {
      status: "ready";
      owner?: SequenceStageOwner | null;
      intervention?: SequenceStageIntervention | null;
      composition: SequenceStageComposition;
      voice?: SequenceDialogueVoice | null;
      errorMessage?: null;
    }
  | {
      status: "error";
      owner?: SequenceStageOwner | null;
      intervention?: SequenceStageIntervention | null;
      composition?: SequenceStageComposition | null;
      voice?: SequenceDialogueVoice | null;
      errorMessage?: string | null;
    };
