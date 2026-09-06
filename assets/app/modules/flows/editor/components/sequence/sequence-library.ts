import type { SequenceEntityId } from "@modules/flows/sequence/types";

export const SEQUENCE_LIBRARY_IMAGE_MIME = "application/x-storyarn-sequence-image";

export interface SequenceLibraryImage {
  asset_id: SequenceEntityId;
  url: string;
  label: string;
  sheet_id?: SequenceEntityId;
  source: "asset" | "gallery" | "portrait";
}

export interface SequenceLibraryPortrait {
  id: SequenceEntityId;
  asset_id?: SequenceEntityId | null;
  url: string;
  name?: string | null;
}

export interface SequenceLibraryGalleryImage {
  id: SequenceEntityId;
  asset_id?: SequenceEntityId | null;
  url: string;
  label?: string | null;
}

export interface SequenceLibrarySheet {
  id: SequenceEntityId;
  name: string;
  avatar_url?: string | null;
  color?: string | null;
  avatars?: SequenceLibraryPortrait[];
  gallery_images?: SequenceLibraryGalleryImage[];
}

function validId(value: unknown): value is SequenceEntityId {
  return (
    (typeof value === "number" && Number.isSafeInteger(value) && value > 0) ||
    (typeof value === "string" && /^[1-9]\d*$/.test(value))
  );
}

function validImage(value: Partial<SequenceLibraryImage>): value is SequenceLibraryImage {
  return (
    validId(value.asset_id) &&
    typeof value.url === "string" &&
    value.url.trim().length > 0 &&
    typeof value.label === "string" &&
    ["asset", "gallery", "portrait"].includes(value.source ?? "") &&
    (value.sheet_id === undefined || validId(value.sheet_id))
  );
}

export function parseSequenceLibraryImage(raw: string): SequenceLibraryImage | null {
  try {
    const value = JSON.parse(raw) as Partial<SequenceLibraryImage> | null;
    if (!value || !validImage(value)) return null;
    return {
      asset_id: value.asset_id,
      url: value.url,
      label: value.label,
      source: value.source,
      ...(value.sheet_id !== undefined ? { sheet_id: value.sheet_id } : {}),
    };
  } catch {
    return null;
  }
}
