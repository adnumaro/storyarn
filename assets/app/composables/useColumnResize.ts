import { ref } from "vue";

interface ColumnDef {
  id: string;
  default: number;
  min?: number;
}

/**
 * Manages pixel widths for a set of resizable table columns. Use with a
 * `table-fixed` layout + `<colgroup>`; each `<col>` binds
 * `:style="{ width: widths[id] + 'px' }"`.
 *
 * ```ts
 * const { widths, startResize } = useColumnResize([
 *   { id: "variable", default: 200 },
 *   { id: "type", default: 80 },
 * ]);
 * ```
 *
 * ```html
 * <colgroup>
 *   <col :style="{ width: widths.variable + 'px' }" />
 *   <col :style="{ width: widths.type + 'px' }" />
 * </colgroup>
 * <th>
 *   Variable
 *   <span class="resize-handle" @pointerdown="startResize('variable', $event)" />
 * </th>
 * ```
 */
export function useColumnResize(defs: ColumnDef[]) {
  const widths = ref<Record<string, number>>(
    Object.fromEntries(defs.map((d) => [d.id, d.default])),
  );

  function startResize(id: string, event: PointerEvent) {
    event.preventDefault();
    event.stopPropagation();
    const startX = event.clientX;
    const startWidth = widths.value[id] ?? 0;
    const minWidth = defs.find((d) => d.id === id)?.min ?? 40;

    function onMove(ev: PointerEvent) {
      widths.value = {
        ...widths.value,
        [id]: Math.max(minWidth, startWidth + (ev.clientX - startX)),
      };
    }

    function onUp() {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      window.removeEventListener("pointercancel", onUp);
      document.body.style.userSelect = "";
      document.body.style.cursor = "";
    }

    document.body.style.userSelect = "none";
    document.body.style.cursor = "col-resize";
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointercancel", onUp);
  }

  return { widths, startResize };
}
