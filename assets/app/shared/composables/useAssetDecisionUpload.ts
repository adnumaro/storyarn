import { computed, ref } from "vue";

export type AssetUploadPurpose = "avatar" | "banner" | "scene_background";

export interface UploadResult {
  id: number;
  url: string;
  reused?: boolean;
  action?: string | null;
}

export interface AssetUploadDecision {
  action: string;
  source_exists: boolean;
  variant_exists: boolean;
  requires_variant: boolean;
  variant_profile: string;
  target: { width: number; height: number; crop: boolean } | null;
  asset_id: number | null;
}

export interface AssetUploadDialogState {
  fileName: string;
  fileSize: string;
  purpose: AssetUploadPurpose;
  action: string;
  sourceExists: boolean;
  variantExists: boolean;
  requiresVariant: boolean;
  target: AssetUploadDecision["target"];
}

interface FileMetadata {
  hash: string;
  width: number | null;
  height: number | null;
}

interface PendingConfirmation {
  resolve: (accepted: boolean) => void;
}

const uploading = ref(false);
const progress = ref(0);
const error = ref<string | null>(null);

function getUploadUrl(suffix = ""): string {
  const path = window.location.pathname;
  const match = path.match(/^(\/workspaces\/[^/]+\/projects\/[^/]+)/);
  if (!match) throw new Error("Cannot determine upload URL from current path");
  return `${match[1]}/upload${suffix}`;
}

function getCsrfToken(): string {
  return document.querySelector("meta[name='csrf-token']")?.getAttribute("content") ?? "";
}

async function inspectUpload(
  file: File,
  purpose: AssetUploadPurpose,
  metadata: FileMetadata,
): Promise<AssetUploadDecision> {
  const response = await fetch(getUploadUrl("/inspect"), {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-csrf-token": getCsrfToken(),
    },
    body: JSON.stringify({
      purpose,
      hash: metadata.hash,
      size: file.size,
      width: metadata.width,
      height: metadata.height,
      content_type: file.type,
      filename: file.name,
    }),
  });

  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw new Error(body.error || `Upload inspection failed (${response.status})`);
  }

  return response.json();
}

async function materializeUpload(
  purpose: AssetUploadPurpose,
  metadata: FileMetadata,
): Promise<UploadResult> {
  const response = await fetch(getUploadUrl("/materialize"), {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-csrf-token": getCsrfToken(),
    },
    body: JSON.stringify({ purpose, hash: metadata.hash }),
  });

  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw new Error(body.error || `Upload materialization failed (${response.status})`);
  }

  return response.json();
}

function uploadFile(file: File, purpose: AssetUploadPurpose): Promise<UploadResult> {
  return new Promise((resolve, reject) => {
    const form = new FormData();
    form.append("file", file);
    form.append("purpose", purpose);

    const request = new XMLHttpRequest();
    request.open("POST", getUploadUrl());
    request.setRequestHeader("x-csrf-token", getCsrfToken());

    request.upload.onprogress = (event) => {
      if (event.lengthComputable) {
        progress.value = Math.round((event.loaded / event.total) * 100);
      }
    };

    request.onload = () => {
      const body = parseResponse(request.responseText);

      if (request.status >= 200 && request.status < 300) {
        resolve(body as UploadResult);
      } else {
        reject(new Error(body.error || `Upload failed (${request.status})`));
      }
    };

    request.onerror = () => reject(new Error("Upload failed"));
    request.send(form);
  });
}

function parseResponse(responseText: string): Record<string, unknown> {
  try {
    return JSON.parse(responseText || "{}");
  } catch {
    return {};
  }
}

async function fileMetadata(file: File): Promise<FileMetadata> {
  const [hash, dimensions] = await Promise.all([sha256(file), imageDimensions(file)]);
  return { hash, ...dimensions };
}

async function sha256(file: File): Promise<string> {
  const buffer = await file.arrayBuffer();
  const digest = await crypto.subtle.digest("SHA-256", buffer);

  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function imageDimensions(file: File): Promise<{ width: number | null; height: number | null }> {
  if (!file.type.startsWith("image/")) {
    return Promise.resolve({ width: null, height: null });
  }

  return new Promise((resolve) => {
    const url = URL.createObjectURL(file);
    const image = new Image();

    image.onload = () => {
      URL.revokeObjectURL(url);
      resolve({ width: image.naturalWidth, height: image.naturalHeight });
    };

    image.onerror = () => {
      URL.revokeObjectURL(url);
      resolve({ width: null, height: null });
    };

    image.src = url;
  });
}

function shouldAskForConfirmation(decision: AssetUploadDecision): boolean {
  return decision.source_exists || decision.requires_variant || decision.variant_exists;
}

function formatBytes(size: number): string {
  if (size < 1024) return `${size} B`;
  if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`;
  return `${(size / 1024 / 1024).toFixed(1)} MB`;
}

export function useAssetDecisionUpload() {
  const dialog = ref<AssetUploadDialogState | null>(null);
  let pendingConfirmation: PendingConfirmation | null = null;

  const busy = computed(() => uploading.value);

  async function uploadWithDecision(
    file: File,
    purpose: AssetUploadPurpose,
  ): Promise<UploadResult | null> {
    if (!file) return null;

    error.value = null;
    progress.value = 0;

    try {
      const metadata = await fileMetadata(file);
      const decision = await inspectUpload(file, purpose, metadata);

      if (shouldAskForConfirmation(decision)) {
        const accepted = await askForConfirmation(file, purpose, decision);
        if (!accepted) return null;
      }

      uploading.value = true;

      if (decision.asset_id && decision.variant_exists) {
        progress.value = 100;
        return materializeUpload(purpose, metadata);
      }

      if (decision.source_exists) {
        progress.value = 100;
        return materializeUpload(purpose, metadata);
      }

      return await uploadFile(file, purpose);
    } catch (reason) {
      error.value = reason instanceof Error ? reason.message : String(reason);
      return null;
    } finally {
      uploading.value = false;
      progress.value = 0;
      dialog.value = null;
      pendingConfirmation = null;
    }
  }

  async function uploadManyWithDecision(
    files: File[],
    purpose: AssetUploadPurpose,
  ): Promise<UploadResult[]> {
    const results: UploadResult[] = [];

    for (const file of files) {
      const result = await uploadWithDecision(file, purpose);
      if (result) results.push(result);
    }

    return results;
  }

  function askForConfirmation(
    file: File,
    purpose: AssetUploadPurpose,
    decision: AssetUploadDecision,
  ): Promise<boolean> {
    dialog.value = {
      fileName: file.name,
      fileSize: formatBytes(file.size),
      purpose,
      action: decision.action,
      sourceExists: decision.source_exists,
      variantExists: decision.variant_exists,
      requiresVariant: decision.requires_variant,
      target: decision.target,
    };

    return new Promise((resolve) => {
      pendingConfirmation = { resolve };
    });
  }

  function confirmDecision(): void {
    pendingConfirmation?.resolve(true);
  }

  function cancelDecision(): void {
    pendingConfirmation?.resolve(false);
  }

  return {
    dialog,
    uploading: busy,
    progress,
    error,
    uploadWithDecision,
    uploadManyWithDecision,
    confirmDecision,
    cancelDecision,
  };
}
