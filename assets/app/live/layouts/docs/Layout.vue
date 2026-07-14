<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import {
  ArrowLeft,
  ArrowRight,
  ChevronDown,
  ChevronRight,
  PanelLeft,
  Search,
  X,
} from "lucide-vue-next";
import LiveLink from "@components/navigation/LiveLink.vue";
import ThemeSelector from "@components/ThemeSelector.vue";
import { consumeHistoryScroll } from "@app/shared/navigation/historyScroll";
import { useLive } from "@shared/composables/useLive";
import { useMediaQuery } from "@shared/composables/useMediaQuery";

interface DocsCategory {
  id: string;
  label: string;
  expanded: boolean;
}

interface DocsGuideNav {
  category: string;
  categoryLabel: string;
  section?: string | null;
  sectionLabel?: string | null;
  sectionOrder?: number | null;
  path?: string[];
  slug: string;
  title: string;
  url: string;
}

interface DocsGuideSection {
  id: string;
  label: string;
  guides: DocsGuideNav[];
}

interface DocsTocEntry {
  level: number;
  id: string;
  text: string;
}

interface DocsGuide extends DocsGuideNav {
  description?: string | null;
  toc: DocsTocEntry[];
}

interface DocsLayoutUrls {
  home: string;
  docs: string;
  workspaces: string;
  login: string;
}

interface DocsLayoutProps {
  signedIn: boolean;
  urls: DocsLayoutUrls;
  sidebarOpen: boolean;
  categories: DocsCategory[];
  guides: DocsGuideNav[];
  guide: DocsGuide | null;
  search: {
    query: string;
    results: DocsGuideNav[] | null;
  };
  prev?: DocsGuideNav | null;
  next?: DocsGuideNav | null;
}

const { docs: docsProp } = defineProps<{
  docs: DocsLayoutProps;
}>();

const live = useLive();
const { t } = useI18n();
const docs = computed(() => docsProp);
const searchQuery = ref(docs.value.search.query);
const sidebarVisible = ref(docs.value.sidebarOpen);
const desktopSidebar = useMediaQuery("(min-width: 1024px)");
const sidebarInteractive = computed(() => sidebarVisible.value || desktopSidebar.value);
let restoreScrollFrame: number | undefined;

function restoreDocsScroll(): void {
  if (restoreScrollFrame !== undefined) window.cancelAnimationFrame(restoreScrollFrame);

  const scrollTop = consumeHistoryScroll(0, "docs-main");
  restoreScrollFrame = window.requestAnimationFrame(() => {
    document.getElementById("docs-main")?.scrollTo({ top: scrollTop });
  });
}

onMounted(restoreDocsScroll);
onUnmounted(() => {
  if (restoreScrollFrame !== undefined) window.cancelAnimationFrame(restoreScrollFrame);
});

watch(() => docs.value.guide?.url, restoreDocsScroll);

watch(
  () => docs.value.search.query,
  (query) => {
    if (query !== searchQuery.value) searchQuery.value = query;
  },
);

watch(
  () => docs.value.sidebarOpen,
  (open) => {
    sidebarVisible.value = open;
  },
);

const guidesByCategory = computed(() => {
  const grouped = new Map<string, { root: DocsGuideNav[]; sections: DocsGuideSection[] }>();

  for (const guide of docs.value.guides) {
    const guides = grouped.get(guide.category) ?? { root: [], sections: [] };

    if (guide.section) {
      let section = guides.sections.find((item) => item.id === guide.section);

      if (!section) {
        section = {
          id: guide.section,
          label: guide.sectionLabel ?? guide.section,
          guides: [],
        };
        guides.sections.push(section);
      }

      section.guides.push(guide);
    } else {
      guides.root.push(guide);
    }

    grouped.set(guide.category, guides);
  }

  return grouped;
});

const searchResultsVisible = computed(() => docs.value.search.results !== null);

function rootGuidesFor(categoryId: string): DocsGuideNav[] {
  return guidesByCategory.value.get(categoryId)?.root ?? [];
}

function sectionsFor(categoryId: string): DocsGuideSection[] {
  return guidesByCategory.value.get(categoryId)?.sections ?? [];
}

function activeGuide(guide: DocsGuideNav): boolean {
  return docs.value.guide?.url === guide.url;
}

function onSearch(event: Event): void {
  const target = event.target as HTMLInputElement;
  searchQuery.value = target.value;
  live.pushEvent("search", { query: target.value });
}

function clearSearch(): void {
  searchQuery.value = "";
  live.pushEvent("clear_search", {});
}

function toggleSidebar(): void {
  sidebarVisible.value = !sidebarVisible.value;
  live.pushEvent("toggle_sidebar", {});
}

function toggleCategory(category: string): void {
  live.pushEvent("toggle_category", { category });
}

function resultsLabel(count: number): string {
  return t(count === 1 ? "docs.result" : "docs.results", { count });
}
</script>

<template>
  <div class="relative h-screen overflow-hidden bg-surface">
    <aside
      :aria-hidden="!sidebarInteractive"
      :inert="!sidebarInteractive"
      class="absolute inset-y-0 left-0 z-0 w-[calc(100vw-4rem)] sm:w-68 lg:w-68 overflow-y-auto pt-6 pr-4"
    >
      <nav class="px-4 space-y-1">
        <div class="mb-5">
          <form class="relative" @submit.prevent="live.pushEvent('search', { query: searchQuery })">
            <Search class="size-4 absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
            <input
              type="text"
              :value="searchQuery"
              :placeholder="$t('docs.search_placeholder')"
              name="query"
              class="h-8 rounded-md border border-input bg-background px-2 text-sm input-bordered w-full pl-9 pr-8"
              autocomplete="off"
              @input="onSearch"
            />
            <button
              v-if="searchQuery !== ''"
              type="button"
              class="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
              :aria-label="$t('docs.clear_search')"
              @click="clearSearch"
            >
              <X class="size-4" />
            </button>
          </form>
        </div>

        <div v-if="searchResultsVisible" class="mb-4">
          <p class="text-xs text-muted-foreground mb-2 px-3">
            {{ resultsLabel(docs.search.results?.length ?? 0) }}
          </p>
          <ul class="space-y-0.5">
            <li v-for="result in docs.search.results ?? []" :key="result.url">
              <LiveLink
                :to="result.url"
                class="block px-3 py-2 rounded-lg text-sm hover:bg-muted truncate"
              >
                <span class="text-foreground">{{ result.title }}</span>
                <span class="text-xs text-muted-foreground ml-1">{{ result.categoryLabel }}</span>
              </LiveLink>
            </li>
          </ul>
        </div>

        <template v-else>
          <div v-for="category in docs.categories" :key="category.id" class="mb-1">
            <button
              type="button"
              class="flex items-center justify-between w-full px-3 py-2 rounded-lg text-sm font-semibold text-foreground hover:bg-muted transition-colors text-left"
              @click="toggleCategory(category.id)"
            >
              <span class="text-left">{{ category.label }}</span>
              <ChevronDown v-if="category.expanded" class="size-4 text-muted-foreground" />
              <ChevronRight v-else class="size-4 text-muted-foreground" />
            </button>

            <ul v-if="category.expanded" class="mt-0.5 ml-3 border-l border-border space-y-0.5">
              <li v-for="guide in rootGuidesFor(category.id)" :key="guide.url">
                <LiveLink
                  :to="guide.url"
                  :class="[
                    'block px-3 py-1.5 text-sm transition-colors -ml-px border-l-2',
                    activeGuide(guide)
                      ? 'border-primary text-primary font-medium'
                      : 'border-transparent text-muted-foreground hover:text-foreground hover:border-border',
                  ]"
                >
                  {{ guide.title }}
                </LiveLink>
              </li>
              <li v-for="section in sectionsFor(category.id)" :key="section.id" class="pt-1">
                <p class="px-3 py-1 text-xs font-medium text-muted-foreground">
                  {{ section.label }}
                </p>
                <ul class="space-y-0.5">
                  <li v-for="guide in section.guides" :key="guide.url">
                    <LiveLink
                      :to="guide.url"
                      :class="[
                        'block px-3 py-1.5 text-sm transition-colors -ml-px border-l-2',
                        activeGuide(guide)
                          ? 'border-primary text-primary font-medium'
                          : 'border-transparent text-muted-foreground hover:text-foreground hover:border-border',
                      ]"
                    >
                      {{ guide.title }}
                    </LiveLink>
                  </li>
                </ul>
              </li>
            </ul>
          </div>
        </template>
      </nav>
    </aside>

    <div
      :class="[
        'relative z-10 h-full min-w-0 flex flex-col overflow-hidden bg-background border-l border-border transition-transform duration-300 ease-out will-change-transform lg:ml-64 lg:w-[calc(100%-16rem)] lg:translate-x-0 lg:rounded-l-2xl',
        sidebarVisible
          ? 'translate-x-[calc(100vw-3.5rem)] sm:translate-x-64 shadow-xl rounded-l-2xl lg:shadow-none lg:rounded-none'
          : 'translate-x-0',
      ]"
    >
      <header
        class="flex items-center h-12 px-4 sm:px-6 lg:px-8 border-b border-border bg-background shrink-0"
      >
        <div class="flex-none mr-4 lg:hidden">
          <button
            type="button"
            :class="[
              'inline-flex items-center justify-center size-9 rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-foreground',
              sidebarVisible && 'bg-accent text-foreground',
            ]"
            :aria-label="sidebarVisible ? $t('docs.hide_sidebar') : $t('docs.show_sidebar')"
            :title="sidebarVisible ? $t('docs.hide_sidebar') : $t('docs.show_sidebar')"
            @click="toggleSidebar"
          >
            <PanelLeft class="size-5" />
          </button>
        </div>

        <div class="flex-1 flex items-center min-w-0">
          <LiveLink
            :to="docs.urls.docs"
            class="flex min-w-0 items-center"
            aria-label="Storyarn docs"
          >
            <img
              :src="'/images/logos/logo-name-black-docs.png'"
              alt="Storyarn docs"
              class="h-auto w-40 sm:w-52 dark:hidden"
            />
            <img
              :src="'/images/logos/logo-name-white-docs.png'"
              alt="Storyarn docs"
              class="hidden h-auto w-40 sm:w-52 dark:block"
            />
          </LiveLink>
        </div>

        <div class="flex-none flex items-center gap-2">
          <ThemeSelector
            size="xs"
            :labels="{
              system: $t('docs.theme_system'),
              light: $t('docs.theme_light'),
              dark: $t('docs.theme_dark'),
            }"
          />

          <LiveLink
            :to="docs.signedIn ? docs.urls.workspaces : docs.urls.login"
            class="inline-flex items-center justify-center h-8 px-3 text-sm rounded-md hover:bg-accent transition-colors"
          >
            {{ docs.signedIn ? $t("docs.dashboard") : $t("docs.login") }}
          </LiveLink>
        </div>
      </header>

      <div class="flex-1 flex overflow-hidden">
        <main
          id="docs-main"
          class="flex-1 overflow-y-auto xl:flex xl:items-start xl:justify-between px-4 sm:px-8 lg:px-12"
        >
          <div class="flex-1 w-full max-w-4xl mx-auto py-8 min-w-0">
            <div v-if="docs.guide" class="mb-8">
              <p class="text-xs uppercase tracking-wider text-primary font-semibold mb-1">
                {{ docs.guide.categoryLabel }}
              </p>
              <h1 class="text-3xl font-bold">{{ docs.guide.title }}</h1>
              <p v-if="docs.guide.description" class="text-muted-foreground mt-2">
                {{ docs.guide.description }}
              </p>
            </div>

            <slot />

            <nav
              v-if="docs.prev || docs.next"
              class="flex items-center justify-between mt-12 pt-8 border-t border-border"
            >
              <div>
                <LiveLink
                  v-if="docs.prev"
                  :to="docs.prev.url"
                  class="group flex flex-col items-start"
                >
                  <span class="text-xs text-muted-foreground group-hover:text-muted-foreground">
                    <ArrowLeft class="size-3 inline" />
                    {{ $t("docs.previous") }}
                  </span>
                  <span class="text-sm font-medium text-primary">{{ docs.prev.title }}</span>
                </LiveLink>
              </div>

              <div>
                <LiveLink
                  v-if="docs.next"
                  :to="docs.next.url"
                  class="group flex flex-col items-end"
                >
                  <span class="text-xs text-muted-foreground group-hover:text-muted-foreground">
                    {{ $t("docs.next") }}
                    <ArrowRight class="size-3 inline" />
                  </span>
                  <span class="text-sm font-medium text-primary">{{ docs.next.title }}</span>
                </LiveLink>
              </div>
            </nav>
          </div>

          <aside
            v-if="docs.guide && docs.guide.toc.length > 0"
            id="docs-toc"
            class="hidden xl:block sticky top-0 w-60 shrink-0 py-8 overflow-y-auto"
            style="max-height: 100vh"
          >
            <p class="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-3">
              {{ $t("docs.on_this_page") }}
            </p>
            <nav class="border-l border-border">
              <a
                v-for="entry in docs.guide.toc"
                :key="entry.id"
                :href="`#${entry.id}`"
                :data-toc-id="entry.id"
                data-live-link-exempt="docs table of contents anchor"
                :class="[
                  'docs-toc-link block text-sm leading-relaxed transition-colors hover:text-primary',
                  entry.level === 3 ? 'pl-5' : 'pl-3',
                  'text-muted-foreground',
                ]"
              >
                {{ entry.text }}
              </a>
            </nav>
          </aside>
        </main>
      </div>
    </div>
  </div>
</template>
