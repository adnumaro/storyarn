<script setup lang="ts">
import { ArrowLeft, ArrowRight, Info, X } from "lucide-vue-next";
import { watch } from "vue";
import { Button } from "@components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import { useLive } from "@composables/useLive";

interface CurrentNode {
  id: number;
  text: string;
  speaker: string | null;
  speakerInitials: string;
}

interface Response {
  id: string;
  text: string;
  hasCondition: boolean;
  conditionLabel: string | null;
}

const {
  open = false,
  currentNode = null,
  responses = [],
  hasNext = false,
  hasHistory = false,
} = defineProps<{
  open?: boolean;
  currentNode?: CurrentNode | null;
  responses?: Response[];
  hasNext?: boolean;
  hasHistory?: boolean;
}>();

const live = useLive();

function onOpenChange(value: boolean): void {
  if (!value) {
    live.pushEvent("preview_close", {});
  }
}

function selectResponse(responseId: string): void {
  live.pushEvent("preview_select_response", { response_id: responseId });
}

function continueFlow(): void {
  live.pushEvent("preview_continue", {});
}

function goBack(): void {
  live.pushEvent("preview_go_back", {});
}

function closePreview(): void {
  live.pushEvent("preview_close", {});
}
</script>

<template>
  <Dialog :open="open" @update:open="onOpenChange">
    <DialogContent class="sm:max-w-md">
      <!-- Node content -->
      <template v-if="currentNode">
        <!-- Speaker header -->
        <DialogHeader>
          <div class="flex items-center gap-3">
            <div
              class="flex items-center justify-center size-10 rounded-full bg-primary text-primary-foreground text-sm font-semibold shrink-0"
            >
              {{ currentNode.speakerInitials }}
            </div>
            <div>
              <DialogTitle class="text-base">
                {{ currentNode.speaker || "Narrator" }}
              </DialogTitle>
              <p class="text-xs text-muted-foreground">
                Node {{ currentNode.id }}
              </p>
            </div>
          </div>
        </DialogHeader>

        <!-- Dialogue text -->
        <div
          class="prose prose-sm max-w-none bg-muted rounded-lg p-4 dark:prose-invert"
          v-html="currentNode.text"
        />

        <!-- Response buttons -->
        <div v-if="responses.length > 0" class="space-y-2">
          <p class="text-sm font-medium text-muted-foreground">Responses:</p>
          <div class="flex flex-col gap-2">
            <Button
              v-for="response in responses"
              :key="response.id"
              variant="outline"
              size="sm"
              class="justify-start text-left h-auto py-2 whitespace-normal"
              @click="selectResponse(response.id)"
            >
              <span class="flex-1" v-html="response.text" />
              <span
                v-if="response.hasCondition"
                class="text-xs px-1.5 py-0.5 rounded bg-amber-500/20 text-amber-700 dark:text-amber-400 ml-2 shrink-0"
                :title="response.conditionLabel || ''"
              >
                ?
              </span>
            </Button>
          </div>
        </div>

        <!-- Continue button -->
        <div v-if="responses.length === 0 && hasNext" class="pt-2">
          <Button class="w-full gap-1" @click="continueFlow">
            Continue
            <ArrowRight class="size-4" />
          </Button>
        </div>

        <!-- End of branch -->
        <div v-if="responses.length === 0 && !hasNext" class="pt-2">
          <div
            class="flex items-center gap-2 rounded-lg border border-blue-500/30 bg-blue-500/10 p-4 text-blue-700 dark:text-blue-300 text-sm"
          >
            <Info class="size-5 shrink-0" />
            <span>End of dialogue branch</span>
          </div>
        </div>

        <!-- Navigation -->
        <div class="flex justify-between pt-4 border-t border-border">
          <Button v-if="hasHistory" variant="ghost" size="sm" class="gap-1" @click="goBack">
            <ArrowLeft class="size-4" />
            Back
          </Button>
          <div v-else />
          <Button variant="ghost" size="sm" @click="closePreview">
            Close
          </Button>
        </div>
      </template>

      <!-- Empty state -->
      <div v-else class="text-center py-8">
        <p class="text-muted-foreground">No node selected for preview.</p>
      </div>
    </DialogContent>
  </Dialog>
</template>
