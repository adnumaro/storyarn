import { nextTick, onBeforeUnmount, type ComputedRef, watch } from "vue";

export interface SheetHighlightLocation {
  blockId: number | string;
  rowId?: number | string | null;
  columnId?: number | string | null;
}

export type SheetDeepLinkTarget =
  | {
      kind: "block";
      blockId: number | string;
      requestId: number;
    }
  | {
      kind: "cell";
      blockId: number | string;
      rowId: number | string;
      columnId: number | string;
      requestId: number;
    };

const highlightClasses = [
  "ring-2",
  "ring-primary",
  "ring-offset-2",
  "ring-offset-background",
] as const;

function matchingDescendant(
  root: HTMLElement,
  attribute: "sheetRowId" | "sheetColumnId",
  value: number | string,
): HTMLElement | null {
  const selector = attribute === "sheetRowId" ? "[data-sheet-row-id]" : "[data-sheet-column-id]";

  return (
    Array.from(root.querySelectorAll<HTMLElement>(selector)).find(
      (element) => element.dataset[attribute] === String(value),
    ) ?? null
  );
}

export function findSheetHighlightElement(location: SheetHighlightLocation): HTMLElement | null {
  const block = document.getElementById(`sheet-block-${location.blockId}`);
  if (!block) return null;

  if (location.rowId == null) return block;

  const row = matchingDescendant(block, "sheetRowId", location.rowId);
  if (!row) return block;
  if (location.columnId == null) return row;

  return matchingDescendant(row, "sheetColumnId", location.columnId) ?? row;
}

export function highlightSheetLocation(location: SheetHighlightLocation): (() => void) | null {
  const target = findSheetHighlightElement(location);
  if (!target) return null;

  target.scrollIntoView({ behavior: "smooth", block: "center" });
  target.classList.add(...highlightClasses);

  const timeout = window.setTimeout(() => {
    target.classList.remove(...highlightClasses);
  }, 1600);

  return () => {
    window.clearTimeout(timeout);
    target.classList.remove(...highlightClasses);
  };
}

export function useSheetHighlight(
  target: ComputedRef<SheetDeepLinkTarget | null>,
  contentReady: ComputedRef<boolean>,
): void {
  let run = 0;
  let clearActiveHighlight: (() => void) | null = null;

  watch(
    [() => target.value?.requestId ?? null, () => contentReady.value],
    async () => {
      const currentRun = ++run;
      clearActiveHighlight?.();
      clearActiveHighlight = null;

      const currentTarget = target.value;
      if (!currentTarget || !contentReady.value) return;

      // The sheet surface and its nested table rows render in the same update,
      // but the target must be resolved only after that DOM patch is complete.
      await nextTick();
      await nextTick();

      if (currentRun !== run || target.value?.requestId !== currentTarget.requestId) return;
      clearActiveHighlight = highlightSheetLocation(currentTarget);
    },
    { immediate: true, flush: "post" },
  );

  onBeforeUnmount(() => {
    run += 1;
    clearActiveHighlight?.();
  });
}
