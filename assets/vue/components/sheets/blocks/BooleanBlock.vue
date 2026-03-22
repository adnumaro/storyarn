<script setup>
import { computed } from "vue"
import { ToggleLeft, Lock } from "lucide-vue-next"
import { Switch } from "@/vue/components/ui/switch"
import { Badge } from "@/vue/components/ui/badge"
import { Checkbox } from "@/vue/components/ui/checkbox"
import BlockToolbar from "../BlockToolbar.vue"
import { useBlockActions } from "./useBlockActions"

const props = defineProps({
  block: { type: Object, required: true },
  canEdit: { type: Boolean, default: false },
  inherited: { type: Boolean, default: false },
})

const { live, label, editingLabel, localLabel, labelInput, startEditLabel, saveLabel , isSelected, onBlockClick } = useBlockActions(props)

const content = computed(() => props.block.value?.content)
const mode = computed(() => props.block.config?.mode || "two_state")

const booleanLabel = computed(() => {
  const cfg = props.block.config || {}
  if (content.value === true) return cfg.true_label || "Yes"
  if (content.value === false) return cfg.false_label || "No"
  return cfg.neutral_label || "—"
})

const booleanChecked = computed({
  get: () => content.value === true,
  set: (val) => live.pushEvent("update_block_value", { id: props.block.id, value: val }),
})

function cycle() {
  let next
  if (content.value === true) next = false
  else if (content.value === false) next = null
  else next = true
  live.pushEvent("update_block_value", { id: props.block.id, value: next })
}
</script>

<template>
  <div
    class="group relative rounded-lg border p-4 pt-5 transition-colors"
    :class="isSelected ? 'border-primary ring-1 ring-primary/30' : 'border-border hover:border-foreground/20'"
    @click="onBlockClick"
  >
    <BlockToolbar v-if="canEdit"
      :is-constant="block.is_constant" :is-variable="!block.is_constant && !!block.variable_name"
      :variable-name="block.variable_name || ''" :show-scope="!inherited"
      :scope="block.scope || 'self'" :required="block.required"
      @toggle-constant="live.pushEvent('toggle_constant', { id: block.id })"
      @update-variable-name="(v) => live.pushEvent('update_variable_name', { id: block.id, variable_name: v })"
      @change-scope="(s) => live.pushEvent('change_block_scope', { id: block.id, scope: s })"
      @toggle-required="live.pushEvent('toggle_required', { id: block.id })"
    >
      <template #config>
        <div class="space-y-1">
          <label class="flex items-center gap-2 text-xs">
            <Checkbox :checked="mode === 'tri_state'"
              @update:model-value="(v) => live.pushEvent('update_block_config', { id: block.id, field: 'mode', value: v ? 'tri_state' : 'two_state' })" />
            Three states (true / false / neutral)
          </label>
        </div>
        <div class="grid grid-cols-2 gap-2">
          <div class="space-y-1"><label class="text-xs font-medium">True label</label>
            <input :value="block.config?.true_label || ''" placeholder="Yes" class="h-7 w-full text-xs rounded-md border border-input bg-background px-2"
              @blur="(e) => live.pushEvent('update_block_config', { id: block.id, field: 'true_label', value: e.target.value })" /></div>
          <div class="space-y-1"><label class="text-xs font-medium">False label</label>
            <input :value="block.config?.false_label || ''" placeholder="No" class="h-7 w-full text-xs rounded-md border border-input bg-background px-2"
              @blur="(e) => live.pushEvent('update_block_config', { id: block.id, field: 'false_label', value: e.target.value })" /></div>
        </div>
        <div v-if="mode === 'tri_state'" class="space-y-1"><label class="text-xs font-medium">Neutral label</label>
          <input :value="block.config?.neutral_label || ''" placeholder="Neutral" class="h-7 w-full text-xs rounded-md border border-input bg-background px-2"
            @blur="(e) => live.pushEvent('update_block_config', { id: block.id, field: 'neutral_label', value: e.target.value })" /></div>
      </template>
    </BlockToolbar>

    <div class="flex items-center justify-between mb-2">
      <div class="flex items-center gap-1.5 text-sm">
        <ToggleLeft class="size-3.5 text-muted-foreground" />
        <input v-if="canEdit && editingLabel" ref="labelInput" v-model="localLabel" class="font-medium bg-transparent outline-none border-none px-0 text-sm" @blur="saveLabel" @keydown.enter.prevent="saveLabel" />
        <span v-else class="font-medium" :class="canEdit && 'cursor-text'" @click="startEditLabel">{{ label }}</span>
        <Lock v-if="block.is_constant" class="size-3 text-muted-foreground/50" />
        <span v-if="block.required" class="text-[10px] text-destructive font-medium">required</span>
      </div>
      <slot name="menu" />
    </div>

    <!-- Two-state -->
    <div v-if="canEdit && mode === 'two_state'" class="flex items-center gap-3">
      <Switch v-model="booleanChecked" />
      <span class="text-sm text-muted-foreground">{{ booleanLabel }}</span>
    </div>

    <!-- Tri-state -->
    <div v-else-if="canEdit && mode === 'tri_state'" class="flex items-center gap-3">
      <button type="button" class="inline-flex items-center gap-2 px-3 py-1.5 rounded-md border border-border text-sm hover:bg-accent transition-colors" @click="cycle">
        <span class="size-2.5 rounded-full" :class="{ 'bg-green-500': content === true, 'bg-red-500': content === false, 'bg-muted-foreground/30': content == null }" />
        {{ booleanLabel }}
      </button>
    </div>

    <!-- Read-only -->
    <Badge v-else :variant="content === true ? 'default' : content === false ? 'destructive' : 'secondary'">
      {{ booleanLabel }}
    </Badge>
  </div>
</template>
