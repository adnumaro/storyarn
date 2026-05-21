/**
 * Composable for uploading files via multipart/form-data POST.
 *
 * Sends files to the dedicated upload controller instead of base64-encoding
 * them through the LiveView channel, which avoids longpoll payload limits.
 */

import { ref } from "vue";

interface UploadResult {
  id: number;
  url: string;
}

interface UseUploadReturn {
  uploading: Readonly<typeof uploading>;
  uploadFiles: (files: File[], purpose: string) => Promise<UploadResult[]>;
  uploadFile: (file: File, purpose: string) => Promise<UploadResult | null>;
}

const uploading = ref(false);

function getUploadUrl(): string {
  const path = window.location.pathname;
  const match = path.match(/^(\/workspaces\/[^/]+\/projects\/[^/]+)/);
  if (!match) throw new Error("Cannot determine upload URL from current path");
  return `${match[1]}/upload`;
}

function getCsrfToken(): string {
  return document.querySelector("meta[name='csrf-token']")?.getAttribute("content") ?? "";
}

async function doUpload(file: File, purpose: string): Promise<UploadResult> {
  const form = new FormData();
  form.append("file", file);
  form.append("purpose", purpose);

  const response = await fetch(getUploadUrl(), {
    method: "POST",
    headers: { "x-csrf-token": getCsrfToken() },
    body: form,
  });

  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw new Error(body.error || `Upload failed (${response.status})`);
  }

  return response.json();
}

export function useUpload(): UseUploadReturn {
  async function uploadFile(file: File, purpose: string): Promise<UploadResult | null> {
    if (!file) return null;
    uploading.value = true;
    try {
      return await doUpload(file, purpose);
    } finally {
      uploading.value = false;
    }
  }

  async function uploadFiles(files: File[], purpose: string): Promise<UploadResult[]> {
    if (files.length === 0) return [];
    uploading.value = true;
    try {
      const results: UploadResult[] = [];
      for (const file of files) {
        results.push(await doUpload(file, purpose));
      }
      return results;
    } finally {
      uploading.value = false;
    }
  }

  return { uploading, uploadFiles, uploadFile };
}
