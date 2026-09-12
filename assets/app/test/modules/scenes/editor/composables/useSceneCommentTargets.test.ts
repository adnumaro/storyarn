import { afterEach, describe, expect, it } from "vitest";
import { effectScope, nextTick, reactive } from "vue";
import type { CommentContextReference } from "@components/comments/types";
import type { SceneRouteConnection } from "@modules/scenes/types/routes";
import type { SceneCommentTargets } from "@modules/scenes/editor/lib/comment-snap-adapter";
import { resolveSceneCommentPosition } from "@modules/scenes/editor/lib/comment-snap-adapter";
import { useSceneCommentTargets } from "@modules/scenes/editor/composables/useSceneCommentTargets";

const scopes: ReturnType<typeof effectScope>[] = [];
afterEach(() => scopes.splice(0).forEach((scope) => scope.stop()));

function connection(overrides: Partial<SceneRouteConnection> = {}): SceneRouteConnection {
  return {
    id: 3,
    fromPinId: 1,
    toPinId: 2,
    waypoints: [],
    label: "Patrol",
    showLabel: false,
    color: null,
    lineWidth: null,
    lineStyle: null,
    bidirectional: false,
    ...overrides,
  };
}

function setup() {
  const state = reactive({
    sceneId: 10 as number | null,
    userId: 20,
    context: { type: "scene_pin", id: "1" } as CommentContextReference & {
      status?: "available" | "unavailable";
    },
    layers: [
      { id: 1, visible: false, name: "Hidden actors" },
      { id: 2, visible: true, name: "Visible actors" },
    ],
    pins: [
      { id: 1, positionX: 10, positionY: 20, layerId: 1 as number | null },
      { id: 2, positionX: 60, positionY: 70, layerId: 2 as number | null },
    ],
    annotations: [{ id: 1, positionX: 30, positionY: 40, layerId: 1 }],
    zones: [
      {
        id: 4,
        layerId: 1,
        vertices: [
          { x: 30, y: 60 },
          { x: 40, y: 20 },
          { x: 50, y: 60 },
        ],
      },
    ],
    connections: [connection()],
    pinConfigs: [] as SceneCommentTargets["pins"],
    zoneConfigs: [] as SceneCommentTargets["zones"],
    annotationConfigs: [] as SceneCommentTargets["annotations"],
    connectionConfigs: [
      { id: 3, points: [124, 160, 576, 560], opacity: 1, connectedLayerIds: [1, 2] },
    ],
    waypointOverride: null as {
      connectionId: number;
      waypoints: { x: number; y: number }[];
    } | null,
  });
  const projection = {
    pixelToPercent: (x: number, y: number) => ({ x: x / 10, y: y / 8 }),
    percentToPixel: (x: number, y: number) => ({ x: x * 10, y: y * 8 }),
  };
  const scope = effectScope();
  scopes.push(scope);
  const comments = scope.run(() =>
    useSceneCommentTargets({
      sceneId: () => state.sceneId,
      userId: () => state.userId,
      layers: () => state.layers,
      pins: () => state.pins,
      zones: () => state.zones,
      annotations: () => state.annotations,
      connections: () => state.connections,
      pinConfigs: () => state.pinConfigs,
      zoneConfigs: () => state.zoneConfigs,
      annotationConfigs: () => state.annotationConfigs,
      connectionConfigs: () => state.connectionConfigs,
      projection: () => projection,
      context: () => state.context,
      waypointOverride: () => state.waypointOverride,
    }),
  )!;
  return { state, comments, projection };
}

describe("Scene comment target projection", () => {
  it("keeps raw percent origins for each context, with a zone bounding origin and a connection raw endpoint", () => {
    const { comments } = setup();
    expect(comments.targets.value.origins).toEqual([
      { type: "scene_pin", id: 1, position: { x: 10, y: 20 } },
      { type: "scene_pin", id: 2, position: { x: 60, y: 70 } },
      { type: "scene_annotation", id: 1, position: { x: 30, y: 40 } },
      { type: "scene_zone", id: 4, position: { x: 30, y: 20 } },
      { type: "scene_connection", id: 3, position: { x: 10, y: 20 } },
    ]);
    expect(comments.targets.value.connections[0]).toMatchObject({
      origin: { x: 10, y: 20 },
      label: "Patrol",
    });
  });

  it("reveals only the local view and resets on command or Scene navigation", async () => {
    const { state, comments } = setup();
    expect(comments.hiddenContext.value).toBe(true);
    comments.revealContext();
    expect(comments.hiddenContext.value).toBe(false);
    expect(comments.locallyRevealed.value).toBe(true);
    expect(comments.effectiveLayers.value[0]).toEqual({
      id: 1,
      visible: true,
      name: "Hidden actors",
    });
    expect(state.layers[0].visible).toBe(false);
    comments.resetLocalLayers();
    expect(comments.hiddenContext.value).toBe(true);
    comments.revealContext();
    state.sceneId = 99;
    await nextTick();
    expect(comments.locallyRevealed.value).toBe(false);
    expect(comments.hiddenContext.value).toBe(true);
  });

  it("does not claim unavailable targets or visible/free-endpoint connections are hidden", () => {
    const { state, comments } = setup();
    state.context = { type: "scene_pin", id: "1", status: "unavailable" };
    expect(comments.hiddenContext.value).toBe(false);
    state.context = { type: "scene_connection", id: "3" };
    expect(comments.hiddenContext.value).toBe(false);
    state.layers[1].visible = false;
    expect(comments.hiddenContext.value).toBe(true);
    state.connections[0].fromPinId = null;
    expect(comments.hiddenContext.value).toBe(false);
    state.connections[0].fromPinId = 1;
    state.pins[1].layerId = null;
    expect(comments.hiddenContext.value).toBe(false);
  });

  it("tracks live annotation and pin positions separately even when their numeric IDs match", () => {
    const { state, comments, projection } = setup();
    state.layers[0].visible = true;
    state.pinConfigs = [
      { id: 1, x: 100, y: 160, radius: 20, label: "Actor", layerId: 1, opacity: 1 },
    ];
    state.annotationConfigs = [
      { id: 1, x: 300, y: 320, width: 200, height: 150, text: "Note", layerId: 1 },
    ];
    const pinContext = { type: "scene_pin", id: "1", offset: { x: 1, y: 2 } };
    const noteContext = { type: "scene_annotation", id: "1", offset: { x: 1, y: 2 } };
    comments.trackDrag("annotation", 1, { x: 500, y: 480 });
    expect(
      resolveSceneCommentPosition(null, noteContext, comments.targets.value, projection),
    ).toEqual({ x: 51, y: 62 });
    expect(
      resolveSceneCommentPosition(null, pinContext, comments.targets.value, projection),
    ).toEqual({ x: 11, y: 22 });
    expect(comments.targets.value.connections[0].origin).toEqual({ x: 10, y: 20 });
    comments.trackDrag("pin", 1, { x: 700, y: 560 });
    expect(
      resolveSceneCommentPosition(null, noteContext, comments.targets.value, projection),
    ).toEqual({ x: 31, y: 42 });
    expect(
      resolveSceneCommentPosition(null, pinContext, comments.targets.value, projection),
    ).toEqual({ x: 71, y: 72 });
    expect(comments.targets.value.connections[0].origin).toEqual({ x: 70, y: 70 });
    comments.clearDrag();
    expect(comments.targets.value.connections[0].origin).toEqual({ x: 10, y: 20 });
  });

  it("uses the live first waypoint for free routes, then the endpoint if the path is empty", () => {
    const { state, comments } = setup();
    state.connections[0] = connection({
      fromPinId: null,
      waypoints: [
        { x: 20, y: 30 },
        { x: 40, y: 50 },
      ],
    });
    expect(comments.targets.value.connections[0]).toMatchObject({
      origin: { x: 20, y: 30 },
      freeEndpoint: true,
    });
    state.waypointOverride = {
      connectionId: 3,
      waypoints: [
        { x: 25, y: 35 },
        { x: 40, y: 50 },
      ],
    };
    expect(comments.targets.value.connections[0].origin).toEqual({ x: 25, y: 35 });
    state.waypointOverride = null;
    state.connections[0].waypoints = [];
    expect(comments.targets.value.connections[0].origin).toEqual({ x: 60, y: 70 });
  });

  it("drops deleted origins and ignores stale rendered connections", () => {
    const { state, comments, projection } = setup();
    state.pins = [];
    state.connections = [];
    expect(comments.targets.value.origins?.some((origin) => origin.type === "scene_pin")).toBe(
      false,
    );
    expect(comments.targets.value.connections).toEqual([]);
    expect(
      resolveSceneCommentPosition(
        { x: 15, y: 25 },
        { type: "scene_pin", id: "1", offset: { x: 3, y: 4 } },
        comments.targets.value,
        projection,
      ),
    ).toEqual({ x: 15, y: 25 });
  });

  it("scopes draft storage to the current user and Scene, requiring a real Scene identity", async () => {
    const { state, comments } = setup();
    expect(comments.draftStorageKey.value).toBe("storyarn:scene-comment-draft:20:10");
    comments.revealContext();
    state.userId = 21;
    await nextTick();
    expect(comments.draftStorageKey.value).toBe("storyarn:scene-comment-draft:21:10");
    expect(comments.locallyRevealed.value).toBe(false);
    state.sceneId = null;
    expect(comments.draftStorageKey.value).toBeNull();
  });
});
