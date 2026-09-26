<script setup lang="ts">
import { ref, watch } from "vue";
import { Search } from "@lucide/vue";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import LiveLink from "@components/navigation/LiveLink.vue";
import { useLive } from "@shared/composables/useLive";
import PageContainer from "@shell/PageContainer.vue";
import TemplateCard from "./TemplateCard.vue";
import type { TemplateSection } from "../types";

/** The templates a reader can see: their own private ones, Storyarn demos and the archive. */
const {
  sections,
  query = "",
  pendingDeleteId = null,
  workspacesHref,
} = defineProps<{
  sections: TemplateSection[];
  query?: string;
  pendingDeleteId?: number | null;
  workspacesHref: string;
}>();
const live = useLive();
const search = ref(query);
watch(
  () => query,
  (value) => (search.value = value),
);

function submitSearch() {
  live.pushEvent("search", { search: { q: search.value } });
}
function templateAction(event: string, id?: number) {
  live.pushEvent(event, id === undefined ? {} : { id: String(id) });
}
</script>
<template>
  <PageContainer id="templates-index">
    <header class="flex items-end justify-between gap-3 border-b border-border pb-6">
      <div>
        <p class="text-sm font-medium text-muted-foreground">{{ $t("templates.list.eyebrow") }}</p>
        <h1 class="text-3xl font-semibold">{{ $t("templates.list.title") }}</h1>
      </div>
      <Button variant="ghost" as-child>
        <LiveLink :to="workspacesHref">{{ $t("templates.list.workspaces") }}</LiveLink>
      </Button>
    </header>

    <form
      id="template-search-form"
      role="search"
      class="flex flex-col gap-3 rounded-xl border border-border p-4 md:flex-row md:items-end"
      @submit.prevent="submitSearch"
    >
      <label class="flex flex-1 flex-col gap-2 text-sm">
        <span class="font-medium">{{ $t("templates.list.search_label") }}</span>
        <Input
          id="template-search-input"
          v-model="search"
          type="search"
          :placeholder="$t('templates.list.search_placeholder')"
        />
      </label>
      <div class="flex gap-2">
        <Button id="template-search-submit" type="submit"
          ><Search class="size-4" />{{ $t("templates.list.search") }}</Button
        >
        <Button
          v-if="query"
          id="template-search-clear"
          type="button"
          variant="ghost"
          @click="templateAction('clear_search')"
          >{{ $t("templates.list.clear") }}</Button
        >
      </div>
    </form>

    <section
      v-for="section in sections"
      :id="section.key === 'private' ? 'my-templates-section' : `${section.key}-templates-section`"
      :key="section.key"
      class="flex flex-col gap-4"
    >
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-semibold">{{ $t(`templates.list.sections.${section.key}`) }}</h2>
        <Badge variant="secondary">{{ section.totalCount }}</Badge>
      </div>

      <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
        <TemplateCard
          v-for="template in section.templates"
          :key="template.id"
          :template="template"
          :archived="section.key === 'archived'"
          :pending-delete="section.key === 'archived' && pendingDeleteId === template.id"
          @archive="templateAction('archive_template', template.id)"
          @unarchive="templateAction('unarchive_template', template.id)"
          @prepare-delete="templateAction('prepare_delete_template', template.id)"
          @cancel-delete="templateAction('cancel_delete_template')"
          @delete="templateAction('delete_template', template.id)"
        />
        <p
          v-if="!section.templates.length"
          :id="section.key === 'private' ? 'my-templates-empty' : `${section.key}-templates-empty`"
          class="col-span-full rounded-xl border border-dashed border-border p-6 text-sm text-muted-foreground"
        >
          {{ $t(`templates.list.empty.${section.key}`) }}
        </p>
      </div>

      <nav v-if="section.totalPages > 1" class="flex items-center justify-end gap-2">
        <Button
          v-if="section.prevHref"
          :id="`${section.key}-templates-prev-page`"
          variant="outline"
          as-child
        >
          <LiveLink :to="section.prevHref" mode="patch">{{
            $t("templates.list.previous")
          }}</LiveLink>
        </Button>
        <span class="text-sm text-muted-foreground">{{
          $t("templates.list.page", { page: section.page, total: section.totalPages })
        }}</span>
        <Button
          v-if="section.nextHref"
          :id="`${section.key}-templates-next-page`"
          variant="outline"
          as-child
        >
          <LiveLink :to="section.nextHref" mode="patch">{{ $t("templates.list.next") }}</LiveLink>
        </Button>
      </nav>
    </section>
  </PageContainer>
</template>
