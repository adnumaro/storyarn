<script setup lang="ts">
import { computed } from "vue";
import { CornerUpLeft } from "@lucide/vue";
import { useI18n } from "vue-i18n";
import UserAvatar from "@components/UserAvatar.vue";
import { formatCommentDateTime, formatCommentTime } from "./commentTime";
import type { CommentMessage, CommentUiConfig } from "./types";

interface Segment {
  text: string;
  mention: boolean;
}

/**
 * One message of a thread. The root reads at full width; replies indent once.
 * Mentions typed as `@Name` highlight inline; members mentioned without a
 * matching name in the text still appear as trailing chips.
 */
const {
  message,
  ui,
  root = false,
  mine = false,
  highlighted = false,
  canReply = false,
} = defineProps<{
  message: CommentMessage;
  ui: CommentUiConfig;
  root?: boolean;
  mine?: boolean;
  highlighted?: boolean;
  canReply?: boolean;
}>();
const emit = defineEmits<{ reply: [message: CommentMessage] }>();
const { locale } = useI18n();
const key = (name: string) => `${ui.i18nPrefix}.${name}`;
const time = computed(() => formatCommentTime(message.inserted_at, locale.value));
const fullTime = computed(() => formatCommentDateTime(message.inserted_at, locale.value));
const mentionNames = computed(() =>
  message.mentions.map((member) => member.display_name).filter((name) => name.length > 0),
);

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

const segments = computed<Segment[]>(() => {
  const names = mentionNames.value;
  if (!names.length) return [{ text: message.body, mention: false }];
  const pattern = new RegExp(`(@(?:${names.map(escapeRegExp).join("|")}))`);
  return message.body
    .split(pattern)
    .filter((part) => part.length > 0)
    .map((part) => ({
      text: part,
      mention: part.startsWith("@") && names.includes(part.slice(1)),
    }));
});

const trailingMentions = computed(() =>
  message.mentions.filter((member) => !message.body.includes(`@${member.display_name}`)),
);
</script>

<template>
  <div
    :id="`${ui.domScope}-comment-message-${message.id}`"
    class="group flex gap-2.5 rounded-md px-3.5 py-1.5"
    :class="[root ? '' : 'pl-[52px]', highlighted ? 'bg-accent/50' : '']"
  >
    <UserAvatar
      :display-name="message.author.display_name"
      :size="root ? 'sm' : 'xs'"
      class="mt-0.5 shrink-0"
    />
    <div class="min-w-0 flex-1">
      <div class="flex items-baseline gap-1.5 text-xs leading-5">
        <span
          class="truncate font-semibold"
          :class="{ 'italic text-muted-foreground': message.author.id == null }"
          >{{ message.author.display_name }}</span
        >
        <time
          :datetime="message.inserted_at"
          :title="fullTime"
          class="shrink-0 text-muted-foreground"
          ><template v-if="mine">{{ $t(key("you")) }} · </template>{{ time }}</time
        >
        <span class="flex-1" />
        <button
          v-if="canReply"
          type="button"
          class="inline-flex shrink-0 items-center gap-1 text-[11px] text-muted-foreground opacity-0 transition-opacity group-focus-within:opacity-100 group-hover:opacity-100 focus-visible:opacity-100"
          :class="{ 'opacity-100': highlighted }"
          :aria-label="$t(key('reply_to'), { name: message.author.display_name })"
          @click="emit('reply', message)"
        >
          <CornerUpLeft class="size-3" />{{ $t(key("reply")) }}
        </button>
      </div>
      <p
        class="whitespace-pre-wrap break-words leading-relaxed"
        :class="root ? 'text-sm' : 'text-[13px]'"
      >
        <template v-for="(segment, index) in segments" :key="index">
          <span
            v-if="segment.mention"
            class="rounded bg-primary/10 px-1 font-medium text-primary"
            >{{ segment.text }}</span
          >
          <template v-else>{{ segment.text }}</template>
        </template>
      </p>
      <div v-if="trailingMentions.length" class="mt-1 flex flex-wrap gap-1">
        <span
          v-for="(member, index) in trailingMentions"
          :key="member.id ?? `deleted-${index}`"
          class="rounded bg-primary/10 px-1 text-[11px] font-medium text-primary"
          >@{{ member.display_name }}</span
        >
      </div>
    </div>
  </div>
</template>
