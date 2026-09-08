import { computed, onScopeDispose, ref, watch } from "vue";
import type { Board, GroupText, GroupVersions, IdeaGroup, Request } from "../types";
import type { Point } from "./useCanvasViewport";
import type { useCanvasHistory, CanvasCommand } from "./useCanvasHistory";

interface GroupChanges {
  title?: string;
  synthesis?: string;
  idea_ids?: number[];
  canvas?: Point;
}
type History = ReturnType<typeof useCanvasHistory>;
type Acknowledged = "applied" | "unconfirmed" | "cancelled";
/** A rejected member placement is reported with group copy, not single-note copy. */
function groupCode(code: string) {
  return code === "stale_canvas" ? "stale_group_canvas" : code;
}
function previousChanges(group: IdeaGroup, changes: GroupChanges): GroupChanges {
  const previous: GroupChanges = {};
  if (changes.title !== undefined) previous.title = group.title ?? "";
  if (changes.synthesis !== undefined) previous.synthesis = group.synthesis ?? "";
  if (changes.idea_ids !== undefined) previous.idea_ids = [...group.idea_ids];
  if (changes.canvas) previous.canvas = { x: group.canvas.x, y: group.canvas.y };
  return previous;
}

function matchesChanges(group: IdeaGroup, expected: GroupChanges) {
  if (!matchesText(group.title, expected.title)) return false;
  if (!matchesText(group.synthesis, expected.synthesis)) return false;
  if (expected.idea_ids && !sameMembers(group.idea_ids, expected.idea_ids)) return false;
  if (expected.canvas && !samePoint(group.canvas, expected.canvas)) return false;
  return true;
}
function matchesText(current: string | null, expected: string | undefined) {
  return expected === undefined || (current ?? "") === expected;
}
function sameMembers(a: number[], b: number[]) {
  return a.length === b.length && a.every((id) => b.includes(id));
}
function samePoint(a: Point, b: Point) {
  return a.x === b.x && a.y === b.y;
}
function snapshot(group: IdeaGroup): IdeaGroup {
  return {
    ...group,
    canvas: { ...group.canvas },
    idea_ids: [...group.idea_ids],
    members: group.members.map((member) => ({ ...member, canvas: { ...member.canvas } })),
  };
}

/** Group writes stay serialized until their authoritative board projection arrives. */
export function useCanvasGroups(
  board: () => Board,
  request: Request,
  history: History,
  notify: (code: string | null, replacing?: string) => void,
  select: (id: number | null) => void,
  settleNotes: (ids: number[]) => Promise<boolean>,
) {
  const selected = ref<number | null>(null);
  const groups = computed(() =>
    board().session?.configuration.private_mode ? [] : (board().groups ?? []),
  );
  const allowed = computed(
    () =>
      board().can_edit &&
      board().session?.status === "open" &&
      !board().session?.configuration.private_mode,
  );
  const retryKeys = new Map<string, string>();
  const pending = new Set<() => void>();
  const find = (id: number) => groups.value.find((group) => group.id === id);
  function choose(id: number | null) {
    selected.value = id;
    select(id);
  }
  function reset() {
    for (const cancel of pending) cancel();
    retryKeys.clear();
    selected.value = null;
  }
  function applied(result: IdeaGroup, at: { epoch: string; sessionId: number | undefined }) {
    return new Promise<Acknowledged>((resolve) => {
      let settled = false;
      const complete = (value: Acknowledged) => {
        stop();
        clearTimeout(timeout);
        pending.delete(cancel);
        if (!settled) resolve(value);
        settled = true;
      };
      const cancel = () => complete("cancelled");
      const check = () => {
        if (board().epoch !== at.epoch || board().session?.id !== at.sessionId || !allowed.value)
          return complete("cancelled");
        if (board().error) return complete("cancelled");
        const current = find(result.id);
        if (result.deleted_at ? !current : current && current.version >= result.version) {
          // A projection arriving after the sync notice retires that notice.
          if (settled) notify(null, "group_sync_pending");
          complete("applied");
        }
      };
      // LiveVue can mutate nested fields without replacing the array.
      const stop = watch(
        () => [board().groups, board().epoch, board().session?.id, board().error, allowed.value],
        check,
        { deep: true, flush: "post" },
      );
      // The server committed the write; only its projection is late. Let the
      // caller proceed and keep watching so the notice clears when it lands.
      const timeout = setTimeout(() => {
        notify("group_sync_pending");
        void request("sync_board", {});
        settled = true;
        resolve("unconfirmed");
      }, 12_000);
      pending.add(cancel);
      check();
    });
  }
  async function mutate(
    event: string,
    payload: Record<string, unknown>,
  ): Promise<IdeaGroup | null> {
    if (!allowed.value) return null;
    const at = { epoch: board().epoch, sessionId: board().session?.id };
    const fingerprint = JSON.stringify([event, payload]);
    const key = retryKeys.get(fingerprint) ?? crypto.randomUUID();
    retryKeys.set(fingerprint, key);
    const reply = await request<IdeaGroup>(event, { ...payload, request_key: key });
    if (reply.status !== "ok") {
      if (reply.status !== "error" || reply.code !== "offline") retryKeys.delete(fingerprint);
      notify(reply.status === "error" ? groupCode(reply.code) : "stale_group");
      return null;
    }
    const acknowledged = await applied(reply.value, at);
    if (acknowledged === "cancelled") return null;
    retryKeys.delete(fingerprint);
    if (acknowledged === "applied") notify(null);
    return snapshot(reply.value);
  }
  function updateCommand(
    before: IdeaGroup,
    after: IdeaGroup,
    previous: GroupChanges,
    next: GroupChanges,
  ): CanvasCommand {
    let expected = next;
    async function apply(changes: GroupChanges) {
      const current = find(after.id);
      if (!current || !matchesChanges(current, expected)) return false;
      const result = await mutate("update_group", {
        group_id: current.id,
        version: current.version,
        ...changes,
      });
      if (!result) return false;
      expected = changes;
      choose(result.id);
      return true;
    }
    return {
      targets: () => [...new Set([...before.idea_ids, ...after.idea_ids])].map((id) => ({ id })),
      undo: () => apply(previous),
      redo: () => apply(next),
    };
  }
  async function update(id: number, changes: GroupChanges, version?: number): Promise<boolean> {
    const before = find(id);
    if (!before || !allowed.value || history.busy.value) return false;
    if (version !== undefined && before.version !== version) {
      notify("stale_group");
      return false;
    }
    const previous = previousChanges(before, changes);
    if (JSON.stringify(previous) === JSON.stringify(changes)) return true;
    const initial = snapshot(before);
    const result = await history.run(() =>
      mutate("update_group", { group_id: id, version: initial.version, ...changes }),
    );
    if (!result) return false;
    history.push(updateCommand(initial, result, previous, previousChanges(result, changes)));
    return true;
  }
  function presenceCommand(
    group: IdeaGroup,
    created: boolean,
    originalIds = group.idea_ids,
  ): CanvasCommand {
    let expected = snapshot(group);
    async function hide() {
      const current = find(expected.id);
      if (
        !current ||
        !matchesChanges(current, {
          title: expected.title ?? "",
          synthesis: expected.synthesis ?? "",
          idea_ids: expected.idea_ids,
        })
      )
        return false;
      const result = await mutate("delete_group", {
        group_id: current.id,
        version: current.version,
      });
      if (!result) return false;
      expected = result;
      choose(null);
      return true;
    }
    async function show() {
      const result = await mutate("restore_group", {
        group_id: expected.id,
        version: expected.version,
        deleted_at: expected.deleted_at,
        idea_ids: originalIds,
      });
      if (!result) return false;
      expected = result;
      choose(result.id);
      return true;
    }
    return {
      targets: () => originalIds.map((id) => ({ id })),
      undo: created ? hide : show,
      redo: created ? show : hide,
    };
  }
  async function create(ids: number[], canvas: IdeaGroup["canvas"]) {
    if (!allowed.value || history.busy.value || ids.length < 2) return;
    const result = await history.run(async () => {
      if (!(await settleNotes(ids))) return null;
      return mutate("create_group", { idea_ids: ids, title: "", synthesis: "", canvas });
    });
    if (!result) return;
    history.push(presenceCommand(result, true));
    choose(result.id);
  }
  async function separate(id: number, canvas?: Point) {
    const initial = find(id);
    if (!initial || !allowed.value || history.busy.value) return;
    if (initial.synthesis?.trim()) {
      if (await update(id, { idea_ids: [], ...(canvas ? { canvas } : {}) })) choose(id);
      return;
    }
    await remove(id);
  }
  async function remove(id: number) {
    const initial = find(id);
    if (!initial || !allowed.value || history.busy.value) return;
    const before = snapshot(initial);
    const result = await history.run(() =>
      mutate("delete_group", { group_id: id, version: before.version }),
    );
    if (!result) return;
    history.push(presenceCommand(result, false, before.idea_ids));
    choose(null);
  }
  async function move(id: number, point: Point, expectedVersions?: GroupVersions) {
    if (!allowed.value || history.busy.value) return;
    const initial = find(id);
    if (!initial) return;
    const before = snapshot(initial);
    if (expectedVersions && !matchesVersions(before, expectedVersions)) {
      notify("stale_group");
      return;
    }
    if (before.canvas.x === point.x && before.canvas.y === point.y) return;
    const result = await history.run(async () => {
      if (!(await settleNotes(before.idea_ids))) return null;
      const current = find(id);
      if (!current || current.version !== before.version || !samePlacements(current, before)) {
        notify("stale_group");
        return null;
      }
      return moveTo(current, point);
    });
    if (!result) return;
    let expected = result;
    async function apply(destination: Point) {
      const current = find(id);
      if (!current || !samePlacements(current, expected)) return false;
      const next = await moveTo(current, destination);
      if (!next) return false;
      expected = next;
      choose(id);
      return true;
    }
    history.push({
      targets: () => before.idea_ids.map((id) => ({ id })),
      undo: () => apply(before.canvas),
      redo: () => apply(point),
    });
  }
  function moveTo(group: IdeaGroup, point: Point) {
    return mutate("move_group", {
      group_id: group.id,
      version: group.version,
      x: point.x,
      y: point.y,
      member_versions: group.members.map((member) => ({
        id: member.idea_id,
        version: member.canvas.version ?? 0,
      })),
    });
  }
  function matchesVersions(group: IdeaGroup, expected: GroupVersions) {
    return (
      group.version === expected.version &&
      group.members.length === expected.member_versions.length &&
      group.members.every((member) =>
        expected.member_versions.some(
          (version) =>
            version.id === member.idea_id && version.version === (member.canvas.version ?? 0),
        ),
      )
    );
  }
  function samePlacements(a: IdeaGroup, b: IdeaGroup) {
    return (
      a.canvas.x === b.canvas.x &&
      a.canvas.y === b.canvas.y &&
      a.members.length === b.members.length &&
      a.members.every((member) =>
        b.members.some(
          (other) =>
            member.idea_id === other.idea_id &&
            member.canvas.x === other.canvas.x &&
            member.canvas.y === other.canvas.y,
        ),
      )
    );
  }
  async function membership(id: number, ids: number[], add: boolean, canvas?: Point) {
    const current = find(id);
    if (!current) return;
    const next = add
      ? [...new Set([...current.idea_ids, ...ids])]
      : current.idea_ids.filter((noteId) => !ids.includes(noteId));
    if (!next.length) await separate(id, canvas);
    else await update(id, { idea_ids: next });
  }
  watch([() => board().epoch, () => board().session?.id], reset);
  watch(allowed, (value) => {
    if (!value) reset();
  });
  watch(
    groups,
    (values) => {
      if (selected.value !== null && !values.some((group) => group.id === selected.value))
        selected.value = null;
    },
    { deep: true },
  );
  onScopeDispose(reset);
  return {
    groups,
    selected,
    allowed,
    choose,
    reset,
    create,
    move,
    separate,
    remove,
    membership,
    save: (id: number, text: GroupText, version: number) => update(id, text, version),
  };
}
