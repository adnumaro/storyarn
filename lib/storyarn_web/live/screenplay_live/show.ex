defmodule StoryarnWeb.ScreenplayLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.Projects
  alias Storyarn.Screenplays
  alias Storyarn.Repo

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.project
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      screenplays_tree={@screenplays_tree}
      active_tool={:screenplays}
      selected_screenplay_id={to_string(@screenplay.id)}
      current_path={
        ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/screenplays/#{@screenplay.id}"
      }
      can_edit={@can_edit}
    >
      <div class="max-w-4xl mx-auto">
        <.header>
          {@screenplay.name}
          <:subtitle :if={@screenplay.description}>
            {@screenplay.description}
          </:subtitle>
        </.header>
      </div>
    </Layouts.project>
    """
  end

  @impl true
  def mount(
        %{
          "workspace_slug" => workspace_slug,
          "project_slug" => project_slug,
          "id" => screenplay_id
        },
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        project = Repo.preload(project, :workspace)
        screenplay = Screenplays.get_screenplay!(project.id, screenplay_id)
        screenplays_tree = Screenplays.list_screenplays_tree(project.id)
        can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:screenplay, screenplay)
          |> assign(:screenplays_tree, screenplays_tree)

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  # ---------------------------------------------------------------------------
  # Sidebar event handlers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("delete_screenplay", %{"id" => screenplay_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        screenplay = Screenplays.get_screenplay!(socket.assigns.project.id, screenplay_id)

        case Screenplays.delete_screenplay(screenplay) do
          {:ok, _} ->
            if to_string(screenplay.id) == to_string(socket.assigns.screenplay.id) do
              {:noreply,
               socket
               |> put_flash(:info, gettext("Screenplay moved to trash."))
               |> push_navigate(
                 to:
                   ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/screenplays"
               )}
            else
              {:noreply,
               socket
               |> put_flash(:info, gettext("Screenplay moved to trash."))
               |> reload_screenplays_tree()}
            end

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not delete screenplay."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("create_screenplay", _params, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Screenplays.create_screenplay(socket.assigns.project, %{
               name: gettext("Untitled")
             }) do
          {:ok, new_screenplay} ->
            {:noreply,
             push_navigate(socket,
               to:
                 ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/screenplays/#{new_screenplay.id}"
             )}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Could not create screenplay."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("create_child_screenplay", %{"parent-id" => parent_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        attrs = %{name: gettext("Untitled"), parent_id: parent_id}

        case Screenplays.create_screenplay(socket.assigns.project, attrs) do
          {:ok, new_screenplay} ->
            {:noreply,
             push_navigate(socket,
               to:
                 ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/screenplays/#{new_screenplay.id}"
             )}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Could not create screenplay."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event(
        "move_to_parent",
        %{"item_id" => item_id, "new_parent_id" => new_parent_id, "position" => position},
        socket
      ) do
    case authorize(socket, :edit_content) do
      :ok ->
        screenplay = Screenplays.get_screenplay!(socket.assigns.project.id, item_id)
        new_parent_id = parse_int(new_parent_id)
        position = parse_int(position) || 0

        case Screenplays.move_screenplay_to_position(screenplay, new_parent_id, position) do
          {:ok, _} ->
            {:noreply, reload_screenplays_tree(socket)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not move screenplay."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  defp parse_int(""), do: nil
  defp parse_int(nil), do: nil
  defp parse_int(val) when is_integer(val), do: val

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp reload_screenplays_tree(socket) do
    assign(
      socket,
      :screenplays_tree,
      Screenplays.list_screenplays_tree(socket.assigns.project.id)
    )
  end
end
