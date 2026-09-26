<script setup lang="ts">
import { useI18n } from "vue-i18n";
import { Badge } from "@components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@components/ui/table";
import { formatTemplateDate } from "../templateFormat";
import type { TemplateInstall, TemplatePublication, TemplateVersion } from "../types";

/**
 * The template's history as sections of its page: publications and installs
 * only for readers who manage the template, versions for everyone.
 */
const {
  versions,
  publications = [],
  installs = [],
  canPublish = false,
} = defineProps<{
  versions: TemplateVersion[];
  publications?: TemplatePublication[];
  installs?: TemplateInstall[];
  canPublish?: boolean;
}>();
const { t, te, locale } = useI18n();
const date = (value: string | null) => formatTemplateDate(value, locale.value);

const statusVariant: Record<string, "default" | "secondary" | "destructive" | "outline"> = {
  published: "default",
  failed: "destructive",
  retrying: "secondary",
  queued: "secondary",
  running: "secondary",
};
function statusLabel(status: string) {
  const key = `templates.show.publications.status.${status}`;
  return t(te(key) ? key : "templates.show.publications.status.unknown");
}
function publicationSummary(publication: TemplatePublication) {
  if (publication.status === "published" && publication.versionNumber !== null)
    return t("templates.show.publications.published_version", {
      version: publication.versionNumber,
    });
  if (publication.status === "failed" && publication.errorMessage) return publication.errorMessage;
  if (publication.mode === "new") return t("templates.show.publications.new");
  if (publication.mode === "update") return t("templates.show.publications.update");
  return "";
}
</script>
<template>
  <section
    v-if="canPublish && publications.length"
    id="template-publications-panel"
    class="flex flex-col gap-4 rounded-xl border border-border bg-card p-5"
  >
    <div class="flex items-center justify-between">
      <h2 class="text-base font-semibold">{{ $t("templates.show.publications.title") }}</h2>
      <Badge variant="secondary">{{ publications.length }}</Badge>
    </div>
    <div class="flex flex-col divide-y divide-border">
      <div
        v-for="publication in publications"
        :id="`template-publication-${publication.id}`"
        :key="publication.id"
        class="flex items-center justify-between gap-4 py-3 first:pt-0 last:pb-0"
      >
        <div class="min-w-0">
          <div class="flex items-center gap-2">
            <Badge :variant="statusVariant[publication.status] ?? 'outline'">{{
              statusLabel(publication.status)
            }}</Badge>
            <span class="truncate text-sm font-medium">{{ publication.name }}</span>
          </div>
          <p class="mt-1 text-xs text-muted-foreground">{{ publicationSummary(publication) }}</p>
        </div>
        <span class="shrink-0 text-xs text-muted-foreground">{{
          date(publication.insertedAt)
        }}</span>
      </div>
    </div>
  </section>

  <section
    id="template-versions-panel"
    class="flex flex-col gap-4 rounded-xl border border-border bg-card p-5"
  >
    <div class="flex items-center justify-between">
      <h2 class="text-base font-semibold">{{ $t("templates.show.versions.title") }}</h2>
      <Badge id="template-version-count" variant="secondary">{{ versions.length }}</Badge>
    </div>
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{{ $t("templates.show.versions.version") }}</TableHead>
          <TableHead>{{ $t("templates.show.versions.published") }}</TableHead>
          <TableHead v-if="canPublish">{{ $t("templates.show.versions.by") }}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody id="template-versions">
        <TableRow
          v-for="version in versions"
          :id="`template-version-${version.id}`"
          :key="version.id"
        >
          <TableCell>
            <div class="flex items-center gap-2">
              <span class="font-medium">{{
                $t("templates.version", { version: version.versionNumber })
              }}</span>
              <Badge v-if="version.isCurrent">{{ $t("templates.show.versions.current") }}</Badge>
            </div>
            <p v-if="version.notes" class="mt-1 max-w-lg text-xs text-muted-foreground">
              {{ version.notes }}
            </p>
          </TableCell>
          <TableCell>{{ date(version.publishedAt) }}</TableCell>
          <TableCell v-if="canPublish">{{ version.publishedByEmail }}</TableCell>
        </TableRow>
        <TableRow v-if="!versions.length" id="template-versions-empty">
          <TableCell :colspan="canPublish ? 3 : 2" class="text-muted-foreground">{{
            $t("templates.show.versions.empty")
          }}</TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </section>

  <section
    v-if="canPublish"
    id="template-install-history"
    class="flex flex-col gap-4 rounded-xl border border-border bg-card p-5"
  >
    <div class="flex items-center justify-between">
      <h2 class="text-base font-semibold">{{ $t("templates.show.installs.title") }}</h2>
      <Badge variant="secondary">{{ installs.length }}</Badge>
    </div>
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{{ $t("templates.show.installs.version") }}</TableHead>
          <TableHead>{{ $t("templates.show.installs.installed") }}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody id="template-installs">
        <TableRow
          v-for="install in installs"
          :id="`template-install-${install.id}`"
          :key="install.id"
        >
          <TableCell>{{ install.versionNumber }}</TableCell>
          <TableCell>{{ date(install.installedAt) }}</TableCell>
        </TableRow>
        <TableRow v-if="!installs.length" id="template-installs-empty">
          <TableCell colspan="2" class="text-muted-foreground">{{
            $t("templates.show.installs.empty")
          }}</TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </section>
</template>
