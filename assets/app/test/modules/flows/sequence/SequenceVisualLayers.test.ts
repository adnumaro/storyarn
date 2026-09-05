import { mount } from "@vue/test-utils";
import SequenceVisualLayers from "@modules/flows/sequence/components/SequenceVisualLayers.vue";
import type { SequenceVisualLayer } from "@modules/flows/sequence/types";

const layers: SequenceVisualLayer[] = [
  {
    id: "character",
    sequenceId: 11,
    sequenceDepth: 1,
    kind: "character",
    label: "Aria",
    url: "/aria.png",
    zIndex: 20,
    x: 0.75,
    y: 1,
    width: 0.38,
    height: 0.9,
    anchorX: 0.5,
    anchorY: 1,
    fit: "contain",
    origin: { nodeId: 42, sequenceId: 11, inherited: true },
  },
  {
    id: "backdrop",
    sequence_id: 10,
    sequence_depth: 0,
    kind: "backdrop",
    label: "Hall",
    url: "/hall.png",
    z_index: 0,
    x: 0,
    y: 0,
    width: 1,
    height: 1,
    anchor_x: 0,
    anchor_y: 0,
    fit: "cover",
  },
  {
    id: "hidden",
    kind: "prop",
    url: "/hidden.png",
    visible: false,
  },
  {
    id: "missing-asset",
    kind: "overlay",
    url: "",
  },
];

describe("SequenceVisualLayers", () => {
  it("renders the resolved stack in depth and z-index order", () => {
    const wrapper = mount(SequenceVisualLayers, { props: { layers } });
    const rendered = wrapper.findAll(".sequence-visual-layer");

    expect(rendered).toHaveLength(2);
    expect(rendered[0]!.attributes("data-layer-id")).toBe("backdrop");
    expect(rendered[0]!.attributes("data-sequence-depth")).toBe("0");
    expect(rendered[0]!.attributes("style")).toContain("width: 100%");
    expect(rendered[1]!.attributes("data-layer-id")).toBe("character");
    expect(rendered[1]!.attributes("data-sequence-depth")).toBe("1");
    expect(rendered[1]!.attributes("style")).toContain("left: 75%");
    expect(rendered[0]!.attributes("style")).toContain("z-index: 0");
    expect(rendered[1]!.attributes("style")).toContain("z-index: 1");
  });

  it("keeps depth precedence across the full supported local z-index range", () => {
    const wrapper = mount(SequenceVisualLayers, {
      props: {
        layers: [
          {
            id: "child-low-z",
            sequenceDepth: 1,
            kind: "character",
            url: "/child.png",
            zIndex: -1000,
          },
          {
            id: "root-high-z",
            sequenceDepth: 0,
            kind: "backdrop",
            url: "/root.png",
            zIndex: 1000,
          },
        ],
      },
    });
    const rendered = wrapper.findAll(".sequence-visual-layer");

    expect(rendered.map((layer) => layer.attributes("data-layer-id"))).toEqual([
      "root-high-z",
      "child-low-z",
    ]);
    expect(rendered[0]!.attributes("style")).toContain("z-index: 0");
    expect(rendered[1]!.attributes("style")).toContain("z-index: 1");
  });

  it("uses the same static geometry in player and editor without animation classes", () => {
    const wrapper = mount(SequenceVisualLayers, { props: { layers } });
    const images = wrapper.findAll(".sequence-visual-layer-image");

    expect(images[0]!.attributes("src")).toBe("/hall.png");
    expect(images[0]!.attributes("style")).toContain("object-fit: cover");
    expect(images[0]!.attributes("style")).toContain("object-position: center center");
    expect(images[1]!.attributes("src")).toBe("/aria.png");
    expect(images[1]!.attributes("style")).toContain("object-position: center bottom");
    expect(images[1]!.attributes("class")).not.toMatch(/animate|transition/);
  });

  it("exposes optional composition provenance for inspection", () => {
    const wrapper = mount(SequenceVisualLayers, { props: { layers } });
    const character = wrapper.get('[data-layer-id="character"]');

    expect(character.attributes("data-origin-node-id")).toBe("42");
    expect(character.attributes("data-origin-sequence-id")).toBe("11");
    expect(character.attributes("data-inherited")).toBe("true");
  });
});
