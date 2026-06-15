import { describe, it, expect } from "vitest";
import { mount } from "@vue/test-utils";
import ImagePosition from "../../../components/forms/assets/ImagePosition.vue";

const POSITIONS = [
  "top-left",
  "top-center",
  "top-right",
  "middle-left",
  "middle-center",
  "middle-right",
  "bottom-left",
  "bottom-center",
  "bottom-right",
];

function mountIt(props: Record<string, unknown> = {}) {
  return mount(ImagePosition, { props });
}

function findGroup(wrapper: ReturnType<typeof mountIt>, modelValue: string) {
  return wrapper
    .findAllComponents({ name: "ToggleGroup" })
    .find((g) => g.props("modelValue") === modelValue);
}

describe("ImagePosition", () => {
  it("emits position-change with the new value", async () => {
    const w = mountIt({ position: "middle-center", fit: "cover" });
    const positionGroup = findGroup(w, "middle-center")!;

    positionGroup.vm.$emit("update:modelValue", "top-left");

    expect(w.emitted("position-change")).toBeDefined();
    expect(w.emitted("position-change")![0]).toEqual(["top-left"]);
  });

  it("emits fit-change with the new fit value", async () => {
    const w = mountIt({ position: "middle-center", fit: "cover" });
    const fitGroup = findGroup(w, "cover")!;

    fitGroup.vm.$emit("update:modelValue", "contain");

    expect(w.emitted("fit-change")).toBeDefined();
    expect(w.emitted("fit-change")![0]).toEqual(["contain"]);
  });

  it("ignores empty deselection from ToggleGroup type=single", () => {
    const w = mountIt({ position: "middle-center", fit: "cover" });
    const positionGroup = findGroup(w, "middle-center")!;
    const fitGroup = findGroup(w, "cover")!;

    positionGroup.vm.$emit("update:modelValue", "");
    fitGroup.vm.$emit("update:modelValue", "");

    expect(w.emitted("position-change")).toBeUndefined();
    expect(w.emitted("fit-change")).toBeUndefined();
  });

  it("unwraps array model-value (multi-mode payload shape)", () => {
    const w = mountIt({ position: "middle-center", fit: "cover" });
    const positionGroup = findGroup(w, "middle-center")!;

    positionGroup.vm.$emit("update:modelValue", ["bottom-right"]);

    expect(w.emitted("position-change")![0]).toEqual(["bottom-right"]);
  });

  it("renders one ToggleGroupItem per position value and per fit value", () => {
    const w = mountIt({ position: "middle-center", fit: "cover" });
    // reka-ui's ToggleGroupItem wraps via as-child + Primitive, so each
    // logical item registers as multiple Vue component instances. Dedupe by
    // the `value` prop to count distinct items.
    const items = w.findAllComponents({ name: "ToggleGroupItem" });
    const distinctValues = new Set(items.map((i) => String(i.props("value"))));

    for (const pos of POSITIONS) {
      expect(distinctValues.has(pos)).toBe(true);
    }
    for (const fit of ["cover", "contain", "fill"]) {
      expect(distinctValues.has(fit)).toBe(true);
    }
    expect(distinctValues.size).toBe(POSITIONS.length + 3);
  });

  it("disables both groups when canEdit is false", () => {
    const w = mountIt({ position: "middle-center", fit: "cover", canEdit: false });
    const groups = w.findAllComponents({ name: "ToggleGroup" });
    expect(groups.every((g) => g.props("disabled") === true)).toBe(true);
  });

  it("normalizes legacy center position props to middle-center", () => {
    const w = mountIt({ position: "center", fit: "cover" });

    expect(findGroup(w, "middle-center")).toBeDefined();
  });
});
