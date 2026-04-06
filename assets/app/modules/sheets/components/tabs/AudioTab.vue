<script setup lang="ts">
import {
  ArrowUpRight,
  ChevronDown,
  GitBranch,
  Headphones,
  Loader2,
  Search,
  Upload,
  Volume2,
  VolumeX,
  X,
} from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import { Badge } from "@components/ui/badge/index.ts";
import { Button } from "@components/ui/button/index.ts";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@components/ui/collapsible/index.ts";
import {
  Command,
  CommandEmpty,
  CommandInput,
  CommandItem,
  CommandList,
} from "@components/ui/command/index.ts";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover/index.ts";
import { useLive } from "@composables/useLive";
import type { AudioAsset, VoiceLineGroup } from "../../types";

const {
  groupedLines = [],
  audioAssets = [],
  workspaceSlug,
  projectSlug,
  canEdit = false,
  loading = false,
} = defineProps<{
  groupedLines?: VoiceLineGroup[];
  audioAssets?: AudioAsset[];
  workspaceSlug: string;
  projectSlug: string;
  canEdit?: boolean;
  loading?: boolean;
}>();

const live = useLive();

const uploadingNodeId = ref<number | string | null>(null);
const openPopoverNodeId = ref<number | string | null>(null);
const searchQuery = ref("");

const totalLines = computed(() => groupedLines.reduce((sum, g) => sum + g.lines.length, 0));

const filteredAssets = computed(() => {
  if (!searchQuery.value) return audioAssets;
  const q = searchQuery.value.toLowerCase();
  return audioAssets.filter((a) => a.filename.toLowerCase().includes(q));
});

// Reset uploading state when props update with new audio data
watch(
  () => groupedLines,
  () => {
    uploadingNodeId.value = null;
  },
);

function flowUrl(flowId: number | string): string {
  return `/workspaces/${workspaceSlug}/projects/${projectSlug}/flows/${flowId}`;
}

function nodeUrl(flowId: number | string, nodeId: number | string): string {
  return `${flowUrl(flowId)}?node=${nodeId}`;
}

function selectAudio(nodeId: number | string, assetId: number | string): void {
  live.pushEvent("select_audio", {
    "node-id": nodeId,
    audio_asset_id: assetId,
  });
  openPopoverNodeId.value = null;
  searchQuery.value = "";
}

function removeAudio(nodeId: number | string): void {
  live.pushEvent("remove_audio", { "node-id": nodeId });
}

function triggerUpload(nodeId: number | string): void {
  const input = document.createElement("input");
  input.type = "file";
  input.accept = "audio/*";
  input.onchange = (e) => {
    const file = (e.target as HTMLInputElement).files![0];
    if (!file) return;
    if (!file.type.startsWith("audio/")) return;
    if (file.size > 20 * 1024 * 1024) return;
    uploadingNodeId.value = nodeId;
    const reader = new FileReader();
    reader.onload = () => {
      live.pushEvent("upload_audio", {
        filename: file.name,
        content_type: file.type,
        data: reader.result,
        node_id: nodeId,
      });
    };
    reader.readAsDataURL(file);
  };
  input.click();
}

function openPopover(nodeId: number | string): void {
  openPopoverNodeId.value = nodeId;
  searchQuery.value = "";
}
</script>

<template>
  <!-- Loading -->
  <div v-if="loading" class="flex items-center justify-center p-16">
    <div
      class="size-6 border-2 border-muted-foreground/20 border-t-muted-foreground/60 rounded-full animate-spin"
    />
  </div>

  <!-- Empty state -->
  <div
    v-else-if="groupedLines.length === 0"
    class="rounded-xl border border-border/60 bg-card p-8 text-center"
  >
    <VolumeX class="size-10 mx-auto text-muted-foreground/20 mb-3" />
    <p class="text-sm font-medium text-muted-foreground mb-1">No voice lines</p>
    <p class="text-xs text-muted-foreground/60">
      Dialogue nodes using this sheet as speaker will appear here.
    </p>
  </div>

  <!-- Flow groups -->
  <div v-else class="space-y-2">
    <Collapsible
      v-for="group in groupedLines"
      :key="group.flow.id"
      :default-open="true"
      class="rounded-xl border border-border/60 bg-card"
    >
      <!-- Flow header -->
      <div class="flex items-center">
        <CollapsibleTrigger
          class="flex items-center gap-2.5 flex-1 px-4 py-3 cursor-pointer hover:bg-muted/40 rounded-xl transition-colors"
        >
          <div
            class="size-6 rounded-md bg-amber-500/15 text-amber-600 dark:text-amber-400 flex items-center justify-center shrink-0"
          >
            <GitBranch class="size-3.5" />
          </div>
          <span class="text-sm font-semibold flex-1 text-left">{{ group.flow.name }}</span>
          <span v-if="group.flow.shortcut" class="text-[11px] text-muted-foreground/60 font-mono">
            #{{ group.flow.shortcut }}
          </span>
          <Badge variant="secondary" class="text-[10px] px-1.5 py-0 rounded-full">
            {{ group.lines.length }}
          </Badge>
          <ChevronDown
            class="size-4 text-muted-foreground transition-transform duration-200 [[data-state=closed]_&]:[-rotate-90]"
          />
        </CollapsibleTrigger>
      </div>

      <!-- Voice lines -->
      <CollapsibleContent>
        <div class="px-4 pb-3 space-y-2">
          <div v-for="line in group.lines" :key="line.nodeId" class="rounded-lg bg-muted/30 p-3">
            <!-- Text + link to node -->
            <div class="flex items-start justify-between gap-2 mb-2">
              <p v-if="line.text" class="text-sm text-foreground/80 flex-1">{{ line.text }}</p>
              <p v-else class="text-sm text-muted-foreground/50 italic flex-1">(empty dialogue)</p>
              <a
                :href="nodeUrl(line.flowId, line.nodeId)"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="shrink-0 p-1.5 rounded-md bg-primary/5 text-primary/50 hover:bg-primary/10 hover:text-primary transition-colors"
                title="Open in flow editor"
              >
                <ArrowUpRight class="size-3.5" />
              </a>
            </div>

            <!-- Audio attached -->
            <div v-if="line.audioAsset" class="space-y-1.5">
              <div class="flex items-center gap-2 text-xs text-muted-foreground">
                <Volume2 class="size-3 shrink-0" />
                <span class="truncate">{{ line.audioAsset.filename }}</span>
              </div>
              <audio
                controls
                class="w-full h-8 [&::-webkit-media-controls-panel]:bg-muted/50 rounded"
              >
                <source :src="line.audioAsset.url" :type="line.audioAsset.contentType" />
              </audio>
              <Button
                v-if="canEdit"
                variant="ghost"
                size="xs"
                class="text-destructive hover:text-destructive gap-1"
                @click="removeAudio(line.nodeId)"
              >
                <X class="size-3" />
                Remove
              </Button>
            </div>

            <!-- No audio + can edit -->
            <div v-else-if="canEdit" class="flex items-center gap-2 mt-1">
              <Popover
                :open="openPopoverNodeId === line.nodeId"
                @update:open="(v) => (v ? openPopover(line.nodeId) : (openPopoverNodeId = null))"
              >
                <PopoverTrigger as-child>
                  <Button variant="outline" size="xs" class="gap-1 font-normal">
                    <Search class="size-3" />
                    Select audio...
                  </Button>
                </PopoverTrigger>
                <PopoverContent align="start" :side-offset="4" class="w-64 p-0">
                  <Command :should-filter="false">
                    <CommandInput
                      :model-value="searchQuery"
                      @update:model-value="(v) => (searchQuery = v as string)"
                      placeholder="Search audio..."
                    />
                    <CommandList class="max-h-48">
                      <div v-if="filteredAssets.length === 0" class="py-4 px-3 text-center">
                        <VolumeX class="size-6 mx-auto text-muted-foreground/20 mb-1.5" />
                        <p v-if="audioAssets.length === 0" class="text-xs text-muted-foreground">
                          No audio assets yet.
                        </p>
                        <p v-else class="text-xs text-muted-foreground">No matches</p>
                      </div>
                      <CommandItem
                        v-for="asset in filteredAssets"
                        :key="asset.id"
                        :value="String(asset.id)"
                        class="text-xs gap-2 cursor-pointer"
                        @select="selectAudio(line.nodeId, asset.id)"
                      >
                        <Headphones class="size-3 shrink-0 text-muted-foreground" />
                        <span class="truncate">{{ asset.filename }}</span>
                      </CommandItem>
                    </CommandList>
                  </Command>
                </PopoverContent>
              </Popover>

              <Button
                variant="outline"
                size="xs"
                class="gap-1 font-normal"
                :disabled="uploadingNodeId === line.nodeId"
                @click="triggerUpload(line.nodeId)"
              >
                <Loader2 v-if="uploadingNodeId === line.nodeId" class="size-3 animate-spin" />
                <Upload v-else class="size-3" />
                {{ uploadingNodeId === line.nodeId ? "Uploading..." : "Upload" }}
              </Button>
            </div>

            <!-- No audio + read only -->
            <div v-else class="flex items-center gap-2 text-xs text-muted-foreground/40 mt-1">
              <VolumeX class="size-3" />
              <span>No audio</span>
            </div>
          </div>
        </div>
      </CollapsibleContent>
    </Collapsible>
  </div>
</template>
