<script setup>
import { Bookmark, Play, RotateCcw } from "lucide-vue-next";
import { Button } from "@/vue/components/ui/button";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
} from "@/vue/components/ui/dialog";
import { useLive } from "@/vue/composables/useLive";

const props = defineProps({
	open: { type: Boolean, default: false },
	pendingSession: { type: Object, default: null },
});

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
          Saved Progress Found
        </DialogTitle>
        <DialogDescription>
          You have a saved exploration session.
        </DialogDescription>
      </DialogHeader>

      <div v-if="pendingSession" class="space-y-1 text-sm">
        <div v-if="pendingSession.sceneName">
          <span class="opacity-50">Scene:</span>
          <span class="font-medium ml-1">{{ pendingSession.sceneName }}</span>
        </div>
        <div class="text-xs opacity-40">
          Last played: {{ pendingSession.updatedAt }}
        </div>
      </div>

      <DialogFooter class="flex-row gap-2 sm:justify-start">
        <Button @click="continueSession">
          <Play class="size-4" />
          Continue
        </Button>
        <Button variant="outline" @click="newSession">
          <RotateCcw class="size-4" />
          New Game
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>
