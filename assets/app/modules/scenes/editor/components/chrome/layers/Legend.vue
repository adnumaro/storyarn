<script setup lang="ts">
import type { Component } from "vue";
import { List, MapPin, Star, User, Zap } from "lucide-vue-next";
import { useLive } from "@shared/composables/useLive.ts";

interface PinGroup {
  label: string;
  color: string;
  icon: string;
  count: number;
}

interface ZoneGroup {
  label: string;
  color: string;
  opacityHex: string;
  count: number;
}

interface ConnectionGroup {
  label: string;
  color: string;
  dashArray: string;
  count: number;
}

interface LegendData {
  pinGroups: PinGroup[];
  zoneGroups: ZoneGroup[];
  connectionGroups: ConnectionGroup[];
  hasEntries: boolean;
}

const {
  legendData = { pinGroups: [], zoneGroups: [], connectionGroups: [], hasEntries: false },
  legendOpen = false,
} = defineProps<{
  legendData: LegendData;
  legendOpen: boolean;
}>();

const live = useLive();

const pinIcons: Record<string, Component> = {
  "map-pin": MapPin,
  user: User,
  zap: Zap,
  star: Star,
};

function toggleLegend(): void {
  live.pushEvent("toggle_legend", {});
}

function getPinIcon(iconName: string): Component {
  return pinIcons[iconName] || MapPin;
}
</script>

<template>
  <div v-if="legendData.hasEntries" class="relative">
    <!-- Toggle button (always visible) -->
    <button
      type="button"
      class="inline-flex items-center gap-1.5 h-8 px-3 text-sm bg-surface border border-border rounded-lg shadow-md hover:bg-accent transition-colors"
      :title="legendOpen ? $t('scenes.legend.hide') : $t('scenes.legend.show')"
      :aria-label="legendOpen ? $t('scenes.legend.hide') : $t('scenes.legend.show')"
      @click="toggleLegend"
    >
      <List class="size-4" />
      {{ $t("scenes.legend.legend") }}
    </button>

    <!-- Expanded: popover above button -->
    <div
      v-if="legendOpen"
      class="absolute bottom-full right-0 mb-2 bg-surface rounded-lg border border-border shadow-md w-56 max-h-64 overflow-hidden flex flex-col"
    >
      <div class="overflow-y-auto p-2 space-y-3">
        <!-- Pin groups -->
        <div v-if="legendData.pinGroups.length > 0">
          <div
            class="text-[10px] font-semibold text-muted-foreground/60 uppercase tracking-wider mb-1"
          >
            {{ $t("scenes.legend.pins") }}
          </div>
          <div
            v-for="(group, i) in legendData.pinGroups"
            :key="'pin-' + i"
            class="flex items-center gap-2 py-0.5"
          >
            <div
              class="size-5 rounded-full flex items-center justify-center shrink-0"
              :style="{
                backgroundColor: (group.color || '#6b7280') + '20',
                color: group.color || '#6b7280',
              }"
            >
              <component :is="getPinIcon(group.icon)" class="size-3" />
            </div>
            <span class="text-xs flex-1 truncate">{{ group.label }}</span>
            <span class="text-xs text-muted-foreground/60 tabular-nums">{{ group.count }}</span>
          </div>
        </div>

        <!-- Zone groups -->
        <div v-if="legendData.zoneGroups.length > 0">
          <div
            class="text-[10px] font-semibold text-muted-foreground/60 uppercase tracking-wider mb-1"
          >
            {{ $t("scenes.legend.zones") }}
          </div>
          <div
            v-for="(group, i) in legendData.zoneGroups"
            :key="'zone-' + i"
            class="flex items-center gap-2 py-0.5"
          >
            <div
              class="size-5 rounded shrink-0 border border-border"
              :style="{ backgroundColor: group.color + group.opacityHex }"
            />
            <span class="text-xs flex-1 truncate">{{ group.label }}</span>
            <span class="text-xs text-muted-foreground/60 tabular-nums">{{ group.count }}</span>
          </div>
        </div>

        <!-- Connection groups -->
        <div v-if="legendData.connectionGroups.length > 0">
          <div
            class="text-[10px] font-semibold text-muted-foreground/60 uppercase tracking-wider mb-1"
          >
            {{ $t("scenes.legend.connections") }}
          </div>
          <div
            v-for="(group, i) in legendData.connectionGroups"
            :key="'conn-' + i"
            class="flex items-center gap-2 py-0.5"
          >
            <svg class="w-5 h-3 shrink-0" viewBox="0 0 20 12">
              <line
                x1="0"
                y1="6"
                x2="20"
                y2="6"
                :stroke="group.color"
                stroke-width="2"
                :stroke-dasharray="group.dashArray"
              />
            </svg>
            <span class="text-xs flex-1 truncate">{{ group.label }}</span>
            <span class="text-xs text-muted-foreground/60 tabular-nums">{{ group.count }}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
