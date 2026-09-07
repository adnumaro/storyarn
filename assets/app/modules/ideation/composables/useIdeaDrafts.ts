import { onUnmounted, reactive, ref } from "vue";
import type { BoardContext, Conflict, Idea, IdeaContent, Request } from "../types";

interface SaveAttempt {
  key: string;
  content: IdeaContent;
  revision: number;
  edit: number;
}
export interface Draft {
  idea: Idea;
  content: IdeaContent;
  context: BoardContext;
  edit: number;
  savedEdit: number;
  status: "saved" | "unsaved" | "saving" | "error" | "conflict";
  error: string | null;
  conflict: Conflict | null;
  attempt: SaveAttempt | null;
}

function content(idea: IdeaContent): IdeaContent {
  return { title: idea.title, body: idea.body, state: idea.state };
}

/** Drafts stay in this mounted board, never in browser storage. A reset unbinds
 * unsaved text from all entity IDs; it can only be copied back deliberately. */
export function useIdeaDrafts(request: Request, context: () => BoardContext) {
  const drafts = reactive(new Map<number, Draft>());
  const recovered = ref<IdeaContent[]>([]);
  const timers = new Map<number, ReturnType<typeof setTimeout>>();
  let generation = 0;

  function open(idea: Idea): Draft {
    const existing = drafts.get(idea.id);
    if (existing) {
      receive(idea);
      return existing;
    }
    drafts.set(idea.id, {
      idea,
      content: content(idea),
      context: context(),
      edit: 0,
      savedEdit: 0,
      status: "saved",
      error: null,
      conflict: null,
      attempt: null,
    });
    return drafts.get(idea.id)!;
  }

  function receive(idea: Idea) {
    const draft = drafts.get(idea.id);
    if (!draft || draft.status !== "saved") return;
    if (idea.revision < draft.idea.revision) return;
    draft.idea = idea;
    draft.content = content(idea);
  }

  function schedule(id: number) {
    clearTimeout(timers.get(id));
    timers.set(
      id,
      setTimeout(() => {
        void save(id);
      }, 800),
    );
  }

  function change(id: number, changes: Partial<IdeaContent>) {
    const draft = drafts.get(id);
    if (!draft) return;
    Object.assign(draft.content, changes);
    draft.edit++;
    if (draft.status === "saving" || draft.status === "conflict") return;
    // An uncertain request must be replayed verbatim before newer typing can save.
    if (draft.attempt) return;
    draft.status = "unsaved";
    draft.error = null;
    schedule(id);
  }

  async function save(id: number) {
    clearTimeout(timers.get(id));
    const draft = drafts.get(id);
    if (!draft || ["saving", "saved", "conflict"].includes(draft.status)) return;
    const started = generation;
    const attempt = draft.attempt ?? {
      key: crypto.randomUUID(),
      content: content(draft.content),
      revision: draft.idea.revision,
      edit: draft.edit,
    };
    draft.attempt = attempt;
    draft.status = "saving";
    const reply = await request<Idea>(
      "save_idea",
      {
        idea_id: id,
        revision: attempt.revision,
        request_key: attempt.key,
        ...attempt.content,
      },
      draft.context,
    );
    if (started !== generation || drafts.get(id) !== draft) return;
    if (reply.status === "ok") {
      draft.idea = reply.value;
      draft.savedEdit = attempt.edit;
      draft.attempt = null;
      draft.error = null;
      if (draft.edit === attempt.edit) {
        draft.content = content(reply.value);
        draft.status = "saved";
      } else {
        draft.status = "unsaved";
        schedule(id);
      }
    } else if (reply.status === "conflict") {
      draft.status = "conflict";
      draft.conflict = reply.value;
      draft.attempt = null;
    } else {
      draft.status = "error";
      draft.error = reply.code;
      if (reply.code !== "offline") draft.attempt = null;
    }
  }

  function resolve(id: number, keepMine: boolean) {
    const draft = drafts.get(id);
    if (!draft?.conflict) return;
    draft.idea = draft.conflict.current;
    draft.conflict = null;
    draft.error = null;
    draft.attempt = null;
    if (keepMine) {
      draft.status = "unsaved";
      void save(id);
    } else {
      draft.content = content(draft.idea);
      draft.savedEdit = draft.edit;
      draft.status = "saved";
    }
  }

  function reset(retainText = true) {
    generation++;
    for (const timer of timers.values()) clearTimeout(timer);
    timers.clear();
    if (retainText) {
      recovered.value.push(
        ...[...drafts.values()]
          .filter((draft) => draft.status !== "saved")
          .map((draft) => content(draft.content)),
      );
    } else recovered.value = [];
    drafts.clear();
  }

  onUnmounted(() => reset(false));
  return { drafts, recovered, open, receive, change, save, resolve, reset };
}
