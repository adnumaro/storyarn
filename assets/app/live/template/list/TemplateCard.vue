<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import LiveLink from "@components/navigation/LiveLink.vue";
import { formatDate } from "@shared/utils/date-utils";
import type { TemplateCardItem } from "../types";

const {
  template,
  archived = false,
  pendingDelete = false,
} = defineProps<{
  template: TemplateCardItem;
  archived?: boolean;
  pendingDelete?: boolean;
}>();
const emit = defineEmits<{
  archive: [];
  unarchive: [];
  prepareDelete: [];
  cancelDelete: [];
  delete: [];
}>();
const { locale } = useI18n();
const updated = computed(() => formatDate(template.updatedAt, locale.value));
</script>
<template>
  <article
    :id="`template-card-${template.id}`"
    class="flex flex-col gap-4 rounded-xl border border-border bg-card p-5 shadow-xs transition-colors hover:border-foreground/20"
  >
    <div class="flex items-start justify-between gap-3">
      <div class="min-w-0">
        <h3 class="truncate text-base font-semibold">{{ template.name }}</h3>
        <p class="mt-1 line-clamp-2 text-sm text-muted-foreground">
          {{ template.description || $t("templates.no_description") }}
        </p>
      </div>
      <Badge :variant="template.visibility === 'public' ? 'secondary' : 'outline'" class="shrink-0">
        {{ $t(`templates.visibility.${template.visibility}`) }}
      </Badge>
    </div>

    <div class="flex items-center justify-between text-xs text-muted-foreground">
      <span>{{
        template.versionNumber === null
          ? $t("templates.no_version")
          : $t("templates.version", { version: template.versionNumber })
      }}</span>
      <span>{{ updated }}</span>
    </div>

    <p v-if="template.previewNames.length" class="text-xs text-muted-foreground">
      {{ template.previewNames.join(" / ") }}
    </p>

    <p
      v-if="pendingDelete"
      :id="`delete-template-confirmation-${template.id}`"
      role="alert"
      class="rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-xs text-destructive"
    >
      {{ $t("templates.card.delete_confirmation") }}
    </p>

    <div class="flex flex-wrap justify-end gap-2">
      <template v-if="template.canManage">
        <Button
          v-if="!archived"
          :id="`archive-template-${template.id}`"
          variant="ghost"
          class="text-destructive"
          @click="emit('archive')"
          >{{ $t("templates.card.archive") }}</Button
        >
        <template v-else>
          <Button
            :id="`unarchive-template-${template.id}`"
            variant="outline"
            @click="emit('unarchive')"
            >{{ $t("templates.card.restore") }}</Button
          >
          <Button
            v-if="!pendingDelete"
            :id="`delete-template-${template.id}`"
            variant="ghost"
            class="text-destructive"
            @click="emit('prepareDelete')"
            >{{ $t("templates.card.delete") }}</Button
          >
          <template v-else>
            <Button
              :id="`cancel-delete-template-${template.id}`"
              variant="ghost"
              @click="emit('cancelDelete')"
              >{{ $t("templates.card.cancel") }}</Button
            >
            <Button
              :id="`confirm-delete-template-${template.id}`"
              variant="destructive"
              @click="emit('delete')"
              >{{ $t("templates.card.delete_permanently") }}</Button
            >
          </template>
        </template>
      </template>
      <Button v-if="!archived" as-child>
        <LiveLink :to="template.href">{{ $t("templates.card.open") }}</LiveLink>
      </Button>
    </div>
  </article>
</template>
