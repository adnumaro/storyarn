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

  @doc """
  Handles starting an inline rename of a draft from the drafts list.
  Sets `:renaming_draft` assign to show the inline input form.
  """
  def handle_rename_draft_inline(socket, draft_id) do
    %{current_scope: scope, project: project} = socket.assigns

    case Drafts.get_my_draft(draft_id, scope.user.id, project.id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("drafts", "Draft not found."))}

      draft ->
        {:noreply, Phoenix.Component.assign(socket, :renaming_draft, draft)}
    end
  end

  @doc """
  Handles submitting a draft rename.
  """
  def handle_submit_rename_draft(socket, %{"name" => name, "draft_id" => draft_id}) do
    %{current_scope: scope, project: project} = socket.assigns

    case Drafts.get_my_draft(draft_id, scope.user.id, project.id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("drafts", "Draft not found."))}

      draft ->
        case Drafts.rename_draft(draft, name) do
          {:ok, updated} ->
            updated_list =
              Enum.map(socket.assigns.my_drafts, fn d ->
                if d.id == updated.id, do: %{d | name: updated.name}, else: d
              end)

            {:noreply,
             socket
             |> Phoenix.Component.assign(:renaming_draft, nil)
             |> Phoenix.Component.assign(:my_drafts, updated_list)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, dgettext("drafts", "Could not rename draft."))}
        end
    end
  end

  def handle_submit_rename_draft(socket, _params) do
    {:noreply, socket}
  end

  @doc """
  Handles discarding a draft from the drafts list (not the current draft being edited).
  """
  def handle_discard_draft_from_list(socket, draft_id) do
    %{current_scope: scope, project: project} = socket.assigns

    case Drafts.get_my_draft(draft_id, scope.user.id, project.id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("drafts", "Draft not found."))}

      draft ->
        case Drafts.discard_draft(draft) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, dgettext("drafts", "Draft discarded."))
             |> Phoenix.Component.assign(
               :my_drafts,
               Drafts.list_my_drafts(project.id, scope.user.id)
             )}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("drafts", "Could not discard draft."))}
        end
    end
  end

  @doc """
  Handles the `:touch_draft` message. Call from `handle_info(:touch_draft, socket)`.
  """
  def handle_touch_draft(socket) do
    if socket.assigns[:is_draft] && socket.assigns[:draft] do
      Drafts.touch_draft(socket.assigns.draft.id)
    end

    {:noreply, socket}
  end

  defp editor_scope_for(%{entity_type: "flow", source_entity_id: id}), do: {:flow, id}
  defp editor_scope_for(%{entity_type: "sheet", source_entity_id: id}), do: {:sheet, id}
  defp editor_scope_for(%{entity_type: "scene", source_entity_id: id}), do: {:scene, id}
end
