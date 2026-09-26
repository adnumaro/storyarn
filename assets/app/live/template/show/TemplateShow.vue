<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { ChevronLeft, X } from "@lucide/vue";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import { Textarea } from "@components/ui/textarea";
import LiveLink from "@components/navigation/LiveLink.vue";
import { useLive } from "@shared/composables/useLive";
import PageContainer from "@shell/PageContainer.vue";
import TemplateCurrentVersion from "./TemplateCurrentVersion.vue";
import TemplateInstallPanel from "./TemplateInstallPanel.vue";
import TemplateRecords from "./TemplateRecords.vue";
import type {
  TemplateCurrentVersion as CurrentVersion,
  TemplateDetail,
  TemplateInstall,
  TemplateInstallState,
  TemplateInstallationFailure,
  TemplatePublication,
  TemplateVersion,
} from "../types";

/** One template: its versions and history, and the form that creates a project from it. */
const {
  template,
  currentVersion = null,
  versions,
  publications = [],
  hasActivePublication = false,
  installs = [],
  install,
  installationFailure = null,
  templatesHref,
} = defineProps<{
  template: TemplateDetail;
  currentVersion?: CurrentVersion | null;
  versions: TemplateVersion[];
  publications?: TemplatePublication[];
  hasActivePublication?: boolean;
  installs?: TemplateInstall[];
  install: TemplateInstallState;
  installationFailure?: TemplateInstallationFailure | null;
  templatesHref: string;
}>();
const { t, te } = useI18n();
const live = useLive();
const notes = ref("");

const failureReason = computed(() => {
  const key = `workspace.new_project.templates.errors.${installationFailure?.errorCode}`;
  return t(te(key) ? key : "workspace.new_project.templates.errors.generic");
});

function publish() {
  if (hasActivePublication) return;
  live.pushEvent("publish_new_version", { publication: { version_notes: notes.value } }, () => {
    notes.value = "";
  });
}
</script>
<template>
  <PageContainer id="template-show" layout="aside">
    <nav class="text-sm">
      <LiveLink
        :to="templatesHref"
        class="inline-flex items-center gap-1 text-muted-foreground hover:text-foreground"
        ><ChevronLeft class="size-4" />{{ $t("templates.show.back") }}</LiveLink
      >
    </nav>

    <header
      class="flex flex-col gap-4 border-b border-border pb-6 md:flex-row md:items-start md:justify-between"
    >
      <div class="min-w-0">
        <div class="mb-2 flex items-center gap-2">
          <Badge :variant="template.visibility === 'public' ? 'secondary' : 'outline'">{{
            $t(`templates.visibility.${template.visibility}`)
          }}</Badge>
          <Badge variant="outline">{{ $t(`templates.status.${template.status}`) }}</Badge>
        </div>
        <h1 class="text-3xl font-semibold">{{ template.name }}</h1>
        <p class="mt-2 max-w-2xl text-sm leading-6 text-muted-foreground">
          {{ template.description || $t("templates.no_description") }}
        </p>
      </div>

      <div v-if="template.canPublish" class="flex w-full flex-col gap-2 md:w-80">
        <form
          id="publish-template-version-form"
          class="flex flex-col gap-2"
          @submit.prevent="publish"
        >
          <Textarea
            id="template-version-notes"
            v-model="notes"
            class="min-h-20"
            maxlength="2000"
            :placeholder="$t('templates.show.version_notes')"
            :disabled="hasActivePublication"
          />
          <Button
            id="publish-template-version-button"
            type="submit"
            variant="outline"
            :disabled="hasActivePublication"
            >{{
              hasActivePublication
                ? $t("templates.show.publication_running")
                : $t("templates.show.publish")
            }}</Button
          >
        </form>
        <Button
          id="archive-template-button"
          variant="ghost"
          class="text-destructive"
          @click="live.pushEvent('archive_template', {})"
          >{{ $t("templates.show.archive") }}</Button
        >
      </div>
    </header>

    <TemplateCurrentVersion :version="currentVersion" />
    <TemplateRecords
      :versions="versions"
      :publications="publications"
      :installs="installs"
      :can-publish="template.canPublish"
    />

    <template #aside>
      <div
        v-if="installationFailure"
        id="template-installation-failure"
        role="alert"
        class="flex items-start gap-2 rounded-xl border border-destructive/40 bg-destructive/5 p-4 text-sm text-destructive"
      >
        <p class="min-w-0 flex-1">
          {{
            $t("templates.show.failure.message", {
              reason: failureReason,
              reference: installationFailure.id,
            })
          }}
        </p>
        <Button
          id="dismiss-template-installation-failure"
          variant="ghost"
          size="icon-xs"
          :aria-label="$t('templates.show.failure.dismiss')"
          @click="
            live.pushEvent('dismiss_template_installation_failure', {
              installation_id: String(installationFailure.id),
            })
          "
          ><X class="size-4"
        /></Button>
      </div>
      <TemplateInstallPanel
        :versions="versions"
        :workspaces="install.workspaces"
        :defaults="install.defaults"
        :active-installations="install.activeInstallations"
        :installing="install.activeInstallations.length > 0"
        :can-install="currentVersion !== null"
      />
    </template>
  </PageContainer>
</template>
