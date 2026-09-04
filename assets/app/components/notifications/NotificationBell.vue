<script setup lang="ts">
import {
  Bell,
  Check,
  CheckCircle2,
  CircleAlert,
  LoaderCircle,
  MessageSquare,
  Plus,
  Trash2,
  XCircle,
} from "@lucide/vue";
import { computed, onMounted, onUnmounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import LiveLink from "@components/navigation/LiveLink.vue";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import { useLive } from "@shared/composables/useLive";
import type { NotificationCenterState, NotificationFilter, NotificationItem } from "./types";

const { locale, t } = useI18n();
const live = useLive();
const center = ref<NotificationCenterState>({ filter: "all", items: [], unreadCount: 0 });
const filters: NotificationFilter[] = ["all", "unread"];
const pending = ref(false);
const error = ref(false);
const loaded = ref(false);
const open = ref(false);
const now = ref(Date.now());

interface PendingRequest {
  event: string;
  payload: Record<string, unknown>;
}

let requestToken = 0;
let notificationsUpdatedRef: number | undefined;
let clock: ReturnType<typeof setInterval> | undefined;
let lastRequest: PendingRequest | null = null;

const unreadBadge = computed(() =>
  center.value.unreadCount > 99 ? "99+" : String(center.value.unreadCount),
);

const triggerLabel = computed(() =>
  center.value.unreadCount > 0
    ? t("notifications.trigger_unread", { count: center.value.unreadCount })
    : t("notifications.trigger"),
);

onMounted(() => {
  notificationsUpdatedRef = live.handleEvent("notifications_updated", (payload) => {
    const state = parseCenter(payload);
    if (!state) return;

    center.value = state;
    loaded.value = true;
    error.value = false;
  });

  clock = setInterval(() => {
    now.value = Date.now();
  }, 60_000);

  refreshNotifications();
});

onUnmounted(() => {
  if (notificationsUpdatedRef !== undefined) {
    live.removeHandleEvent(notificationsUpdatedRef);
  }

  if (clock !== undefined) clearInterval(clock);
});

function parseCenter(payload: Record<string, unknown>): NotificationCenterState | null {
  const filter = payload.filter;
  const items = payload.items;
  const unreadCount = payload.unreadCount;

  if (
    (filter !== "all" && filter !== "unread") ||
    !Array.isArray(items) ||
    typeof unreadCount !== "number" ||
    unreadCount < 0 ||
    !items.every(validItem)
  ) {
    return null;
  }

  return {
    filter,
    items: items as NotificationItem[],
    unreadCount,
  };
}

function validItem(item: unknown): item is NotificationItem {
  if (!item || typeof item !== "object") return false;

  const candidate = item as Partial<NotificationItem>;
  return (
    typeof candidate.id === "number" &&
    typeof candidate.kind === "string" &&
    typeof candidate.createdAt === "string" &&
    (candidate.href === null || typeof candidate.href === "string") &&
    (candidate.readAt === null || typeof candidate.readAt === "string")
  );
}

function runRequest(event: string, payload: Record<string, unknown>): void {
  const token = ++requestToken;
  lastRequest = { event, payload };
  pending.value = true;
  error.value = false;

  live.pushEvent(
    event,
    payload,
    (reply) => {
      if (token !== requestToken) return;

      const state = parseCenter(reply);
      pending.value = false;

      if (state) {
        center.value = state;
        loaded.value = true;
        lastRequest = null;
      } else {
        error.value = true;
      }
    },
    () => {
      if (token !== requestToken) return;
      pending.value = false;
      error.value = true;
    },
  );
}

function retry(): void {
  if (!lastRequest) return;
  runRequest(lastRequest.event, lastRequest.payload);
}

function changeFilter(filter: NotificationFilter): void {
  if (pending.value || filter === center.value.filter) return;
  runRequest("notification_filter_changed", { filter });
}

function markRead(notificationId: number): void {
  if (pending.value) return;
  runRequest("mark_notification_read", { id: notificationId });
}

function markAllRead(): void {
  if (pending.value || center.value.unreadCount === 0) return;
  runRequest("mark_all_notifications_read", {});
}

function handleNotificationOpen(notification: NotificationItem): void {
  if (notification.readAt === null) {
    runRequest("mark_notification_read", { id: notification.id });
  }
  open.value = false;
}

function refreshNotifications(): void {
  if (pending.value) return;
  runRequest("refresh_notifications", { filter: center.value.filter });
}

function handlePopoverOpen(isOpen: boolean): void {
  if (isOpen) refreshNotifications();
}

function entityLabel(notification: NotificationItem): string {
  if (!notification.entityType) return t("notifications.entities.content");

  const key = `notifications.entities.${notification.entityType}`;
  const translated = t(key);
  return translated === key ? t("notifications.entities.content") : translated;
}

function commentText(notification: NotificationItem, actor: string): string | null {
  if (notification.kind === "comment_mention") {
    return t("notifications.messages.comment_mention", { actor });
  }

  if (notification.kind === "comment_reply") {
    return t("notifications.messages.comment_reply", { actor });
  }

  return null;
}

function notificationText(notification: NotificationItem): string {
  const actor = notification.actorName || t("notifications.actor_fallback");
  const entity = entityLabel(notification);
  const name = notification.entityName;
  const comment = commentText(notification, actor);

  if (comment) return comment;

  if (notification.kind === "content_created") {
    return name
      ? t("notifications.messages.created_named", { actor, entity, name })
      : t("notifications.messages.created", { actor, entity });
  }

  if (notification.kind === "content_deleted") {
    return name
      ? t("notifications.messages.deleted_named", { actor, entity, name })
      : t("notifications.messages.deleted", { actor, entity });
  }

  if (notification.status === "failure") {
    return name
      ? t("notifications.messages.async_failure_named", { entity, name })
      : t("notifications.messages.async_failure", { entity });
  }

  return name
    ? t("notifications.messages.async_success_named", { entity, name })
    : t("notifications.messages.async_success", { entity });
}

function relativeTime(isoDate: string): string {
  const timestamp = Date.parse(isoDate);
  if (Number.isNaN(timestamp)) return "";

  const differenceSeconds = Math.round((timestamp - now.value) / 1000);
  const absoluteSeconds = Math.abs(differenceSeconds);
  const formatter = new Intl.RelativeTimeFormat(locale.value, { numeric: "auto" });

  if (absoluteSeconds < 45) return formatter.format(0, "second");
  if (absoluteSeconds < 3_600)
    return formatter.format(Math.round(differenceSeconds / 60), "minute");
  if (absoluteSeconds < 86_400)
    return formatter.format(Math.round(differenceSeconds / 3_600), "hour");
  if (absoluteSeconds < 604_800)
    return formatter.format(Math.round(differenceSeconds / 86_400), "day");

  return new Intl.DateTimeFormat(locale.value, {
    day: "numeric",
    month: "short",
    year:
      new Date(timestamp).getFullYear() === new Date(now.value).getFullYear()
        ? undefined
        : "numeric",
  }).format(timestamp);
}
</script>

<template>
  <Popover v-model:open="open" @update:open="handlePopoverOpen">
    <PopoverTrigger as-child>
      <button
        id="notification-bell-trigger"
        type="button"
        class="toolbar-btn relative size-9"
        :aria-label="triggerLabel"
        :title="triggerLabel"
      >
        <Bell class="size-4" />
        <span
          v-if="center.unreadCount > 0"
          aria-hidden="true"
          class="absolute -right-1 -top-1 flex min-w-4.5 h-4.5 items-center justify-center rounded-full bg-primary px-1 text-[10px] font-semibold leading-none text-primary-foreground shadow-sm ring-2 ring-background"
        >
          {{ unreadBadge }}
        </span>
      </button>
    </PopoverTrigger>

    <PopoverContent
      align="end"
      side="bottom"
      :side-offset="8"
      class="flex max-h-[min(calc(100dvh_-_1rem),var(--reka-popover-content-available-height))] w-96 max-w-[calc(100vw-1rem)] flex-col overflow-hidden p-0"
      :aria-busy="pending"
    >
      <div
        class="flex shrink-0 items-center justify-between gap-3 border-b border-border/70 px-4 py-3"
      >
        <div class="min-w-0">
          <h2 class="text-sm font-semibold">{{ t("notifications.title") }}</h2>
          <p class="text-xs text-muted-foreground">
            {{ t("notifications.unread_count", { count: center.unreadCount }) }}
          </p>
        </div>
        <button
          type="button"
          class="shrink-0 text-xs font-medium text-primary transition-colors hover:text-primary/80 disabled:cursor-default disabled:text-muted-foreground/60"
          :disabled="pending || center.unreadCount === 0"
          @click="markAllRead"
        >
          {{ t("notifications.mark_all") }}
        </button>
      </div>

      <div class="shrink-0 border-b border-border/70 px-3 py-2">
        <div
          role="group"
          :aria-label="t('notifications.filters.label')"
          class="inline-flex rounded-lg bg-muted p-0.5"
        >
          <button
            v-for="filter in filters"
            :key="filter"
            type="button"
            :aria-pressed="center.filter === filter"
            :disabled="pending"
            :class="[
              'rounded-md px-3 py-1 text-xs font-medium transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
              center.filter === filter
                ? 'bg-background text-foreground shadow-sm'
                : 'text-muted-foreground hover:text-foreground',
            ]"
            @click="changeFilter(filter)"
          >
            {{ t(`notifications.filters.${filter}`) }}
          </button>
        </div>
      </div>

      <div
        v-if="error"
        role="alert"
        class="flex shrink-0 items-center gap-3 border-b border-border/70 px-4 py-3"
      >
        <CircleAlert class="size-4 shrink-0 text-destructive" />
        <p class="min-w-0 flex-1 text-xs text-muted-foreground">
          {{ t("notifications.error") }}
        </p>
        <button type="button" class="text-xs font-medium text-primary" @click="retry">
          {{ t("notifications.retry") }}
        </button>
      </div>

      <div
        v-if="!loaded && !error"
        role="status"
        class="flex min-h-32 flex-1 flex-col items-center justify-center gap-2 px-6 py-8 text-center text-muted-foreground"
      >
        <LoaderCircle aria-hidden="true" class="size-5 animate-spin" />
        <p class="text-xs">{{ t("notifications.updating") }}</p>
      </div>

      <p v-else-if="pending" class="sr-only" role="status">
        {{ t("notifications.updating") }}
      </p>

      <ul v-if="loaded && center.items.length > 0" class="min-h-0 flex-1 overflow-y-auto py-1">
        <li
          v-for="notification in center.items"
          :key="notification.id"
          :class="[
            'group relative flex gap-3 px-4 py-3 transition-colors hover:bg-muted/60',
            notification.readAt === null && 'bg-primary/4',
          ]"
        >
          <div
            :class="[
              'mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full',
              notification.status === 'failure'
                ? 'bg-destructive/10 text-destructive'
                : 'bg-primary/10 text-primary',
            ]"
          >
            <XCircle v-if="notification.status === 'failure'" class="size-4" />
            <CheckCircle2 v-else-if="notification.kind === 'async_operation'" class="size-4" />
            <Plus v-else-if="notification.kind === 'content_created'" class="size-4" />
            <MessageSquare
              v-else-if="
                notification.kind === 'comment_mention' || notification.kind === 'comment_reply'
              "
              class="size-4"
            />
            <Trash2 v-else class="size-4" />
          </div>

          <div class="min-w-0 flex-1 pr-7">
            <p
              :class="[
                'text-sm leading-5',
                notification.readAt === null ? 'font-medium text-foreground' : 'text-foreground/80',
              ]"
            >
              <LiveLink
                v-if="notification.href"
                :id="`notification-link-${notification.id}`"
                :to="notification.href"
                class="rounded-sm transition-colors hover:text-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                @click="handleNotificationOpen(notification)"
              >
                {{ notificationText(notification) }}
              </LiveLink>
              <span v-else>{{ notificationText(notification) }}</span>
            </p>
            <p
              v-if="notification.entityType === 'comment' && !notification.href"
              class="mt-1 text-xs text-muted-foreground"
            >
              {{ t("notifications.comment_unavailable") }}
            </p>
            <div class="mt-1 flex min-w-0 items-center gap-1.5 text-xs text-muted-foreground">
              <span v-if="notification.projectName" class="truncate">
                {{ t("notifications.project_context", { project: notification.projectName }) }}
              </span>
              <span v-if="notification.projectName" aria-hidden="true">·</span>
              <time :datetime="notification.createdAt" class="shrink-0">
                {{ relativeTime(notification.createdAt) }}
              </time>
            </div>
          </div>

          <button
            v-if="notification.readAt === null"
            type="button"
            class="absolute right-3 top-3 flex size-7 items-center justify-center rounded-md text-muted-foreground opacity-70 transition-all hover:bg-background hover:text-foreground focus-visible:opacity-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring group-hover:opacity-100 disabled:cursor-wait"
            :aria-label="t('notifications.mark_read')"
            :title="t('notifications.mark_read')"
            :disabled="pending"
            @click="markRead(notification.id)"
          >
            <Check class="size-3.5" />
          </button>

          <span
            v-if="notification.readAt === null"
            aria-hidden="true"
            class="absolute right-1.5 top-1/2 size-1.5 -translate-y-1/2 rounded-full bg-primary"
          />
        </li>
      </ul>

      <div
        v-else-if="loaded"
        class="flex min-h-0 flex-1 flex-col items-center overflow-y-auto px-6 py-10 text-center"
      >
        <div
          class="mb-3 flex size-10 items-center justify-center rounded-full bg-muted text-muted-foreground"
        >
          <Bell class="size-5" />
        </div>
        <p class="text-sm font-medium">
          {{ t(`notifications.empty.${center.filter}.title`) }}
        </p>
        <p class="mt-1 max-w-64 text-xs leading-5 text-muted-foreground">
          {{ t(`notifications.empty.${center.filter}.description`) }}
        </p>
      </div>
    </PopoverContent>
  </Popover>
</template>
