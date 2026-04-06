<script setup lang="ts">
import { AlertTriangle, Monitor, Moon, Sun, ImagePlus, Trash2 } from "lucide-vue-next";
import { ref, watch, onMounted, onUnmounted } from "vue";
import { Button } from "@components/ui/button/index.ts";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog/index.ts";
import { Input } from "@components/ui/input/index.ts";
import { Label } from "@components/ui/label/index.ts";
import { Separator } from "@components/ui/separator/index.ts";
import { Textarea } from "@components/ui/textarea/index.ts";
import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select/index.ts";

import { useLive } from "@composables/useLive";

const {
  workspaceName = "",
  workspaceDescription = "",
  workspaceBannerUrl = "",
  sourceLocale = "",
  languageOptions = [],
  isOwner = false,
} = defineProps<{
  workspaceName?: string;
  workspaceDescription?: string;
  workspaceBannerUrl?: string;
  sourceLocale?: string;
  languageOptions?: [string, string][];
  isOwner?: boolean;
}>();

const live = useLive();

// Form states
const localName = ref(workspaceName);
const localDescription = ref(workspaceDescription);
const localBannerUrl = ref(workspaceBannerUrl);
const localSourceLocale = ref(sourceLocale);

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
    localSourceLocale.value = v;
  },
);

function saveWorkspace() {
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

// Theme toggle (Shared behavior)
const currentTheme = ref("system");

function updateThemeRef() {
  currentTheme.value = localStorage.getItem("phx:theme") || "system";
}

onMounted(() => {
  updateThemeRef();
  window.addEventListener("phx:set-theme", updateThemeRef);
});

onUnmounted(() => {
  window.removeEventListener("phx:set-theme", updateThemeRef);
});

function setTheme(theme: string) {
  if (theme === "system") {
    localStorage.removeItem("phx:theme");
  } else {
    localStorage.setItem("phx:theme", theme);
  }
  window.dispatchEvent(new CustomEvent("phx:set-theme"));
}

// Delete Workspace
const showDeleteConfirm = ref(false);

function confirmDeleteWorkspace() {
  showDeleteConfirm.value = false;
  live.pushEvent("delete", {});
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
      <form @submit.prevent="saveWorkspace" class="space-y-5">
        <div class="space-y-1.5">
          <Label for="workspace-name">{{ $t("settings.workspace.general.fields.name") }}</Label>
          <Input id="workspace-name" v-model="localName" required />
        </div>

        <div class="space-y-1.5">
          <Label for="workspace-description">{{
            $t("settings.workspace.general.fields.description")
          }}</Label>
          <Textarea
            id="workspace-description"
            v-model="localDescription"
            :rows="3"
            :placeholder="$t('settings.workspace.general.fields.description')"
          />
        </div>

        <div class="space-y-1.5">
          <Label>{{ $t("settings.workspace.general.fields.banner") }}</Label>
          <div v-if="localBannerUrl" class="space-y-2 mt-1.5">
            <div class="rounded border border-border overflow-hidden">
              <img :src="localBannerUrl" alt="Workspace banner" class="w-full h-32 object-cover" />
            </div>
            <div class="flex gap-2">
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
            v-else
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
          <Label for="source-locale">{{
            $t("settings.workspace.general.fields.source_language")
          }}</Label>
          <Select v-model="localSourceLocale">
            <SelectTrigger id="source-locale">
              <SelectValue :placeholder="$t('settings.workspace.general.fields.select_language')" />
            </SelectTrigger>
            <SelectContent>
              <SelectGroup>
                <SelectItem v-for="opt in languageOptions" :key="opt[1]" :value="opt[1]">
                  {{ opt[0] }}
                </SelectItem>
              </SelectGroup>
            </SelectContent>
          </Select>
          <p class="text-xs text-muted-foreground mt-1">
            {{ $t("settings.workspace.general.fields.source_language_hint") }}
          </p>
        </div>

        <div class="flex justify-start gap-3 pt-2">
          <Button type="submit">{{ $t("settings.workspace.general.save_changes") }}</Button>
        </div>
      </form>
    </section>

    <Separator />

    <!-- Appearance -->
    <section>
      <h3 class="text-lg font-semibold mb-4">{{ $t("settings.workspace.appearance.title") }}</h3>
      <div class="flex items-center gap-1 rounded-full border border-border bg-muted p-0.5 w-fit">
        <button
          :class="[
            'flex items-center justify-center size-8 rounded-full transition-colors',
            currentTheme === 'system'
              ? 'bg-background text-foreground shadow-sm'
              : 'text-muted-foreground hover:bg-accent hover:text-accent-foreground',
          ]"
          title="System"
          @click="setTheme('system')"
          type="button"
        >
          <Monitor class="size-4" :class="{ 'opacity-75': currentTheme !== 'system' }" />
        </button>
        <button
          :class="[
            'flex items-center justify-center size-8 rounded-full transition-colors',
            currentTheme === 'light'
              ? 'bg-background text-foreground shadow-sm'
              : 'text-muted-foreground hover:bg-accent hover:text-accent-foreground',
          ]"
          title="Light"
          @click="setTheme('light')"
          type="button"
        >
          <Sun class="size-4" :class="{ 'opacity-75': currentTheme !== 'light' }" />
        </button>
        <button
          :class="[
            'flex items-center justify-center size-8 rounded-full transition-colors',
            currentTheme === 'dark'
              ? 'bg-background text-foreground shadow-sm'
              : 'text-muted-foreground hover:bg-accent hover:text-accent-foreground',
          ]"
          title="Dark"
          @click="setTheme('dark')"
          type="button"
        >
          <Moon class="size-4" :class="{ 'opacity-75': currentTheme !== 'dark' }" />
        </button>
      </div>
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
