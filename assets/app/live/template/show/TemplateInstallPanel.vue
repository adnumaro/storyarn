<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { LoaderCircle } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import { useLive } from "@shared/composables/useLive";
import type {
  TemplateActiveInstallation,
  TemplateInstallDefaults,
  TemplateVersion,
} from "../types";

/** Creates a project from the template in a workspace the reader can add projects to. */
const {
  versions,
  workspaces,
  defaults,
  activeInstallations = [],
  installing = false,
  canInstall = true,
} = defineProps<{
  versions: TemplateVersion[];
  workspaces: Array<{ id: string; name: string }>;
  defaults: TemplateInstallDefaults;
  activeInstallations?: TemplateActiveInstallation[];
  /** An installation of this template is already running. */
  installing?: boolean;
  /** The template has a published version to install. */
  canInstall?: boolean;
}>();
const { t, te } = useI18n();
const live = useLive();
const workspaceId = ref(defaults.workspaceId);
const versionId = ref(defaults.versionId);
const name = ref(defaults.name);
const starting = ref(false);
watch(
  () => defaults,
  (value) => {
    workspaceId.value = value.workspaceId;
    versionId.value = value.versionId;
    name.value = value.name;
  },
);
const disabled = computed(() => installing || starting.value);
const submittable = computed(
  () => !disabled.value && canInstall && workspaces.length > 0 && name.value.trim() !== "",
);

function stage(value: string) {
  const key = `workspace.new_project.templates.stages.${value}`;
  return t(te(key) ? key : "workspace.new_project.templates.installing");
}
function versionLabel(version: TemplateVersion) {
  const label = t("templates.version", { version: version.versionNumber });
  return version.isCurrent ? t("templates.show.install.current_option", { version: label }) : label;
}
function install() {
  if (!submittable.value) return;
  starting.value = true;
  const done = () => (starting.value = false);
  live.pushEvent(
    "install",
    { install: { workspace_id: workspaceId.value, version_id: versionId.value, name: name.value } },
    done,
    done,
  );
}
</script>
<template>
  <section
    id="template-install-panel"
    class="flex flex-col gap-4 rounded-xl border border-border bg-card p-5 shadow-xs"
  >
    <h2 class="text-base font-semibold">{{ $t("templates.show.install.title") }}</h2>

    <div
      v-if="activeInstallations.length"
      id="template-active-installations"
      class="flex flex-col gap-3"
      aria-live="polite"
    >
      <article
        v-for="installation in activeInstallations"
        :id="`template-active-installation-${installation.id}`"
        :key="installation.id"
        class="flex items-start gap-3 rounded-lg border border-primary/30 bg-primary/5 p-4"
      >
        <LoaderCircle class="mt-0.5 size-4 shrink-0 animate-spin text-primary" />
        <div class="min-w-0">
          <p class="truncate text-sm font-semibold">{{ installation.projectName }}</p>
          <p class="mt-1 text-xs text-muted-foreground">{{ stage(installation.stage) }}</p>
          <p class="mt-2 text-xs text-muted-foreground">
            {{ $t("templates.show.install.reference", { reference: installation.id }) }}
          </p>
        </div>
      </article>
    </div>

    <form id="template-install-form" class="flex flex-col gap-4" @submit.prevent="install">
      <label class="flex flex-col gap-2 text-sm">
        <span class="font-medium">{{ $t("templates.show.install.workspace") }}</span>
        <Select v-model="workspaceId" :disabled="disabled || !workspaces.length">
          <SelectTrigger id="template-install-workspace" class="w-full"
            ><SelectValue
          /></SelectTrigger>
          <SelectContent>
            <SelectItem v-for="workspace in workspaces" :key="workspace.id" :value="workspace.id">{{
              workspace.name
            }}</SelectItem>
          </SelectContent>
        </Select>
      </label>

      <label class="flex flex-col gap-2 text-sm">
        <span class="font-medium">{{ $t("templates.show.install.version") }}</span>
        <Select v-model="versionId" :disabled="disabled || !versions.length">
          <SelectTrigger id="template-install-version" class="w-full"
            ><SelectValue
          /></SelectTrigger>
          <SelectContent>
            <SelectItem v-for="version in versions" :key="version.id" :value="String(version.id)">{{
              versionLabel(version)
            }}</SelectItem>
          </SelectContent>
        </Select>
      </label>

      <label class="flex flex-col gap-2 text-sm">
        <span class="font-medium">{{ $t("templates.show.install.name") }}</span>
        <Input
          id="template-install-name"
          v-model="name"
          type="text"
          maxlength="100"
          required
          :disabled="disabled"
        />
      </label>

      <Button id="template-install-submit" type="submit" class="w-full" :disabled="!submittable">
        <template v-if="installing"
          ><LoaderCircle class="size-4 animate-spin" />{{
            $t("templates.show.install.in_progress")
          }}</template
        >
        <template v-else-if="starting">{{ $t("templates.show.install.starting") }}</template>
        <template v-else>{{ $t("templates.show.install.submit") }}</template>
      </Button>
    </form>
  </section>
</template>
