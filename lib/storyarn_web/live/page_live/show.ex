defmodule StoryarnWeb.PageLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.LiveHelpers.Authorize

  import StoryarnWeb.Components.PageComponents
  import StoryarnWeb.Components.SaveIndicator

  alias Storyarn.Pages
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias StoryarnWeb.PageLive.Components.Banner
  alias StoryarnWeb.PageLive.Components.ContentTab
  alias StoryarnWeb.PageLive.Components.PageAvatar
  alias StoryarnWeb.PageLive.Components.PageColor
  alias StoryarnWeb.PageLive.Components.PageTitle
  alias StoryarnWeb.PageLive.Components.ReferencesTab
  alias StoryarnWeb.PageLive.Helpers.PageTreeHelpers
  alias StoryarnWeb.PageLive.Helpers.ReferenceHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.project
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      pages_tree={@pages_tree}
      current_path={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages/#{@page.id}"}
      selected_page_id={to_string(@page.id)}
      can_edit={@can_edit}
    >
      <%!-- Breadcrumb (above banner) --%>
      <nav class="text-sm mb-4">
        <ol class="flex flex-wrap items-center gap-1 text-base-content/70">
          <li :for={{ancestor, idx} <- Enum.with_index(@ancestors)} class="flex items-center">
            <.link
              navigate={
                ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages/#{ancestor.id}"
              }
              class="hover:text-primary flex items-center gap-1"
            >
              <.page_avatar avatar_asset={ancestor.avatar_asset} name={ancestor.name} size="sm" />
              {ancestor.name}
            </.link>
            <span :if={idx < length(@ancestors) - 1} class="mx-1 text-base-content/50">/</span>
          </li>
        </ol>
      </nav>

      <%!-- Banner --%>
      <.live_component
        module={Banner}
        id="page-banner"
        page={@page}
        project={@project}
        current_user={@current_scope.user}
        can_edit={@can_edit}
      />

      <%!-- Page Header --%>
      <div class="relative">
        <div class="max-w-3xl mx-auto">
          <div class="flex items-start gap-4 mb-8">
            <%!-- Avatar with edit options --%>
            <.live_component
              module={PageAvatar}
              id="page-avatar"
              page={@page}
              project={@project}
              current_user={@current_scope.user}
              can_edit={@can_edit}
            />
            <div class="flex-1">
              <.live_component
                module={PageTitle}
                id="page-title"
                page={@page}
                project={@project}
                current_user_id={@current_scope.user.id}
                can_edit={@can_edit}
              />
              <.live_component
                module={PageColor}
                id="page-color"
                page={@page}
                can_edit={@can_edit}
              />
            </div>
          </div>
        </div>
        <%!-- Save indicator (positioned at header level) --%>
        <.save_indicator status={@save_status} variant={:floating} />
      </div>

      <div class="max-w-3xl mx-auto">
        <%!-- Tabs Navigation --%>
        <div role="tablist" class="tabs tabs-border mb-6">
          <button
            role="tab"
            class={["tab", @current_tab == "content" && "tab-active"]}
            phx-click="switch_tab"
            phx-value-tab="content"
          >
            <.icon name="file-text" class="size-4 mr-2" />
            {gettext("Content")}
          </button>
          <button
            role="tab"
            class={["tab", @current_tab == "references" && "tab-active"]}
            phx-click="switch_tab"
            phx-value-tab="references"
          >
            <.icon name="link" class="size-4 mr-2" />
            {gettext("References")}
          </button>
        </div>

        <%!-- Tab Content: Content (LiveComponent) --%>
        <.live_component
          :if={@current_tab == "content"}
          module={ContentTab}
          id="content-tab"
          workspace={@workspace}
          project={@project}
          page={@page}
          blocks={@blocks}
          children={@children}
          can_edit={@can_edit}
          current_user_id={@current_scope.user.id}
        />

        <%!-- Tab Content: References (LiveComponent) --%>
        <.live_component
          :if={@current_tab == "references"}
          module={ReferencesTab}
          id="references-tab"
          project={@project}
          page={@page}
          can_edit={@can_edit}
          current_user_id={@current_scope.user.id}
        />
      </div>
    </Layouts.project>
    """
  end

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug, "id" => page_id},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        mount_with_project(socket, workspace_slug, project_slug, page_id, project, membership)

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  defp mount_with_project(socket, workspace_slug, project_slug, page_id, project, membership) do
    case Pages.get_page(project.id, page_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Page not found."))
         |> redirect(to: ~p"/workspaces/#{workspace_slug}/projects/#{project_slug}/pages")}

      page ->
        {:ok, setup_page_view(socket, project, membership, page)}
    end
  end

  defp setup_page_view(socket, project, membership, page) do
    project = Repo.preload(project, :workspace)
    page = Repo.preload(page, [:avatar_asset, :banner_asset, :current_version])
    pages_tree = Pages.list_pages_tree(project.id)
    ancestors = Pages.get_page_with_ancestors(project.id, page.id) || [page]
    children = Pages.get_children(page.id)
    blocks = ReferenceHelpers.load_blocks_with_references(page.id, project.id)
    can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)

    socket
    |> assign(:project, project)
    |> assign(:workspace, project.workspace)
    |> assign(:membership, membership)
    |> assign(:page, page)
    |> assign(:pages_tree, pages_tree)
    |> assign(:ancestors, ancestors)
    |> assign(:children, children)
    |> assign(:blocks, blocks)
    |> assign(:can_edit, can_edit)
    |> assign(:save_status, :idle)
    |> assign(:current_tab, "content")
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  # ===========================================================================
  # Event Handlers: Tabs
  # ===========================================================================

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in ["content", "references"] do
    {:noreply, assign(socket, :current_tab, tab)}
  end

  # ===========================================================================
  # Event Handlers: Page Tree
  # ===========================================================================

  def handle_event("delete_page", %{"id" => page_id}, socket) do
    with_authorization(socket, :edit_content, &PageTreeHelpers.delete_page(&1, page_id))
  end

  def handle_event(
        "move_page",
        %{"page_id" => page_id, "parent_id" => parent_id, "position" => position},
        socket
      ) do
    with_authorization(
      socket,
      :edit_content,
      &PageTreeHelpers.move_page(&1, page_id, parent_id, position)
    )
  end

  def handle_event("create_child_page", %{"parent-id" => parent_id}, socket) do
    with_authorization(socket, :edit_content, &PageTreeHelpers.create_child_page(&1, parent_id))
  end

  def handle_event("create_page", _params, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      attrs = %{name: gettext("Untitled")}

      case Pages.create_page(socket.assigns.project, attrs) do
        {:ok, new_page} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/pages/#{new_page.id}"
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, gettext("Could not create page."))}
      end
    end)
  end

  # ===========================================================================
  # Handle Info
  # ===========================================================================

  @impl true
  def handle_info(:reset_save_status, socket) do
    {:noreply, assign(socket, :save_status, :idle)}
  end

  # Handle messages from ContentTab LiveComponent
  def handle_info({:content_tab, :saved}, socket) do
    {:noreply,
     socket
     |> assign(:save_status, :saved)
     |> schedule_save_status_reset()}
  end

  # Handle messages from VersionsSection LiveComponent
  def handle_info({:versions_section, :saved}, socket) do
    {:noreply,
     socket
     |> assign(:save_status, :saved)
     |> schedule_save_status_reset()}
  end

  def handle_info({:versions_section, :page_updated, page}, socket) do
    {:noreply, assign(socket, :page, page)}
  end

  def handle_info({:versions_section, :version_restored, %{page: page}}, socket) do
    # Reload blocks and pages tree after version restore
    blocks = ReferenceHelpers.load_blocks_with_references(page.id, socket.assigns.project.id)
    pages_tree = Pages.list_pages_tree(socket.assigns.project.id)

    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:blocks, blocks)
     |> assign(:pages_tree, pages_tree)
     |> assign(:save_status, :saved)
     |> schedule_save_status_reset()}
  end

  # Handle messages from Banner LiveComponent
  def handle_info({:banner, :page_updated, page}, socket) do
    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:save_status, :saved)
     |> schedule_save_status_reset()}
  end

  def handle_info({:banner, :error, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  # Handle messages from PageAvatar LiveComponent
  def handle_info({:page_avatar, :page_updated, page, pages_tree}, socket) do
    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:pages_tree, pages_tree)
     |> assign(:save_status, :saved)
     |> schedule_save_status_reset()}
  end

  def handle_info({:page_avatar, :error, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  # Handle messages from PageTitle LiveComponent
  def handle_info({:page_title, :name_saved, page, pages_tree}, socket) do
    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:pages_tree, pages_tree)
     |> assign(:save_status, :saved)
     |> schedule_save_status_reset()}
  end

  def handle_info({:page_title, :shortcut_saved, page}, socket) do
    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:save_status, :saved)
     |> schedule_save_status_reset()}
  end

  def handle_info({:page_title, :error, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  # Handle messages from PageColor LiveComponent
  def handle_info({:page_color, :page_updated, page}, socket) do
    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:save_status, :saved)
     |> schedule_save_status_reset()}
  end

  def handle_info({:page_color, :error, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp schedule_save_status_reset(socket) do
    Process.send_after(self(), :reset_save_status, 4000)
    socket
  end
end
