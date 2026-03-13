defmodule StoryarnWeb.Live.Shared.DraftHandlers do
  @moduledoc false

  import Phoenix.LiveView
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Drafts

  @doc """
  Handles the "create_draft" event. Call from handle_event with:

      DraftHandlers.handle_create_draft(socket, entity_type, entity_id, draft_path_fn)

  `draft_path_fn` receives `(socket, draft)` and returns the path to navigate to.
  """
  def handle_create_draft(socket, entity_type, entity_id, draft_path_fn) do
    %{project: project, current_scope: scope} = socket.assigns

    case Drafts.create_draft(project.id, entity_type, entity_id, scope.user.id) do
      {:ok, draft} ->
        {:noreply, push_navigate(socket, to: draft_path_fn.(socket, draft))}

      {:error, :draft_limit_reached} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("drafts", "You've reached the maximum number of active drafts.")
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("drafts", "Could not create draft."))}
    end
  end

  @doc """
  Handles the "discard_draft" event. Call from handle_event with:

      DraftHandlers.handle_discard_draft(socket, redirect_path)
  """
  def handle_discard_draft(socket, redirect_path) do
    %{draft: draft} = socket.assigns

    case Drafts.discard_draft(draft) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("drafts", "Draft discarded."))
         |> push_navigate(to: redirect_path)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("drafts", "Could not discard draft."))}
    end
  end
end
