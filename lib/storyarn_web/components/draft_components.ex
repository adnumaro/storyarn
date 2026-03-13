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
      <.icon name="git-branch" class="size-4 text-warning" />
      <span class="flex-1">
        {dgettext("drafts", "Editing draft — changes don't affect the original")}
      </span>
      <button
        type="button"
        phx-click={show_modal("discard-draft-confirm")}
        class="btn btn-ghost btn-xs text-error"
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
end
