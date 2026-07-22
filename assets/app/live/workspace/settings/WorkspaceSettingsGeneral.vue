<script setup lang="ts">
import { AlertTriangle, ImagePlus, ShieldCheck, Sparkles, Trash2 } from "lucide-vue-next";
import { ref, watch } from "vue";
import ThemeSelector from "@components/ThemeSelector.vue";
import { Button } from "@components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import { Input } from "@components/ui/input";
import { Label } from "@components/ui/label";
import { Separator } from "@components/ui/separator";
import { Switch } from "@components/ui/switch";
import { Textarea } from "@components/ui/textarea";
import LanguagePicker from "@components/language/LanguagePicker.vue";
import type { LanguagePickerOption } from "@components/language/types";

import { useLive } from "@shared/composables/useLive";

type AiSettings = {
  visible?: boolean;
  managedAllowed?: boolean;
  allowance?: {
    status?: string;
    availableUnits?: number;
    reservedUnits?: number;
    committedUnits?: number;
  };
  provenance?: {
    provider?: string;
    model?: string;
    region?: string;
    dataRetention?: string;
  } | null;
};

const {
  workspaceName = "",
  workspaceDescription = "",
  workspaceBannerUrl = "",
  sourceLocale = "",
  languageOptions = [],
  isOwner = false,
  canEditWorkspace = true,
  ai = {},
} = defineProps<{
  workspaceName?: string;
  workspaceDescription?: string;
  workspaceBannerUrl?: string;
  sourceLocale?: string;
  languageOptions?: LanguagePickerOption[];
  isOwner?: boolean;
  canEditWorkspace?: boolean;
  ai?: AiSettings;
}>();

const live = useLive();

// Form states
const localName = ref(workspaceName);
const localDescription = ref(workspaceDescription);
const localBannerUrl = ref(workspaceBannerUrl);
const localSourceLocale = ref(sourceLocale.toLowerCase());

watch(
  () => workspaceName,
  (v) => {
    localName.value = v;
  },
);
watch(
  () => workspaceDescription,
  (v) => {
    localDescription.value = v;
  },
);
watch(
  () => workspaceBannerUrl,
  (v) => {
    localBannerUrl.value = v;
  },
);
watch(
  () => sourceLocale,
  (v) => {
    localSourceLocale.value = v.toLowerCase();
  },
);

function saveWorkspace() {
  if (!canEditWorkspace) return;

  live.pushEvent("save", {
    workspace: {
      name: localName.value,
      description: localDescription.value,
      banner_url: localBannerUrl.value,
      source_locale: localSourceLocale.value,
    },
  });
}

// Banner upload
function triggerBannerUpload() {
  const input = document.createElement("input");
  input.type = "file";
  input.accept = "image/*";
  input.onchange = (e) => uploadBanner((e.target as HTMLInputElement).files![0]);
  input.click();
}

function uploadBanner(file: File) {
  if (!file) return;
  const reader = new FileReader();
  reader.onload = () => {
    live.pushEvent("upload_workspace_banner", {
      filename: file.name,
      content_type: file.type,
      data: reader.result,
    });
  };
  reader.readAsDataURL(file);
}

function removeBanner() {
  localBannerUrl.value = "";
  live.pushEvent("remove_workspace_banner", {});
}

// Delete Workspace
const showDeleteConfirm = ref(false);

function confirmDeleteWorkspace() {
  showDeleteConfirm.value = false;
  live.pushEvent("delete", {});
}

function updateManagedAiPolicy(enabled: boolean) {
  if (!isOwner) return;
  live.pushEvent("update_managed_ai_policy", { enabled });
}
</script>

<template>
  <div class="space-y-8">
    <div class="space-y-1.5">
      <h1 class="text-2xl font-bold tracking-tight text-foreground">
        {{ $t("settings.workspace.general.title") }}
      </h1>
      <p class="text-base text-muted-foreground">{{ $t("settings.workspace.general.subtitle") }}</p>
    </div>

    <!-- General Settings -->
    <section>
      <form id="workspace-settings-form" class="space-y-5" @submit.prevent="saveWorkspace">
        <div class="space-y-1.5">
          <Label for="workspace-name">{{ $t("settings.workspace.general.fields.name") }}</Label>
          <Input id="workspace-name" v-model="localName" required :disabled="!canEditWorkspace" />
        </div>

        <div class="space-y-1.5">
          <Label for="workspace-description">{{
            $t("settings.workspace.general.fields.description")
          }}</Label>
          <Textarea
            id="workspace-description"
            v-model="localDescription"
            :disabled="!canEditWorkspace"
            :rows="3"
            :placeholder="$t('settings.workspace.general.fields.description')"
          />
        </div>

        <div class="space-y-1.5">
          <Label>{{ $t("settings.workspace.general.fields.banner") }}</Label>
          <div v-if="localBannerUrl" class="space-y-2 mt-1.5">
            <div class="rounded border border-border overflow-hidden">
              <img
                :src="localBannerUrl"
                :alt="$t('settings.workspace.general.fields.banner')"
                class="w-full h-32 object-cover"
              />
            </div>
            <div v-if="canEditWorkspace" class="flex gap-2">
              <Button
                type="button"
                variant="outline"
                class="flex-1 h-8 text-xs"
                @click="triggerBannerUpload"
              >
                <ImagePlus class="size-3 mr-1.5" />
                {{ $t("settings.workspace.general.fields.change") }}
              </Button>
              <Button
                type="button"
                variant="outline"
                class="flex-1 h-8 text-xs border-destructive/30 text-destructive hover:bg-destructive/10"
                @click="removeBanner"
              >
                <Trash2 class="size-3 mr-1.5" />
                {{ $t("settings.workspace.general.fields.remove") }}
              </Button>
            </div>
          </div>
          <Button
            v-else-if="canEditWorkspace"
            type="button"
            variant="outline"
            class="w-full h-9 text-xs border-dashed text-muted-foreground"
            @click="triggerBannerUpload"
          >
            <ImagePlus class="size-4 mr-1.5" />
            {{ $t("settings.workspace.general.fields.upload_banner") }}
          </Button>
        </div>

        <div class="space-y-1.5">
          <Label for="source-locale-trigger">{{
            $t("settings.workspace.general.fields.source_language")
          }}</Label>
          <LanguagePicker
            id="source-locale"
            v-model="localSourceLocale"
            :options="languageOptions"
            :label="$t('settings.workspace.general.fields.source_language')"
            :text="{
              placeholder: $t('settings.workspace.general.fields.select_language'),
              searchPlaceholder: $t('localization.sidebar.search_languages'),
              emptyLabel: $t('localization.sidebar.no_matches'),
            }"
            :appearance="{ triggerClass: 'w-full' }"
            :disabled="!canEditWorkspace"
          />
          <p class="text-xs text-muted-foreground mt-1">
            {{ $t("settings.workspace.general.fields.source_language_hint") }}
          </p>
        </div>

        <div v-if="canEditWorkspace" class="flex justify-start gap-3 pt-2">
          <Button type="submit">{{ $t("settings.workspace.general.save_changes") }}</Button>
        </div>
      </form>
    </section>

    <Separator />

    <section v-if="ai.visible" id="storyarn-ai-settings" class="space-y-4">
      <div
        class="flex items-start justify-between gap-5 rounded-xl border border-border bg-card p-5 shadow-sm"
      >
        <div class="min-w-0 space-y-3">
          <div class="flex items-center gap-2">
            <span
              class="flex size-9 items-center justify-center rounded-lg bg-primary/10 text-primary"
            >
              <Sparkles class="size-5" />
            </span>
            <div>
              <h3 class="font-semibold text-foreground">
                {{ $t("settings.workspace.storyarn_ai.title") }}
              </h3>
              <p class="text-xs text-muted-foreground">
                {{ $t("settings.workspace.storyarn_ai.beta_badge") }}
              </p>
            </div>
          </div>

          <p class="max-w-2xl text-sm leading-6 text-muted-foreground">
            {{ $t("settings.workspace.storyarn_ai.description") }}
          </p>

          <div class="flex flex-wrap gap-2 text-xs">
            <span class="rounded-full border border-border bg-muted/50 px-2.5 py-1 text-foreground">
              {{ $t("settings.workspace.storyarn_ai.allowance") }}:
              {{ ai.allowance?.availableUnits ?? 0 }}
            </span>
            <span
              class="rounded-full border px-2.5 py-1"
              :class="
                ai.allowance?.status === 'active'
                  ? 'border-success/30 bg-success/10 text-success'
                  : 'border-warning/30 bg-warning/10 text-warning'
              "
            >
              {{
                $t(`settings.workspace.storyarn_ai.states.${ai.allowance?.status ?? "unavailable"}`)
              }}
            </span>
          </div>

          <div
            class="flex items-start gap-2 rounded-lg bg-muted/40 p-3 text-xs text-muted-foreground"
          >
            <ShieldCheck class="mt-0.5 size-4 shrink-0 text-primary" />
            <p v-if="ai.provenance">
              {{
                $t("settings.workspace.storyarn_ai.disclosure", {
                  provider: ai.provenance.provider,
                  model: ai.provenance.model,
                  region: ai.provenance.region,
                })
              }}
            </p>
            <p v-else>{{ $t("settings.workspace.storyarn_ai.route_unavailable") }}</p>
          </div>
        </div>

        <div class="flex shrink-0 flex-col items-end gap-2">
          <Switch
            id="storyarn-ai-policy-toggle"
            :model-value="ai.managedAllowed"
            :disabled="!isOwner"
            :aria-label="$t('settings.workspace.storyarn_ai.toggle_label')"
            @update:model-value="updateManagedAiPolicy"
          />
          <span v-if="!isOwner" class="text-right text-xs text-muted-foreground">
            {{ $t("settings.workspace.storyarn_ai.owner_only") }}
          </span>
        </div>
      </div>
    </section>

    <Separator v-if="ai.visible" />

    <!-- Appearance -->
    <section>
      <h3 class="text-lg font-semibold mb-4">{{ $t("settings.workspace.appearance.title") }}</h3>
      <ThemeSelector
        :labels="{
          system: $t('settings.workspace.appearance.system'),
          light: $t('settings.workspace.appearance.light'),
          dark: $t('settings.workspace.appearance.dark'),
        }"
      />
    </section>

    <!-- Danger Zone (Only if Owner) -->
    <template v-if="isOwner">
      <Separator />

      <section>
        <h3 class="text-lg font-semibold mb-4 text-destructive">
          {{ $t("settings.workspace.danger_zone.title") }}
        </h3>
        <div class="border border-destructive/30 rounded-lg p-4">
          <p class="text-sm text-foreground mb-1 font-medium">
            {{ $t("settings.workspace.danger_zone.delete_workspace") }}
          </p>
          <p class="text-sm text-muted-foreground mb-4">
            {{ $t("settings.workspace.danger_zone.delete_description") }}
          </p>
          <div class="flex justify-end gap-3">
            <Button variant="destructive" @click="showDeleteConfirm = true" type="button">{{
              $t("settings.workspace.danger_zone.delete_button")
            }}</Button>
          </div>
        </div>
      </section>
    </template>

    <!-- Delete Confirm Dialog -->
    <Dialog v-model:open="showDeleteConfirm">
      <DialogContent>
        <DialogHeader>
          <div class="flex items-center gap-2">
            <AlertTriangle class="size-5 text-destructive" />
            <DialogTitle>{{ $t("settings.workspace.delete_modal.title") }}</DialogTitle>
          </div>
          <DialogDescription>{{
            $t("settings.workspace.delete_modal.description")
          }}</DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" @click="showDeleteConfirm = false">{{
            $t("settings.workspace.delete_modal.cancel")
          }}</Button>
          <Button variant="destructive" @click="confirmDeleteWorkspace">{{
            $t("settings.workspace.delete_modal.delete")
          }}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
