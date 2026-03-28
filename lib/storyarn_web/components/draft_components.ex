defmodule StoryarnWeb.Components.DraftComponents do
  @moduledoc false
  use StoryarnWeb, :html

  @doc """
  Banner shown at the top of an editor when in draft mode.
  """
  attr :is_draft, :boolean, required: true

  def draft_banner(assigns) do
    ~H"""
    <div
      :if={@is_draft}
      class="bg-warning/20 border-b border-warning px-4 py-1.5 text-sm flex items-center gap-2"
    >
      <.icon name="git-branch" class="size-4 text-amber-600 dark:text-amber-400" />
      <span class="flex-1">
        {dgettext("drafts", "Editing draft — changes don't affect the original")}
      </span>
      <button
        type="button"
        phx-click={JS.push("load_merge_summary")}
        class="inline-flex items-center justify-center px-3 py-2 text-sm rounded-md hover:bg-accent transition-colors btn-xs text-green-600 dark:text-green-400"
      >
        <.icon name="git-merge" class="size-3.5" />
        {dgettext("drafts", "Merge")}
      </button>
      <button
        type="button"
        phx-click={show_modal("discard-draft-confirm")}
        class="inline-flex items-center justify-center px-3 py-2 text-sm rounded-md hover:bg-accent transition-colors btn-xs text-destructive"
      >
        {dgettext("drafts", "Discard")}
      </button>
    </div>
    """
  end

  @doc """
  Confirmation modal for discarding a draft.
  """
  attr :is_draft, :boolean, required: true

  def discard_draft_modal(assigns) do
    ~H"""
    <.confirm_modal
      :if={@is_draft}
      id="discard-draft-confirm"
      title={dgettext("drafts", "Discard draft?")}
      message={dgettext("drafts", "This draft will be permanently deleted. This cannot be undone.")}
      confirm_text={dgettext("drafts", "Discard")}
      confirm_variant="error"
      icon="trash-2"
      on_confirm={JS.push("discard_draft")}
    />
    """
  end

  @doc """
  Modal for reviewing and merging a draft.
  Shows a diff summary and merge/cancel actions.
  """
  attr :is_draft, :boolean, required: true
  attr :merge_summary, :map, default: nil

  def merge_review_modal(assigns) do
    ~H"""
    <.modal :if={@is_draft} id="merge-review-modal">
      <div class="space-y-4">
        <div class="flex items-center gap-3">
          <div class="bg-success/20 rounded-full p-2">
            <.icon name="git-merge" class="size-5 text-green-600 dark:text-green-400" />
          </div>
          <div>
            <h3 class="text-lg font-semibold">{dgettext("drafts", "Merge Draft")}</h3>
            <p class="text-sm text-muted-foreground">
              {dgettext("drafts", "This will replace the original with your draft's content.")}
            </p>
          </div>
        </div>

        <div :if={@merge_summary} class="space-y-3">
          <div
            :if={@merge_summary.draft_changes != ""}
            class="bg-muted rounded-lg p-3 text-sm"
          >
            <div class="font-medium mb-1">{dgettext("drafts", "Changes in this draft")}</div>
            <p class="text-muted-foreground">{@merge_summary.draft_changes}</p>
          </div>
          <div
            :if={@merge_summary.draft_changes == ""}
            class="bg-muted rounded-lg p-3 text-sm text-muted-foreground"
          >
            {dgettext("drafts", "No changes detected.")}
          </div>

          <div
            :if={@merge_summary.original_versions_since_fork > 0}
            class="bg-warning/10 border border-warning/30 rounded-lg p-3 text-sm"
          >
            <div class="flex items-center gap-2 text-amber-600 dark:text-amber-400">
              <.icon name="alert-triangle" class="size-4" />
              <span class="font-medium">{dgettext("drafts", "Original has diverged")}</span>
            </div>
            <p class="text-muted-foreground mt-1">
              {dngettext(
                "drafts",
                "The original has %{count} new version since this draft was created. Merging will overwrite those changes. A safety snapshot will be created first.",
                "The original has %{count} new versions since this draft was created. Merging will overwrite those changes. A safety snapshot will be created first.",
                @merge_summary.original_versions_since_fork,
                count: @merge_summary.original_versions_since_fork
              )}
            </p>
          </div>
        </div>

        <div :if={is_nil(@merge_summary)} class="flex justify-center py-4">
          <span class="size-5 border-2 border-muted-foreground/20 border-t-muted-foreground/60 rounded-full animate-spin"></span>
        </div>

        <div class="flex justify-end gap-2 pt-2">
          <button
            type="button"
            phx-click={hide_modal("merge-review-modal")}
            class="inline-flex items-center justify-center h-8 px-3 text-sm rounded-md hover:bg-accent transition-colors"
          >
            {dgettext("drafts", "Cancel")}
          </button>
          <button
            type="button"
            phx-click={JS.push("merge_draft") |> hide_modal("merge-review-modal")}
            class="inline-flex items-center justify-center px-3 py-2 text-sm rounded-md bg-green-600 text-white hover:bg-green-700 btn-sm"
            disabled={is_nil(@merge_summary)}
          >
            <.icon name="git-merge" class="size-4" />
            {dgettext("drafts", "Merge into original")}
          </button>
        </div>
      </div>
    </.modal>
    """
  end
end
