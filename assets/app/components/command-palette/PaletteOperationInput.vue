<script setup lang="ts">
import { injectListboxRootContext, ListboxFilter } from "reka-ui";
import { computed, nextTick, ref, useId, watch } from "vue";
import { useI18n } from "vue-i18n";
import { useCommand } from "@components/ui/command";
import {
  firstMissingRequiredParameterId,
  nextOperationParameterId,
  operationParameter,
  operationReady,
  previousOperationParameterId,
  type OperationDefinition,
  type OperationErrors,
  type OperationParameterDefinition,
  type OperationValue,
  type OperationValues,
} from "@shared/command-palette/operationCatalog";

const {
  definition,
  values = {},
  activeParameter = null,
  query = "",
  errors = {},
  disabled = false,
} = defineProps<{
  definition: OperationDefinition;
  values?: OperationValues;
  activeParameter?: string | null;
  query?: string;
  errors?: OperationErrors;
  disabled?: boolean;
}>();

const emit = defineEmits<{
  activate: [parameterId: string];
  clear: [parameterId: string];
  cancel: [];
  submit: [];
  "update:query": [query: string];
}>();

const { t } = useI18n();
const { filterState } = useCommand();
const listboxRoot = injectListboxRootContext();
const instanceId = useId().replaceAll(":", "");
const composing = ref(false);
const rootElement = ref<HTMLElement | null>(null);

const activeDefinition = computed(() => operationParameter(definition, activeParameter));

const activeValue = computed(() => (activeParameter ? values[activeParameter] : undefined));

const renderedErrors = computed(() =>
  definition.parameters.flatMap((parameter) => {
    const message = errors[parameter.id];
    return message ? [{ parameter, message }] : [];
  }),
);

watch(
  () => query,
  (query) => {
    if (filterState.search !== query) filterState.search = query;
  },
  { immediate: true },
);

watch(
  () => activeParameter,
  () => {
    void focusActive();
  },
  { flush: "post" },
);

async function focusActive(): Promise<void> {
  if (disabled) return;
  await nextTick();
  const parameterId = activeParameter ?? definition.parameters[0]?.id;
  if (!parameterId) return;

  const slots = rootElement.value?.querySelectorAll<HTMLElement>("[data-palette-parameter]");
  for (const slot of slots ?? []) {
    if (slot.dataset.paletteParameter === parameterId) {
      slot.focus();
      return;
    }
  }
}

async function highlightFirstOption(): Promise<void> {
  await nextTick();
  if (listboxRoot.highlightedElement.value?.isConnected) return;
  listboxRoot.highlightFirstItem();
  await nextTick();
}

defineExpose({ focusActive, highlightFirstOption });

function parameterForPart(parameterId: string): OperationParameterDefinition | undefined {
  return operationParameter(definition, parameterId);
}

function parameterValue(parameterId: string): OperationValue | null | undefined {
  return values[parameterId];
}

function parameterLabel(parameter: OperationParameterDefinition): string {
  return t(parameter.labelKey);
}

function slotLabel(parameter: OperationParameterDefinition): string {
  const value = parameterValue(parameter.id);
  return value ? `${parameterLabel(parameter)}: ${value.label}` : parameterLabel(parameter);
}

function errorId(parameterId: string): string {
  const safeParameterId = parameterId.replaceAll(/[^a-zA-Z0-9_-]/g, "-");
  return `palette-operation-${instanceId}-${safeParameterId}-error`;
}

function updateQuery(query: string): void {
  filterState.search = query;
  emit("update:query", query);
}

function activate(parameterId: string): void {
  if (disabled) return;
  if (query) updateQuery("");
  emit("activate", parameterId);
}

function onQueryValue(query: string): void {
  if (disabled || composing.value) return;
  updateQuery(query);
}

function onCompositionEnd(event: CompositionEvent): void {
  composing.value = false;
  if (disabled) return;
  updateQuery((event.target as HTMLInputElement).value);
}

function imeOwns(event: KeyboardEvent): boolean {
  return composing.value || event.isComposing || event.keyCode === 229;
}

function keepActiveParameter(): void {
  const parameterId = activeParameter;
  if (!parameterId) return;
  emit("activate", parameterId);
  void focusActive();
}

function activateNextOrSubmit(parameterId: string): void {
  const nextParameterId = nextOperationParameterId(definition, parameterId);
  if (nextParameterId) {
    activate(nextParameterId);
    return;
  }

  const missingRequired = firstMissingRequiredParameterId(definition, values);
  if (missingRequired) {
    activate(missingRequired);
  } else if (operationReady(definition, values, errors)) {
    emit("submit");
  } else {
    keepActiveParameter();
  }
}

function onBackspace(event: KeyboardEvent): void {
  if (query) return;

  const parameterId = activeParameter;
  if (!parameterId) {
    event.preventDefault();
    event.stopPropagation();
    emit("cancel");
    return;
  }

  event.preventDefault();
  event.stopPropagation();

  if (activeValue.value) {
    emit("clear", parameterId);
    return;
  }

  const previousParameterId = previousOperationParameterId(definition, parameterId);
  if (previousParameterId) {
    activate(previousParameterId);
  } else {
    emit("cancel");
  }
}

function onEnter(event: KeyboardEvent): void {
  // A non-empty query belongs to the completion list. Let Reka select its
  // highlighted result instead of treating it as a template submission.
  if (query.trim()) return;

  event.preventDefault();
  event.stopPropagation();

  const parameter = activeDefinition.value;
  if (!parameter) {
    const missingRequired = firstMissingRequiredParameterId(definition, values);
    if (missingRequired) {
      activate(missingRequired);
    } else if (operationReady(definition, values, errors)) {
      emit("submit");
    }
    return;
  }

  if ((parameter.required && !activeValue.value) || errors[parameter.id]) {
    // Required-but-empty and invalid values are focus states, not errors
    // generated by the composer. The server/parent owns validation messages.
    keepActiveParameter();
    return;
  }

  activateNextOrSubmit(parameter.id);
}

function onTab(event: KeyboardEvent): void {
  const parameter = activeDefinition.value;
  if (!parameter) return;

  if (!event.shiftKey && parameter.required && !activeValue.value) {
    event.preventDefault();
    event.stopPropagation();
    keepActiveParameter();
    return;
  }

  const destination = event.shiftKey
    ? previousOperationParameterId(definition, parameter.id)
    : nextOperationParameterId(definition, parameter.id);

  if (!destination) return;

  event.preventDefault();
  event.stopPropagation();
  activate(destination);
}

function onHorizontalArrow(event: KeyboardEvent, direction: "previous" | "next"): void {
  // While the user is typing a completion query, horizontal arrows retain
  // their native caret semantics. Atomic slot navigation takes over once the
  // query is empty (including a slot whose selected value is a placeholder).
  if (query) return;

  const parameter = activeDefinition.value;
  if (!parameter) return;

  const destination =
    direction === "previous"
      ? previousOperationParameterId(definition, parameter.id)
      : nextOperationParameterId(definition, parameter.id);
  if (!destination) return;

  event.preventDefault();
  event.stopPropagation();
  activate(destination);
}

function onKeydown(event: KeyboardEvent): void {
  if (disabled || imeOwns(event)) return;

  switch (event.key) {
    case "ArrowLeft":
      onHorizontalArrow(event, "previous");
      break;
    case "ArrowRight":
      onHorizontalArrow(event, "next");
      break;
    case "Backspace":
      onBackspace(event);
      break;
    case "Escape":
      event.preventDefault();
      event.stopPropagation();
      emit("cancel");
      break;
    case "Enter":
      onEnter(event);
      break;
    case "Tab":
      onTab(event);
      break;
  }
}
</script>

<template>
  <div
    ref="rootElement"
    data-slot="palette-operation-input"
    role="group"
    :aria-label="t(definition.help.labelKey)"
    class="border-b px-3 py-2"
    @keydown.capture="onKeydown"
  >
    <div class="flex min-h-9 flex-wrap items-center gap-x-1.5 gap-y-2 text-sm">
      <template v-for="(part, index) in definition.phrase" :key="`${part.kind}-${index}`">
        <span
          v-if="part.kind === 'text'"
          class="select-none whitespace-nowrap text-muted-foreground"
        >
          {{ t(part.textKey) }}
        </span>

        <template v-else>
          <template v-if="parameterForPart(part.parameterId)">
            <ListboxFilter
              v-if="activeParameter === part.parameterId"
              :model-value="query"
              :data-palette-parameter="part.parameterId"
              :disabled="disabled"
              autocomplete="off"
              spellcheck="false"
              :required="parameterForPart(part.parameterId)!.required"
              :aria-required="parameterForPart(part.parameterId)!.required"
              :aria-label="slotLabel(parameterForPart(part.parameterId)!)"
              :aria-invalid="errors[part.parameterId] ? 'true' : undefined"
              :aria-describedby="errors[part.parameterId] ? errorId(part.parameterId) : undefined"
              :placeholder="
                parameterValue(part.parameterId)?.label ||
                parameterLabel(parameterForPart(part.parameterId)!)
              "
              class="h-7 min-w-24 rounded-md border border-primary/60 bg-background px-2 font-medium text-foreground outline-none ring-2 ring-primary/15 placeholder:text-muted-foreground focus:border-primary disabled:cursor-not-allowed disabled:opacity-50"
              :style="{
                width: `${Math.max(
                  (
                    query ||
                    parameterValue(part.parameterId)?.label ||
                    parameterLabel(parameterForPart(part.parameterId)!)
                  ).length + 3,
                  12,
                )}ch`,
              }"
              @update:model-value="onQueryValue"
              @compositionstart="composing = true"
              @compositionend="onCompositionEnd"
              @keydown.esc.stop
            />
            <button
              v-else
              type="button"
              :data-palette-parameter="part.parameterId"
              :disabled="disabled"
              tabindex="-1"
              :aria-label="slotLabel(parameterForPart(part.parameterId)!)"
              :aria-invalid="errors[part.parameterId] ? 'true' : undefined"
              :aria-describedby="errors[part.parameterId] ? errorId(part.parameterId) : undefined"
              class="min-h-7 rounded-md border border-dashed border-border bg-muted/40 px-2 font-medium text-foreground transition-colors hover:border-primary/50 hover:bg-accent focus-visible:border-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/30 disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50"
              @click="activate(part.parameterId)"
            >
              <span v-if="parameterValue(part.parameterId)">
                {{ parameterValue(part.parameterId)!.label }}
              </span>
              <span v-else class="font-normal text-muted-foreground">
                {{ parameterLabel(parameterForPart(part.parameterId)!) }}
              </span>
            </button>
          </template>
        </template>
      </template>
    </div>

    <div v-if="renderedErrors.length" class="mt-1.5 space-y-1">
      <p
        v-for="{ parameter, message } in renderedErrors"
        :id="errorId(parameter.id)"
        :key="parameter.id"
        role="alert"
        class="text-xs text-destructive"
      >
        {{ message }}
      </p>
    </div>
  </div>
</template>
