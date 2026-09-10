import { afterEach, describe, expect, it } from "vitest";
import { CommentMagneticDrag } from "@components/comments/commentMagnetism";
import type { CommentContextReference } from "@components/comments/types";
import {
  sheetCommentPositionForSurface,
  sheetCommentSurfaceSize,
} from "@modules/sheets/lib/comment-geometry";
import {
  resolveSheetCommentPosition,
  sheetCommentSnapAdapter,
} from "@modules/sheets/lib/comment-snap-adapter";

interface Rectangle {
  left: number;
  top: number;
  width: number;
  height: number;
}

function measure(
  element: HTMLElement,
  rect: Rectangle,
  layout?: { width: number; height: number },
) {
  element.getBoundingClientRect = () =>
    ({
      ...rect,
      x: rect.left,
      y: rect.top,
      right: rect.left + rect.width,
      bottom: rect.top + rect.height,
      toJSON: () => rect,
    }) as DOMRect;
  Object.defineProperties(element, {
    offsetWidth: { configurable: true, get: () => layout?.width ?? rect.width },
    offsetHeight: { configurable: true, get: () => layout?.height ?? rect.height },
  });
  return rect;
}

function surface(rect = { left: 100, top: 100, width: 800, height: 1000 }) {
  const element = document.createElement("div");
  element.dataset.sheetCommentSurface = "true";
  element.dataset.sheetCommentOwner = "1";
  document.body.append(element);
  measure(element, rect);
  return element;
}

function target(
  parent: HTMLElement,
  type: string,
  id: string,
  rect: Rectangle,
  label = `${type} ${id}`,
) {
  const element = document.createElement("div");
  element.dataset.sheetCommentType = type;
  element.dataset.sheetCommentId = id;
  element.dataset.sheetCommentLabel = label;
  parent.append(element);
  measure(element, rect);
  return element;
}

afterEach(() => document.body.replaceChildren());

describe("Sheet comment magnetic adapter", () => {
  it("exposes semantic identities for regions, inherited blocks and grouped rows", () => {
    const container = surface();
    const rect = { left: 150, top: 150, width: 300, height: 60 };
    target(container, "sheet_cover", "1", rect, "Cover");
    target(container, "sheet_header", "1", rect, "Header");
    target(container, "sheet_title", "1", rect, "Title");
    target(container, "sheet_block", "42", rect, "Mood");
    const inherited = document.createElement("div");
    container.append(inherited);
    target(inherited, "sheet_block", "81", rect, "Inherited power");
    target(container, "sheet_column_group", "4d92b7f1-0713-4cae-bd33-c749722399aa", rect);

    expect(
      sheetCommentSnapAdapter(container)
        .candidates()
        ?.map(({ context }) => context),
    ).toEqual([
      { type: "sheet_cover", id: "1" },
      { type: "sheet_header", id: "1" },
      { type: "sheet_title", id: "1" },
      { type: "sheet_block", id: "42" },
      { type: "sheet_block", id: "81" },
      { type: "sheet_column_group", id: "4d92b7f1-0713-4cae-bd33-c749722399aa" },
    ]);
  });

  it("lets the shared engine choose a nested block or its containing row without changing owner", () => {
    const container = surface();
    const groupId = "4d92b7f1-0713-4cae-bd33-c749722399aa";
    const row = target(container, "sheet_column_group", groupId, {
      left: 140,
      top: 300,
      width: 720,
      height: 140,
    });
    target(row, "sheet_block", "42", { left: 140, top: 300, width: 220, height: 140 });
    target(row, "sheet_block", "43", { left: 390, top: 300, width: 220, height: 140 });
    const adapter = sheetCommentSnapAdapter(container);
    const drag = new CommentMagneticDrag(
      adapter,
      { position: { x: 20, y: 250 }, context: null },
      { x: 260, y: 350 },
    );

    expect(drag.update({ x: 260, y: 350 }).context).toEqual({
      type: "sheet_block",
      id: "42",
      offset: { x: 15, y: 50 },
    });
    expect(drag.preview.candidates).toHaveLength(2);
    expect(drag.cycle(1).context).toEqual({
      type: "sheet_column_group",
      id: groupId,
      offset: { x: 15, y: 50 },
    });
    expect(drag.cycle(1).context?.id).toBe("42");
    expect(container.dataset.sheetCommentOwner).toBe("1");
  });

  it("converts CSS positions through scale and scroll while keeping the pin 16 CSS pixels inside", () => {
    const container = surface();
    const rect = measure(
      container,
      { left: 100, top: -100, width: 800, height: 2000 },
      { width: 400, height: 1000 },
    );
    const adapter = sheetCommentSnapAdapter(container);

    expect(sheetCommentSurfaceSize(container)).toEqual({ width: 400, height: 1000 });
    expect(adapter.fromScreen({ x: 300, y: 300 })).toEqual({ x: 25, y: 200 });
    expect(adapter.toScreen({ x: 25, y: 200 })).toEqual({ x: 300, y: 300 });
    expect(adapter.clamp({ x: -100, y: -20 })).toEqual({ x: 4, y: 16 });
    expect(adapter.clamp({ x: 200, y: 1500 })).toEqual({ x: 96, y: 984 });
    expect(sheetCommentPositionForSurface({ x: 25, y: 200 }, container)).toEqual({
      x: 100,
      y: 200,
    });
    rect.top = -300;
    expect(adapter.toScreen({ x: 25, y: 200 })).toEqual({ x: 300, y: 100 });
    expect(adapter.fromScreen({ x: 300, y: 100 })).toEqual({ x: 25, y: 200 });
  });

  it("measures snap thresholds in visible pixels even when the sheet is scaled", () => {
    const container = surface();
    measure(
      container,
      { left: 100, top: 100, width: 800, height: 1000 },
      { width: 400, height: 500 },
    );
    target(container, "sheet_block", "42", { left: 300, top: 300, width: 200, height: 100 });
    const adapter = sheetCommentSnapAdapter(container);
    const drag = new CommentMagneticDrag(
      adapter,
      { position: { x: 10, y: 125 }, context: null },
      { x: 180, y: 350 },
    );
    expect(drag.update({ x: 281, y: 350 }).context).toBeNull();
    expect(drag.update({ x: 282, y: 350 }).position).toEqual({ x: 25, y: 125 });
    expect(drag.preview.context?.offset).toEqual({ x: 0, y: 25 });
    expect(drag.update({ x: 273, y: 350 }).context?.id).toBe("42");
    expect(drag.update({ x: 271, y: 350 }).context).toBeNull();
  });

  it("preserves contextual offsets across resize, reordering and scroll with fresh DOM geometry", () => {
    const container = surface();
    const block = target(container, "sheet_block", "42", {
      left: 300,
      top: 500,
      width: 300,
      height: 100,
    });
    const adapter = sheetCommentSnapAdapter(container);
    const candidate = adapter.candidates()![0];
    const saved = { x: 30, y: 420 };
    const context = adapter.context(candidate, saved);
    expect(context.offset).toEqual({ x: 5, y: 20 });

    measure(container, { left: 100, top: 100, width: 400, height: 1400 });
    measure(block, { left: 140, top: 700, width: 320, height: 180 });
    expect(resolveSheetCommentPosition(saved, context, container)).toEqual({ x: 15, y: 620 });

    measure(container, { left: 100, top: -400, width: 400, height: 1400 });
    measure(block, { left: 140, top: 200, width: 320, height: 180 });
    expect(resolveSheetCommentPosition(saved, context, container)).toEqual({ x: 15, y: 620 });
  });

  it("follows rendered targets outside the viewport without acquiring invisible snap candidates", () => {
    const container = surface();
    target(container, "sheet_block", "42", { left: 300, top: 900, width: 300, height: 100 });
    const context = { type: "sheet_block", id: "42", offset: { x: 5, y: 20 } };

    expect(sheetCommentSnapAdapter(container).candidates()).toEqual([]);
    expect(resolveSheetCommentPosition({ x: 30, y: 420 }, context, container)).toEqual({
      x: 30,
      y: 820,
    });
  });

  it.each(["display", "visibility", "opacity", "hidden", "aria-hidden"])(
    "ignores targets hidden by an ancestor's %s without discarding their saved fallback",
    (hiddenBy) => {
      const container = surface();
      const parent = document.createElement("div");
      container.append(parent);
      const block = target(parent, "sheet_block", "42", {
        left: 300,
        top: 300,
        width: 300,
        height: 100,
      });
      if (hiddenBy === "display") parent.style.display = "none";
      else if (hiddenBy === "visibility") parent.style.visibility = "hidden";
      else if (hiddenBy === "opacity") parent.style.opacity = "0";
      else parent.setAttribute(hiddenBy, "true");
      const context = { type: "sheet_block", id: "42", offset: { x: 5, y: 20 } };
      expect(sheetCommentSnapAdapter(container).candidates()).toEqual([]);
      expect(resolveSheetCommentPosition({ x: 60, y: 600 }, context, container)).toEqual({
        x: 60,
        y: 600,
      });
      expect(block.dataset.sheetCommentId).toBe("42");
    },
  );

  it("uses saved positions for missing or unavailable contexts and resumes after restoration", () => {
    const container = surface();
    const block = target(container, "sheet_block", "42", {
      left: 300,
      top: 300,
      width: 300,
      height: 100,
    });
    const context = { type: "sheet_block", id: "42", offset: { x: 5, y: 20 } };
    const saved = { x: 60, y: 600 };
    expect(
      resolveSheetCommentPosition(saved, { ...context, status: "unavailable" }, container),
    ).toEqual(saved);
    block.remove();
    expect(resolveSheetCommentPosition(saved, context, container)).toEqual(saved);
    container.append(block);
    expect(resolveSheetCommentPosition(saved, context, container)).toEqual({ x: 30, y: 220 });
    expect(context.offset).toEqual({ x: 5, y: 20 });
  });

  it("clips candidates to scroll viewports but retains the unclipped target origin for offsets", () => {
    const container = surface();
    const viewport = document.createElement("div");
    viewport.style.overflowX = "auto";
    viewport.style.overflowY = "auto";
    measure(viewport, { left: 200, top: 200, width: 400, height: 200 });
    container.before(viewport);
    viewport.append(container);
    target(container, "sheet_block", "42", { left: 150, top: 150, width: 600, height: 400 });
    const adapter = sheetCommentSnapAdapter(container);
    const candidate = adapter.candidates()![0];
    expect(candidate.geometry).toEqual({
      kind: "rect",
      left: 200,
      top: 200,
      width: 400,
      height: 200,
    });
    expect(adapter.context(candidate, adapter.fromScreen({ x: 200, y: 200 })).offset).toEqual({
      x: 6.25,
      y: 50,
    });
  });

  it("excludes unsupported identities, collapsed elements and nested sheet surfaces", () => {
    const container = surface();
    const rect = { left: 150, top: 150, width: 300, height: 60 };
    target(container, "flow_node", "42", rect);
    target(container, "sheet_block", "", rect);
    target(container, "sheet_block", "43", { ...rect, height: 0 });
    const nested = document.createElement("div");
    nested.dataset.sheetCommentSurface = "true";
    container.append(nested);
    target(nested, "sheet_title", "2", rect);
    expect(sheetCommentSnapAdapter(container).candidates()).toEqual([]);
  });

  it("keeps invalid or absent offsets at their surface-constrained fallback", () => {
    const container = surface();
    const saved = { x: 101, y: 2000 };
    const contexts: Array<CommentContextReference | null> = [
      null,
      { type: "sheet_block", id: "42" },
      { type: "sheet_block", id: "42", offset: { x: Number.NaN, y: 0 } },
    ];
    for (const context of contexts) {
      expect(resolveSheetCommentPosition(saved, context, container)).toEqual({ x: 98, y: 984 });
    }
  });
});
