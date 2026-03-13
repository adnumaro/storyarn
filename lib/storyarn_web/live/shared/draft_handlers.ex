defmodule StoryarnWeb.Live.Shared.DraftHandlers do
  @moduledoc false

  import Phoenix.LiveView
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.{Collaboration, Drafts}

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

  @doc """
  Handles the "merge_draft" event. Call from handle_event with:

      DraftHandlers.handle_merge_draft(socket, redirect_path_fn)

  `redirect_path_fn` receives `(socket)` and returns the path to the original entity.
  Broadcasts `:entity_merged` to collaborators on the original entity.
  """
  def handle_merge_draft(socket, redirect_path_fn) do
    %{draft: draft, current_scope: scope} = socket.assigns

    case Drafts.merge_draft(draft, scope.user.id) do
      {:ok, _updated_entity} ->
        editor_scope = editor_scope_for(draft)

        Collaboration.broadcast_change_from(self(), editor_scope, :entity_merged, %{
          entity_type: draft.entity_type,
          entity_id: draft.source_entity_id,
          user_email: scope.user.email,
          user_id: scope.user.id,
          user_color: Collaboration.user_color(scope.user.id)
        })

        {:noreply,
         socket
         |> put_flash(:info, dgettext("drafts", "Draft merged successfully."))
         |> push_navigate(to: redirect_path_fn.(socket))}

      {:error, :source_not_found} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("drafts", "The original entity no longer exists.")
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("drafts", "Could not merge draft."))}
    end
  end

  @doc """
  Loads the merge summary for the current draft.
  Returns `{:noreply, socket}` with `:merge_summary` assigned.
  """
  def handle_load_merge_summary(socket) do
    %{draft: draft} = socket.assigns

    # Reset to nil so the modal shows a loading spinner on re-open
    socket = Phoenix.Component.assign(socket, :merge_summary, nil)

    case Drafts.build_merge_summary(draft) do
      {:ok, summary} ->
        {:noreply, Phoenix.Component.assign(socket, :merge_summary, summary)}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("drafts", "Could not load merge summary.")
         )}
    end
  end

  defp editor_scope_for(%{entity_type: "flow", source_entity_id: id}), do: {:flow, id}
  defp editor_scope_for(%{entity_type: "sheet", source_entity_id: id}), do: {:sheet, id}
  defp editor_scope_for(%{entity_type: "scene", source_entity_id: id}), do: {:scene, id}
end
