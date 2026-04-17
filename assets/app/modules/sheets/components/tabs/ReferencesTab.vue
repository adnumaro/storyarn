<script setup lang="ts">
import {
  AlertTriangle,
  ArrowRight,
  ArrowUpRight,
  BookOpen,
  ChevronDown,
  Circle,
  Database,
  Eye,
  FileText,
  GitBranch,
  Link,
  Map,
  Pencil,
  Zap,
} from "lucide-vue-next";
import type { FunctionalComponent } from "vue";
import { computed, ref } from "vue";
import { Badge } from "@components/ui/badge/index.ts";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@components/ui/collapsible/index.ts";
import type { Backlink, SceneAppearance, VariableUsageEntry } from "../../types";

const {
  variableUsage = [],
  backlinks = [],
  sceneAppearances = [],
  workspaceSlug,
  projectSlug,
  loading = false,
} = defineProps<{
  variableUsage?: VariableUsageEntry[];
  backlinks?: Backlink[];
  sceneAppearances?: SceneAppearance[];
  workspaceSlug: string;
  projectSlug: string;
  loading?: boolean;
}>();

const variableUsageOpen = ref(true);
const backlinksOpen = ref(true);
const sceneAppearancesOpen = ref(true);

const totalVariableRefs = computed(() =>
  variableUsage.reduce((sum, v) => sum + v.reads.length + v.writes.length, 0),
);

function nodeIcon(nodeType: string | undefined): FunctionalComponent {
  if (nodeType === "instruction") return Zap;
  if (nodeType === "condition") return GitBranch;
  return Circle;
}

function sourceIcon(sourceType: string): FunctionalComponent {
  if (sourceType === "sheet") return FileText;
  if (sourceType === "flow") return GitBranch;
  if (sourceType === "screenplay") return BookOpen;
  if (sourceType === "scene") return Map;
  return Link;
}

function sourceColor(sourceType: string): string {
  if (sourceType === "sheet") return "bg-violet-500/15 text-violet-600 dark:text-violet-400";
  if (sourceType === "flow") return "bg-amber-500/15 text-amber-600 dark:text-amber-400";
  if (sourceType === "screenplay")
    return "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400";
  if (sourceType === "scene") return "bg-sky-500/15 text-sky-600 dark:text-sky-400";
  return "bg-muted text-muted-foreground";
}

function flowUrl(flowId: number | string | undefined, nodeId?: number | string): string {
  const base = `/workspaces/${workspaceSlug}/projects/${projectSlug}/flows/${flowId}`;
  return nodeId ? `${base}?node=${nodeId}` : base;
}

function sceneUrl(sceneId: number | string | undefined): string {
  return `/workspaces/${workspaceSlug}/projects/${projectSlug}/scenes/${sceneId}`;
}

function backlinkUrl(backlink: Backlink): string {
  const si = backlink.sourceInfo;
  if (si.type === "sheet")
    return `/workspaces/${workspaceSlug}/projects/${projectSlug}/sheets/${si.sheetId}`;
  if (si.type === "flow")
    return `/workspaces/${workspaceSlug}/projects/${projectSlug}/flows/${si.flowId}`;
  if (si.type === "screenplay")
    return `/workspaces/${workspaceSlug}/projects/${projectSlug}/screenplays/${si.screenplayId}?element=${backlink.sourceId}`;
  if (si.type === "scene")
    return `/workspaces/${workspaceSlug}/projects/${projectSlug}/scenes/${si.sceneId}`;
  return "#";
}
</script>

<template>
  <div v-if="loading" class="flex items-center justify-center p-16">
    <div
      class="size-6 border-2 border-muted-foreground/20 border-t-muted-foreground/60 rounded-full animate-spin"
    />
  </div>

  <div v-else class="space-y-2">
    <!-- ── Variable Usage ── -->
    <Collapsible
      v-model:open="variableUsageOpen"
      class="rounded-xl border border-border/60 bg-card"
    >
      <CollapsibleTrigger
        class="flex items-center gap-2.5 w-full px-4 py-3 cursor-pointer hover:bg-muted/40 rounded-xl transition-colors"
      >
        <div
          class="size-6 rounded-md bg-indigo-500/15 text-indigo-600 dark:text-indigo-400 flex items-center justify-center shrink-0"
        >
          <Database class="size-3.5" />
        </div>
        <span class="text-sm font-semibold flex-1 text-left">{{ $t("sheets.references_tab.variable_usage") }}</span>
        <Badge
          v-if="totalVariableRefs > 0"
          variant="secondary"
          class="text-[10px] px-1.5 py-0 rounded-full"
        >
          {{ totalVariableRefs }}
        </Badge>
        <ChevronDown
          :class="[
            'size-4 text-muted-foreground transition-transform duration-200',
            !variableUsageOpen && '-rotate-90',
          ]"
        />
      </CollapsibleTrigger>

      <CollapsibleContent>
        <div class="px-4 pb-4">
          <div v-if="variableUsage.length === 0" class="rounded-lg bg-muted/30 p-5 text-center">
            <Database class="size-8 mx-auto text-muted-foreground/20 mb-2" />
            <p class="text-xs text-muted-foreground">
              {{ $t("sheets.references_tab.no_usage") }}
            </p>
          </div>

          <div v-else class="space-y-2.5">
            <div
              v-for="variable in variableUsage"
              :key="variable.blockId"
              v-show="variable.reads.length > 0 || variable.writes.length > 0"
              class="rounded-lg bg-muted/30 p-3"
            >
              <!-- Variable header -->
              <div class="flex items-center gap-2 mb-2.5 pb-2 border-b border-border/40">
                <span class="text-sm font-medium">{{ variable.label }}</span>
                <code class="text-[11px] text-muted-foreground/70 bg-muted px-1.5 py-0.5 rounded">{{
                  variable.shortcut
                }}</code>
                <Badge variant="outline" class="text-[10px] px-1.5 py-0">{{ variable.type }}</Badge>
              </div>

              <!-- Writes -->
              <div v-if="variable.writes.length > 0" class="mb-2">
                <span
                  class="text-[11px] font-semibold text-orange-500 dark:text-orange-400 flex items-center gap-1 mb-1.5 uppercase tracking-wider"
                >
                  <Pencil class="size-3" />
                  {{ $t("sheets.references_tab.modified_by") }}
                </span>
                <div class="ml-1 space-y-0.5">
                  <a
                    v-for="(ref, i) in variable.writes"
                    :key="'w' + i"
                    :href="
                      ref.sourceType === 'scene_zone'
                        ? sceneUrl(ref.sceneId)
                        : flowUrl(ref.flowId, ref.nodeId)
                    "
                    data-phx-link="redirect"
                    data-phx-link-state="push"
                    class="flex items-center gap-2 text-xs hover:text-primary group py-1 px-2 -mx-2 rounded-md hover:bg-background/60 transition-colors"
                  >
                    <div
                      :class="[
                        'size-5 rounded flex items-center justify-center shrink-0',
                        ref.sourceType === 'scene_zone'
                          ? 'bg-sky-500/15 text-sky-500'
                          : 'bg-amber-500/15 text-amber-500',
                      ]"
                    >
                      <component
                        :is="ref.sourceType === 'scene_zone' ? Map : nodeIcon(ref.nodeType)"
                        class="size-3"
                      />
                    </div>
                    <span class="font-medium">{{
                      ref.sourceType === "scene_zone" ? ref.sceneName : ref.flowName
                    }}</span>
                    <ArrowRight class="size-3 text-muted-foreground/40" />
                    <Badge variant="outline" class="text-[10px] px-1 py-0">
                      {{ ref.sourceType === "scene_zone" ? ref.zoneName : ref.nodeType }}
                    </Badge>
                    <span
                      v-if="ref.detail"
                      class="text-muted-foreground/70 font-mono text-[11px]"
                      >{{ ref.detail }}</span
                    >
                    <Badge
                      v-if="ref.stale"
                      class="text-[10px] px-1.5 py-0 bg-orange-500/15 text-orange-500 border-orange-500/20 gap-0.5"
                    >
                      <AlertTriangle class="size-2.5" />
                      {{ $t("sheets.references_tab.outdated") }}
                    </Badge>
                  </a>
                </div>
              </div>

              <!-- Reads -->
              <div v-if="variable.reads.length > 0">
                <span
                  class="text-[11px] font-semibold text-blue-500 dark:text-blue-400 flex items-center gap-1 mb-1.5 uppercase tracking-wider"
                >
                  <Eye class="size-3" />
                  {{ $t("sheets.references_tab.read_by") }}
                </span>
                <div class="ml-1 space-y-0.5">
                  <a
                    v-for="(ref, i) in variable.reads"
                    :key="'r' + i"
                    :href="
                      ref.sourceType === 'scene_zone'
                        ? sceneUrl(ref.sceneId)
                        : flowUrl(ref.flowId, ref.nodeId)
                    "
                    data-phx-link="redirect"
                    data-phx-link-state="push"
                    class="flex items-center gap-2 text-xs hover:text-primary group py-1 px-2 -mx-2 rounded-md hover:bg-background/60 transition-colors"
                  >
                    <div
                      :class="[
                        'size-5 rounded flex items-center justify-center shrink-0',
                        ref.sourceType === 'scene_zone'
                          ? 'bg-sky-500/15 text-sky-500'
                          : 'bg-amber-500/15 text-amber-500',
                      ]"
                    >
                      <component
                        :is="ref.sourceType === 'scene_zone' ? Map : nodeIcon(ref.nodeType)"
                        class="size-3"
                      />
                    </div>
                    <span class="font-medium">{{
                      ref.sourceType === "scene_zone" ? ref.sceneName : ref.flowName
                    }}</span>
                    <ArrowRight class="size-3 text-muted-foreground/40" />
                    <Badge variant="outline" class="text-[10px] px-1 py-0">
                      {{ ref.sourceType === "scene_zone" ? ref.zoneName : ref.nodeType }}
                    </Badge>
                    <Badge
                      v-if="ref.stale"
                      class="text-[10px] px-1.5 py-0 bg-orange-500/15 text-orange-500 border-orange-500/20 gap-0.5"
                    >
                      <AlertTriangle class="size-2.5" />
                      {{ $t("sheets.references_tab.outdated") }}
                    </Badge>
                  </a>
                </div>
              </div>
            </div>
          </div>
        </div>
      </CollapsibleContent>
    </Collapsible>

    <!-- ── Backlinks ── -->
    <Collapsible v-model:open="backlinksOpen" class="rounded-xl border border-border/60 bg-card">
      <CollapsibleTrigger
        class="flex items-center gap-2.5 w-full px-4 py-3 cursor-pointer hover:bg-muted/40 rounded-xl transition-colors"
      >
        <div
          class="size-6 rounded-md bg-violet-500/15 text-violet-600 dark:text-violet-400 flex items-center justify-center shrink-0"
        >
          <Link class="size-3.5" />
        </div>
        <span class="text-sm font-semibold flex-1 text-left">{{ $t("sheets.references_tab.backlinks") }}</span>
        <Badge
          v-if="backlinks.length > 0"
          variant="secondary"
          class="text-[10px] px-1.5 py-0 rounded-full"
        >
          {{ backlinks.length }}
        </Badge>
        <ChevronDown
          :class="[
            'size-4 text-muted-foreground transition-transform duration-200',
            !backlinksOpen && '-rotate-90',
          ]"
        />
      </CollapsibleTrigger>

      <CollapsibleContent>
        <div class="px-4 pb-4">
          <div v-if="backlinks.length === 0" class="rounded-lg bg-muted/30 p-5 text-center">
            <Link class="size-8 mx-auto text-muted-foreground/20 mb-2" />
            <p class="text-xs text-muted-foreground mb-0.5">{{ $t("sheets.references_tab.no_backlinks_title") }}</p>
            <p class="text-[11px] text-muted-foreground/60">
              {{ $t("sheets.references_tab.no_backlinks_description") }}
            </p>
          </div>

          <div v-else class="space-y-0.5">
            <a
              v-for="backlink in backlinks"
              :key="backlink.id"
              :href="backlinkUrl(backlink)"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="flex items-center gap-3 py-2.5 px-2 -mx-2 rounded-lg hover:bg-muted/50 group cursor-pointer transition-colors"
            >
              <div
                :class="[
                  'shrink-0 size-8 rounded-lg flex items-center justify-center',
                  sourceColor(backlink.sourceInfo.type),
                ]"
              >
                <component :is="sourceIcon(backlink.sourceInfo.type)" class="size-4" />
              </div>

              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <span class="text-sm font-medium truncate">{{ backlink.sourceInfo.name }}</span>
                  <span
                    v-if="backlink.sourceInfo.shortcut"
                    class="text-[11px] text-muted-foreground/60 font-mono"
                  >
                    #{{ backlink.sourceInfo.shortcut }}
                  </span>
                </div>
                <div class="flex items-center gap-1.5 mt-0.5">
                  <Badge
                    v-if="backlink.sourceInfo.contextType"
                    variant="outline"
                    class="text-[10px] px-1.5 py-0"
                  >
                    {{ backlink.sourceInfo.contextType }}
                  </Badge>
                  <span
                    v-if="backlink.sourceInfo.contextLabel"
                    class="text-[11px] text-muted-foreground/70"
                  >
                    {{ backlink.sourceInfo.contextLabel }}
                  </span>
                </div>
              </div>

              <span class="text-[11px] text-muted-foreground/50 tabular-nums shrink-0">{{
                backlink.date
              }}</span>
            </a>
          </div>
        </div>
      </CollapsibleContent>
    </Collapsible>

    <!-- ── Scene Appearances ── -->
    <Collapsible
      v-model:open="sceneAppearancesOpen"
      class="rounded-xl border border-border/60 bg-card"
    >
      <CollapsibleTrigger
        class="flex items-center gap-2.5 w-full px-4 py-3 cursor-pointer hover:bg-muted/40 rounded-xl transition-colors"
      >
        <div
          class="size-6 rounded-md bg-sky-500/15 text-sky-600 dark:text-sky-400 flex items-center justify-center shrink-0"
        >
          <Map class="size-3.5" />
        </div>
        <span class="text-sm font-semibold flex-1 text-left">{{ $t("sheets.references_tab.scenes_title") }}</span>
        <Badge
          v-if="sceneAppearances.length > 0"
          variant="secondary"
          class="text-[10px] px-1.5 py-0 rounded-full"
        >
          {{ sceneAppearances.length }}
        </Badge>
        <ChevronDown
          :class="[
            'size-4 text-muted-foreground transition-transform duration-200',
            !sceneAppearancesOpen && '-rotate-90',
          ]"
        />
      </CollapsibleTrigger>

      <CollapsibleContent>
        <div class="px-4 pb-4">
          <div v-if="sceneAppearances.length === 0" class="rounded-lg bg-muted/30 p-5 text-center">
            <Map class="size-8 mx-auto text-muted-foreground/20 mb-2" />
            <p class="text-xs text-muted-foreground mb-0.5">
              {{ $t("sheets.references_tab.no_scenes") }}
            </p>
            <p class="text-[11px] text-muted-foreground/60">
              {{ $t("sheets.references_tab.no_scenes_description") }}
            </p>
          </div>

          <div v-else class="space-y-0.5">
            <a
              v-for="(appearance, i) in sceneAppearances"
              :key="i"
              :href="sceneUrl(appearance.sceneId)"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="flex items-center gap-3 py-2.5 px-2 -mx-2 rounded-lg hover:bg-muted/50 group cursor-pointer transition-colors"
            >
              <div
                class="shrink-0 size-8 rounded-lg flex items-center justify-center bg-sky-500/15 text-sky-600 dark:text-sky-400"
              >
                <Map class="size-4" />
              </div>

              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <span class="text-sm font-medium truncate">{{ appearance.sceneName }}</span>
                </div>
                <div class="flex items-center gap-1.5 mt-0.5">
                  <Badge variant="outline" class="text-[10px] px-1.5 py-0">{{
                    appearance.elementType
                  }}</Badge>
                  <span
                    v-if="appearance.elementName"
                    class="text-[11px] text-muted-foreground/70"
                    >{{ appearance.elementName }}</span
                  >
                </div>
              </div>

              <ArrowUpRight
                class="size-4 text-muted-foreground/20 group-hover:text-muted-foreground/50 transition-colors shrink-0"
              />
            </a>
          </div>
        </div>
      </CollapsibleContent>
    </Collapsible>
  </div>
</template>
