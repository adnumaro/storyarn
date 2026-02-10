defmodule StoryarnWeb.SheetLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Components.SheetComponents
  import StoryarnWeb.Components.SaveIndicator

  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Components.Banner
  alias StoryarnWeb.SheetLive.Components.ContentTab
  alias StoryarnWeb.SheetLive.Components.HistoryTab
  alias StoryarnWeb.SheetLive.Components.ReferencesTab
  alias StoryarnWeb.SheetLive.Components.SheetAvatar
  alias StoryarnWeb.SheetLive.Components.SheetTitle
  alias StoryarnWeb.SheetLive.Helpers.ReferenceHelpers
  alias StoryarnWeb.SheetLive.Helpers.SheetTreeHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.project
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      sheets_tree={@sheets_tree}
      current_path={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets/#{@sheet.id}"}
      selected_sheet_id={to_string(@sheet.id)}
      can_edit={@can_edit}
    >
      <%!-- Breadcrumb (above banner) --%>
      <nav class="text-sm mb-4">
        <ol class="flex flex-wrap items-center gap-1 text-base-content/70">
          <li :for={{ancestor, idx} <- Enum.with_index(@ancestors)} class="flex items-center">
            <.link
              navigate={
                ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets/#{ancestor.id}"
              }
              class="hover:text-primary flex items-center gap-1"
            >
              <.sheet_avatar avatar_asset={ancestor.avatar_asset} name={ancestor.name} size="sm" />
              {ancestor.name}
            </.link>
            <span :if={idx < length(@ancestors) - 1} class="mx-1 text-base-content/50">/</span>
          </li>
        </ol>
      </nav>

      <%!-- Banner --%>
      <.live_component
        module={Banner}
        id="sheet-banner"
        sheet={@sheet}
        project={@project}
        current_user={@current_scope.user}
        can_edit={@can_edit}
      />

      <%!-- Sheet Header --%>
      <div class="relative">
        <div class="max-w-3xl mx-auto">
          <div class="flex items-start gap-4 mb-8">
            <%!-- Avatar with edit options --%>
            <.live_component
              module={SheetAvatar}
              id="sheet-avatar"
              sheet={@sheet}
              project={@project}
              current_user={@current_scope.user}
              can_edit={@can_edit}
            />
            <div class="flex-1">
              <.live_component
                module={SheetTitle}
                id="sheet-title"
                sheet={@sheet}
                project={@project}
                current_user_id={@current_scope.user.id}
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
          <button
            role="tab"
            class={["tab", @current_tab == "history" && "tab-active"]}
            phx-click="switch_tab"
            phx-value-tab="history"
          >
            <.icon name="clock" class="size-4 mr-2" />
            {gettext("History")}
          </button>
        </div>

        <%!-- Tab Content: Content (LiveComponent) --%>
        <.live_component
          :if={@current_tab == "content"}
          module={ContentTab}
          id="content-tab"
          workspace={@workspace}
          project={@project}
          sheet={@sheet}
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
          sheet={@sheet}
          blocks={@blocks}
        />

        <%!-- Tab Content: History (LiveComponent) --%>
        <.live_component
          :if={@current_tab == "history"}
          module={HistoryTab}
          id="history-tab"
          project={@project}
          sheet={@sheet}
          can_edit={@can_edit}
          current_user_id={@current_scope.user.id}
        />
      </div>
    </Layouts.project>
    """
  end

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug, "id" => sheet_id},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        mount_with_project(socket, workspace_slug, project_slug, sheet_id, project, membership)

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  defp mount_with_project(socket, workspace_slug, project_slug, sheet_id, project, membership) do
    case Sheets.get_sheet(project.id, sheet_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Sheet not found."))
         |> redirect(to: ~p"/workspaces/#{workspace_slug}/projects/#{project_slug}/sheets")}

      sheet ->
        {:ok, setup_sheet_view(socket, project, membership, sheet)}
    end
  end

  defp setup_sheet_view(socket, project, membership, sheet) do
    project = Repo.preload(project, :workspace)
    sheet = Repo.preload(sheet, [:avatar_asset, :banner_asset, :current_version])
    sheets_tree = Sheets.list_sheets_tree(project.id)
    ancestors = Sheets.get_sheet_with_ancestors(project.id, sheet.id) || [sheet]
    children = Sheets.get_children(sheet.id)
    blocks = ReferenceHelpers.load_blocks_with_references(sheet.id, project.id)
    can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)

    socket
    |> assign(:project, project)
    |> assign(:workspace, project.workspace)
    |> assign(:membership, membership)
    |> assign(:sheet, sheet)
    |> assign(:sheets_tree, sheets_tree)
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
  def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in ["content", "references", "history"] do
    {:noreply, assign(socket, :current_tab, tab)}
  end

  # ===========================================================================
  # Event Handlers: Sheet Tree
  # ===========================================================================

  def handle_event("delete_sheet", %{"id" => sheet_id}, socket) do
    with_authorization(socket, :edit_content, &SheetTreeHelpers.delete_sheet(&1, sheet_id))
  end

  def handle_event(
        "move_sheet",
        %{"sheet_id" => sheet_id, "parent_id" => parent_id, "position" => position},
        socket
      ) do
    with_authorization(
      socket,
      :edit_content,
      &SheetTreeHelpers.move_sheet(&1, sheet_id, parent_id, position)
    )
  end

  def handle_event("create_child_sheet", %{"parent-id" => parent_id}, socket) do
    with_authorization(socket, :edit_content, &SheetTreeHelpers.create_child_sheet(&1, parent_id))
  end

  def handle_event("create_sheet", _params, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      attrs = %{name: gettext("Untitled")}

      case Sheets.create_sheet(socket.assigns.project, attrs) do
        {:ok, new_sheet} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/sheets/#{new_sheet.id}"
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, gettext("Could not create sheet."))}
      end
    end)
  end

  # Sheet color (from ColorPicker hook — pushes to parent LV, not LiveComponent)
  def handle_event("set_sheet_color", %{"color" => color}, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      update_sheet_color(socket, color)
    end)
  end

  def handle_event("clear_sheet_color", _params, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      update_sheet_color(socket, nil)
    end)
  end

  defp update_sheet_color(socket, color) do
    sheet = socket.assigns.sheet

    case Sheets.update_sheet(sheet, %{color: color}) do
      {:ok, updated_sheet} ->
        updated_sheet =
          Repo.preload(updated_sheet, [:avatar_asset, :banner_asset, :current_version],
            force: true
          )

        {:noreply,
         socket
         |> assign(:sheet, updated_sheet)
         |> assign(:save_status, :saved)
         |> schedule_save_status_reset()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update color."))}
    end
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

  def handle_info({:versions_section, :sheet_updated, sheet}, socket) do
    {:noreply, assign(socket, :sheet, sheet)}
  end

  def handle_info({:versions_section, :version_restored, %{sheet: sheet}}, socket) do
    # Reload blocks and sheets tree after version restore
    blocks = ReferenceHelpers.load_blocks_with_references(sheet.id, socket.assigns.project.id)
    sheets_tree = Sheets.list_sheets_tree(socket.assigns.project.id)

    {:noreply,
     socket
     |> assign(:sheet, sheet)
     |> assign(:blocks, blocks)
     |> assign(:sheets_tree, sheets_tree)
     |> assign(:save_status, :saved)
     |> schedule_save_status_reset()}
  end

  # Handle messages from Banner LiveComponent
  def handle_info({:banner, :sheet_updated, sheet}, socket) do
    {:noreply,
     socket
     |> assign(:sheet, sheet)
     |> assign(:save_status, :saved)
     |> schedule_save_status_reset()}
  end

  def handle_info({:banner, :error, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  # Handle messages from SheetAvatar LiveComponent
  def handle_info({:sheet_avatar, :sheet_updated, sheet, sheets_tree}, socket) do
    {:noreply,
     socket
     |> assign(:sheet, sheet)
     |> assign(:sheets_tree, sheets_tree)
     |> assign(:save_status, :saved)
     |> schedule_save_status_reset()}
  end

  def handle_info({:sheet_avatar, :error, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  # Handle messages from SheetTitle LiveComponent
  def handle_info({:sheet_title, :name_saved, sheet, sheets_tree}, socket) do
    {:noreply,
     socket
     |> assign(:sheet, sheet)
     |> assign(:sheets_tree, sheets_tree)
     |> assign(:save_status, :saved)
     |> schedule_save_status_reset()}
  end

  def handle_info({:sheet_title, :shortcut_saved, sheet}, socket) do
    {:noreply,
     socket
     |> assign(:sheet, sheet)
     |> assign(:save_status, :saved)
     |> schedule_save_status_reset()}
  end

  def handle_info({:sheet_title, :error, message}, socket) do
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
