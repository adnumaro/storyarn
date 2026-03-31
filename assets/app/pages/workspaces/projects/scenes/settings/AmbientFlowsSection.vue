<script setup>
import { Plus, Wind } from "lucide-vue-next";
import { computed, ref } from "vue";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@components/ui/command";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import { useLive } from "@composables/useLive";
import AmbientFlowRow from "./AmbientFlowRow.vue";

const props = defineProps({
  ambientFlows: { type: Array, default: () => [] },
  projectFlows: { type: Array, default: () => [] },
  canEdit: { type: Boolean, default: false },
});

const live = useLive();
const addOpen = ref(false);

const availableFlows = computed(() => {
  const linkedIds = new Set(props.ambientFlows.map((af) => af.flowId));
  return props.projectFlows.filter((f) => !linkedIds.has(f.id));
});

function selectFlow(flowId) {
  live.pushEvent("select_add_ambient_flow", { id: flowId });
  addOpen.value = false;
}
</script>

<template>
  <div class="pt-2 border-t border-border space-y-2">
    <label class="text-xs font-medium text-foreground inline-flex items-center gap-1">
      <Wind class="size-3" />
      Ambient Flows
    </label>

    <div v-if="ambientFlows.length === 0" class="text-xs text-muted-foreground/60">
      No ambient flows linked to this scene.
    </div>

    <AmbientFlowRow v-for="af in ambientFlows" :key="af.id" :flow="af" :can-edit="canEdit" />

    <!-- Add flow -->
    <div v-if="canEdit && availableFlows.length > 0">
      <Popover v-model:open="addOpen">
        <PopoverTrigger as-child>
          <button
            type="button"
            class="inline-flex items-center gap-1 h-7 px-2 text-xs rounded-md hover:bg-accent transition-colors"
          >
            <Plus class="size-3 text-primary" />
            <span class="text-primary">Add ambient flow...</span>
          </button>
        </PopoverTrigger>
        <PopoverContent class="w-56 p-0" align="start">
          <Command>
            <CommandInput placeholder="Search flows..." class="h-8 text-xs" />
            <CommandList class="max-h-48">
              <CommandEmpty class="text-xs py-3">No flows found.</CommandEmpty>
              <CommandGroup>
                <CommandItem
                  v-for="flow in availableFlows"
                  :key="flow.id"
                  :value="flow.name"
                  class="text-xs"
                  @select="selectFlow(flow.id)"
                >
                  {{ flow.name }}
                </CommandItem>
              </CommandGroup>
            </CommandList>
          </Command>
        </PopoverContent>
      </Popover>
    </div>
  </div>
</template>
