defmodule StoryarnWeb.PageLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.Components.PageComponents

  alias Storyarn.Pages
  alias Storyarn.Projects
  alias Storyarn.Repo

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.project
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      pages_tree={@pages_tree}
      current_path={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages"}
      can_edit={@can_edit}
    >
      <div class="text-center mb-8">
        <.header>
          {gettext("Pages")}
          <:subtitle>
            {gettext("Create and organize your project's content")}
          </:subtitle>
          <:actions :if={@can_edit}>
            <.link
              patch={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages/new"}
              class="btn btn-primary"
            >
              <.icon name="plus" class="size-4 mr-2" />
              {gettext("New Page")}
            </.link>
          </:actions>
        </.header>
      </div>

      <.empty_state :if={@pages_tree == []} icon="file-text">
        {gettext("No pages yet. Create your first page to get started.")}
      </.empty_state>

      <div :if={@pages_tree != []} class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <.page_card
          :for={page <- @pages_tree}
          page={page}
          project={@project}
          workspace={@workspace}
        />
      </div>

      <.modal
        :if={@live_action == :new}
        id="new-page-modal"
        show
        on_cancel={JS.patch(~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages")}
      >
        <.live_component
          module={StoryarnWeb.PageLive.Form}
          id="new-page-form"
          project={@project}
          title={gettext("New Page")}
          parent_options={parent_options(@pages_tree)}
          navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages"}
        />
      </.modal>
    </Layouts.project>
    """
  end

  attr :page, :map, required: true
  attr :project, :map, required: true
  attr :workspace, :map, required: true

  defp page_card(assigns) do
    children_count = length(Map.get(assigns.page, :children, []))

    assigns = assign(assigns, :children_count, children_count)

    ~H"""
    <.link
      navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages/#{@page.id}"}
      class="card bg-base-100 border border-base-300 shadow-sm hover:shadow-md transition-shadow"
    >
      <div class="card-body">
        <div class="flex items-center gap-3">
          <.page_avatar avatar_asset={@page.avatar_asset} name={@page.name} size="lg" />
          <div>
            <h3 class="card-title text-lg">{@page.name}</h3>
            <p :if={@children_count > 0} class="text-sm text-base-content/50">
              {ngettext("%{count} subpage", "%{count} subpages", @children_count)}
            </p>
          </div>
        </div>
      </div>
    </.link>
    """
  end

  defp parent_options(pages_tree) do
    flatten_pages(pages_tree, [], 0)
  end

  defp flatten_pages(pages, acc, depth) do
    Enum.reduce(pages, acc, fn page, acc ->
      prefix = String.duplicate("  ", depth)
      children = Map.get(page, :children, [])

      acc
      |> Kernel.++([{prefix <> page.name, page.id}])
      |> flatten_pages(children, depth + 1)
    end)
  end

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug},
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
        pages_tree = Pages.list_pages_tree(project.id)
        can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:pages_tree, pages_tree)

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({StoryarnWeb.PageLive.Form, {:saved, page}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, gettext("Page created successfully."))
     |> push_navigate(
       to:
         ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/pages/#{page.id}"
     )}
  end

  @impl true
  def handle_event("delete_page", %{"id" => page_id}, socket) do
    if socket.assigns.can_edit do
      page = Pages.get_page!(socket.assigns.project.id, page_id)

      case Pages.delete_page(page) do
        {:ok, _} ->
          pages_tree = Pages.list_pages_tree(socket.assigns.project.id)

          {:noreply,
           socket
           |> put_flash(:info, gettext("Page deleted successfully."))
           |> assign(:pages_tree, pages_tree)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not delete page."))}
      end
    else
      {:noreply,
       put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event(
        "move_page",
        %{"page_id" => page_id, "parent_id" => parent_id, "position" => position},
        socket
      ) do
    if socket.assigns.can_edit do
      page = Pages.get_page!(socket.assigns.project.id, page_id)
      parent_id = normalize_parent_id(parent_id)

      case Pages.move_page_to_position(page, parent_id, position) do
        {:ok, _page} ->
          pages_tree = Pages.list_pages_tree(socket.assigns.project.id)
          {:noreply, assign(socket, :pages_tree, pages_tree)}

        {:error, :would_create_cycle} ->
          {:noreply,
           put_flash(socket, :error, gettext("Cannot move a page into its own children."))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not move page."))}
      end
    else
      {:noreply,
       put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("create_child_page", %{"parent-id" => parent_id}, socket) do
    if socket.assigns.can_edit do
      attrs = %{name: gettext("New Page"), parent_id: parent_id}

      case Pages.create_page(socket.assigns.project, attrs) do
        {:ok, new_page} ->
          pages_tree = Pages.list_pages_tree(socket.assigns.project.id)

          {:noreply,
           socket
           |> assign(:pages_tree, pages_tree)
           |> push_navigate(
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/pages/#{new_page.id}"
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, gettext("Could not create page."))}
      end
    else
      {:noreply,
       put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end
end
