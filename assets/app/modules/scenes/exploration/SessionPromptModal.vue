<script setup lang="ts">
import { Bookmark, Play, RotateCcw } from "lucide-vue-next";
import { Button } from "@components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import { useLive } from "@composables/useLive";

interface PendingSession {
  sceneName?: string;
  updatedAt?: string;
}

const { open = false, pendingSession = null } = defineProps<{
  open?: boolean;
  pendingSession?: PendingSession | null;
}>();

const live = useLive();

function continueSession() {
  live.pushEvent("continue_session", {});
}

function newSession() {
  live.pushEvent("new_session", {});
}
</script>

<template>
  <Dialog :open="open">
    <DialogContent :show-close-button="false" @interact-outside.prevent @escape-key-down.prevent>
      <DialogHeader>
        <DialogTitle class="flex items-center gap-2">
          <Bookmark class="size-5 opacity-60" />
          {{ $t("scenes.exploration.saved_progress_title") }}
        </DialogTitle>
        <DialogDescription> {{ $t("scenes.exploration.saved_progress_desc") }} </DialogDescription>
      </DialogHeader>

      <div v-if="pendingSession" class="space-y-1 text-sm">
        <div v-if="pendingSession.sceneName">
          <span class="opacity-50">{{ $t("scenes.exploration.scene_label") }}</span>
          <span class="font-medium ml-1">{{ pendingSession.sceneName }}</span>
        </div>
        <div class="text-xs opacity-40">{{ $t("scenes.exploration.last_played") }} {{ pendingSession.updatedAt }}</div>
      </div>

      <DialogFooter class="flex-row gap-2 sm:justify-start">
        <Button @click="continueSession">
          <Play class="size-4" />
          {{ $t("scenes.exploration.continue") }}
        </Button>
        <Button variant="outline" @click="newSession">
          <RotateCcw class="size-4" />
          {{ $t("scenes.exploration.new_game") }}
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>
