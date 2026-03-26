<script setup>
import { computed } from "vue";
import { Ref } from "rete-vue-plugin";

const props = defineProps({
	data: { type: Object, required: true },
	emit: { type: Function, required: true },
});

const inputs = computed(() => Object.entries(props.data?.inputs || {}));
const outputs = computed(() => Object.entries(props.data?.outputs || {}));
const isSimple = computed(() => inputs.value.length <= 1 && outputs.value.length <= 1);
</script>

<template>
  <div class="py-1">
    <!-- Simple: 1 input + 1 output on same row -->
    <template v-if="isSimple">
      <div class="sockets-row flex justify-between items-center py-1">
        <template v-for="[key, input] in inputs" :key="'i-' + key">
          <Ref
            class="input-socket"
            :data="{ type: 'socket', side: 'input', key, nodeId: data.id, payload: input.socket }"
            :emit="emit"
            data-testid="input-socket"
          />
          <span class="text-[11px] text-muted-foreground ml-1">{{ key }}</span>
        </template>
        <template v-if="inputs.length > 0 && outputs.length > 0">
          <span class="flex-1" />
        </template>
        <template v-for="[key, output] in outputs" :key="'o-' + key">
          <span v-if="inputs.length === 0" class="flex-1" />
          <span class="text-[11px] text-muted-foreground mr-1">{{ key }}</span>
          <Ref
            class="output-socket"
            :data="{ type: 'socket', side: 'output', key, nodeId: data.id, payload: output.socket }"
            :emit="emit"
            data-testid="output-socket"
          />
        </template>
      </div>
    </template>

    <!-- Multi-row -->
    <template v-else>
      <div v-for="[key, input] in inputs" :key="'i-' + key" class="flex items-center py-0.5 text-[11px] text-muted-foreground justify-start">
        <Ref
          class="input-socket"
          :data="{ type: 'socket', side: 'input', key, nodeId: data.id, payload: input.socket }"
          :emit="emit"
          data-testid="input-socket"
        />
        <span class="ml-2">{{ input.label || key }}</span>
      </div>
      <div v-for="[key, output] in outputs" :key="'o-' + key" class="flex items-center py-0.5 text-[11px] text-muted-foreground justify-end">
        <span class="mr-2">{{ output.label || key }}</span>
        <Ref
          class="output-socket"
          :data="{ type: 'socket', side: 'output', key, nodeId: data.id, payload: output.socket }"
          :emit="emit"
          data-testid="output-socket"
        />
      </div>
    </template>
  </div>
</template>
