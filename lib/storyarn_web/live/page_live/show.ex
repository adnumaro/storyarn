defmodule StoryarnWeb.PageLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.LiveHelpers.Authorize

  import StoryarnWeb.Components.BlockComponents
  import StoryarnWeb.Components.PageComponents
  import StoryarnWeb.Components.SaveIndicator

  alias Storyarn.Assets
  alias Storyarn.Pages
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias StoryarnWeb.PageLive.Helpers.BlockHelpers
  alias StoryarnWeb.PageLive.Helpers.ConfigHelpers
  alias StoryarnWeb.PageLive.Helpers.PageTreeHelpers

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
      <div class={[!@page.banner_asset && !@can_edit && "hidden"]}>
        <%= if @page.banner_asset do %>
          <div class="relative group h-48 sm:h-56 lg:h-64 overflow-hidden rounded-2xl mb-6">
            <img
              src={@page.banner_asset.url}
              alt=""
              class="w-full h-full object-cover"
            />
            <div
              :if={@can_edit}
              class="absolute inset-0 bg-black/0 group-hover:bg-black/30 transition-colors flex items-center justify-center opacity-0 group-hover:opacity-100"
            >
              <div class="flex gap-2">
                <label class="btn btn-sm btn-ghost bg-base-100/80 hover:bg-base-100">
                  <.icon name="image" class="size-4" />
                  {gettext("Change")}
                  <input
                    type="file"
                    accept="image/*"
                    class="hidden"
                    phx-hook="BannerUpload"
                    id="banner-upload-input"
                    data-page-id={@page.id}
                  />
                </label>
                <button
                  type="button"
                  class="btn btn-sm btn-ghost bg-base-100/80 hover:bg-base-100"
                  phx-click="remove_banner"
                >
                  <.icon name="trash-2" class="size-4" />
                  {gettext("Remove")}
                </button>
              </div>
            </div>
          </div>
        <% else %>
          <div :if={@can_edit} class="flex items-center mb-4">
            <label class="btn btn-ghost btn-sm text-base-content/50 hover:text-base-content">
              <.icon name="image" class="size-4" />
              {gettext("Add cover")}
              <input
                type="file"
                accept="image/*"
                class="hidden"
                phx-hook="BannerUpload"
                id="banner-upload-input-empty"
                data-page-id={@page.id}
              />
            </label>
          </div>
        <% end %>
      </div>

      <%!-- Page Header --%>
      <div class="relative">
        <div class="max-w-3xl mx-auto">
          <div class="flex items-start gap-4 mb-8">
            <%!-- Avatar with edit options --%>
            <div :if={@can_edit} class="relative group">
              <div class="dropdown">
                <div tabindex="0" role="button" class="cursor-pointer">
                  <.page_avatar avatar_asset={@page.avatar_asset} name={@page.name} size="xl" />
                  <div class="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 rounded flex items-center justify-center transition-opacity">
                    <.icon name="camera" class="size-4 text-white" />
                  </div>
                </div>
                <ul
                  tabindex="0"
                  class="dropdown-content menu menu-sm bg-base-100 rounded-box shadow-lg border border-base-300 w-40 z-50"
                >
                  <li>
                    <label class="cursor-pointer">
                      <.icon name="upload" class="size-4" />
                      {gettext("Upload avatar")}
                      <input
                        type="file"
                        accept="image/*"
                        class="hidden"
                        phx-hook="AvatarUpload"
                        id="avatar-upload-input"
                        data-page-id={@page.id}
                      />
                    </label>
                  </li>
                  <li :if={@page.avatar_asset}>
                    <button type="button" class="text-error" phx-click="remove_avatar">
                      <.icon name="trash-2" class="size-4" />
                      {gettext("Remove")}
                    </button>
                  </li>
                </ul>
              </div>
            </div>
            <.page_avatar
              :if={!@can_edit}
              avatar_asset={@page.avatar_asset}
              name={@page.name}
              size="xl"
            />
            <div class="flex-1">
              <h1
                :if={@can_edit}
                id="page-title"
                class="text-3xl font-bold outline-none rounded px-2 -mx-2 py-1 empty:before:content-[attr(data-placeholder)] empty:before:text-base-content/30"
                contenteditable="true"
                phx-hook="EditableTitle"
                phx-update="ignore"
                data-placeholder={gettext("Untitled")}
                data-name={@page.name}
              >
                {@page.name}
              </h1>
              <h1 :if={!@can_edit} class="text-3xl font-bold px-2 -mx-2 py-1">
                {@page.name}
              </h1>
              <%!-- Shortcut --%>
              <div :if={@can_edit} class="flex items-center gap-1 px-2 -mx-2 mt-1">
                <span class="text-base-content/50">#</span>
                <span
                  id="page-shortcut"
                  class="text-sm text-base-content/50 outline-none hover:text-base-content empty:before:content-[attr(data-placeholder)] empty:before:text-base-content/30"
                  contenteditable="true"
                  phx-hook="EditableShortcut"
                  phx-update="ignore"
                  data-placeholder={gettext("add-shortcut")}
                  data-shortcut={@page.shortcut || ""}
                >
                  {@page.shortcut}
                </span>
              </div>
              <div :if={!@can_edit && @page.shortcut} class="text-sm text-base-content/50 px-2 -mx-2 mt-1">
                #{@page.shortcut}
              </div>
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

        <%!-- Tab Content: Content --%>
        <div :if={@current_tab == "content"}>
          <%!-- Blocks --%>
          <div
            id="blocks-container"
            class="flex flex-col gap-2 -mx-2 sm:-mx-8 md:-mx-16"
            phx-hook={if @can_edit, do: "SortableList", else: nil}
            data-group="blocks"
            data-handle=".drag-handle"
          >
            <div
              :for={block <- @blocks}
              class="group relative w-full px-2 sm:px-8 md:px-16"
              id={"block-#{block.id}"}
              data-id={block.id}
            >
              <.block_component
                block={block}
                can_edit={@can_edit}
                editing_block_id={@editing_block_id}
              />
            </div>
          </div>

          <%!-- Add block button / slash command (outside sortable container) --%>
          <div :if={@can_edit} class="relative mt-2">
            <div
              :if={!@show_block_menu}
              class="flex items-center gap-2 py-2 text-base-content/50 hover:text-base-content cursor-pointer group"
              phx-click="show_block_menu"
            >
              <.icon name="plus" class="size-4 opacity-0 group-hover:opacity-100" />
              <span class="text-sm">{gettext("Type / to add a block")}</span>
            </div>

            <.block_menu :if={@show_block_menu} />
          </div>

          <%!-- Children pages --%>
          <div :if={@children != []} class="mt-12 pt-8 border-t border-base-300">
            <h2 class="text-lg font-semibold mb-4">{gettext("Subpages")}</h2>
            <div class="space-y-2">
              <.link
                :for={child <- @children}
                navigate={
                  ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages/#{child.id}"
                }
                class="flex items-center gap-2 p-2 rounded hover:bg-base-200"
              >
                <.page_avatar avatar_asset={child.avatar_asset} name={child.name} size="md" />
                <span>{child.name}</span>
              </.link>
            </div>
          </div>
        </div>

        <%!-- Tab Content: References --%>
        <div :if={@current_tab == "references"}>
          <.references_tab_placeholder />
        </div>
      </div>

      <%!-- Configuration Panel (Right Sidebar) --%>
      <.config_panel :if={@configuring_block} block={@configuring_block} />
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
    pages_tree = Pages.list_pages_tree(project.id)
    ancestors = Pages.get_page_with_ancestors(project.id, page.id) || [page]
    children = Pages.get_children(page.id)
    blocks = Pages.list_blocks(page.id)
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
    |> assign(:editing_block_id, nil)
    |> assign(:show_block_menu, false)
    |> assign(:save_status, :idle)
    |> assign(:configuring_block, nil)
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
  # Event Handlers: Name Editing
  # ===========================================================================

  def handle_event("save_name", %{"name" => name}, socket) do
    with_authorization(socket, :edit_content, &PageTreeHelpers.save_name(&1, name))
  end

  def handle_event("save_shortcut", %{"shortcut" => shortcut}, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      page = socket.assigns.page
      # Convert empty string to nil
      shortcut = if shortcut == "", do: nil, else: shortcut

      case Pages.update_page(page, %{shortcut: shortcut}) do
        {:ok, updated_page} ->
          updated_page = Repo.preload(updated_page, [:avatar_asset, :banner_asset])

          {:noreply,
           socket
           |> assign(:page, updated_page)
           |> assign(:save_status, :saved)
           |> schedule_save_status_reset()}

        {:error, changeset} ->
          error_msg = format_shortcut_error(changeset)
          {:noreply, put_flash(socket, :error, error_msg)}
      end
    end)
  end

  # ===========================================================================
  # Event Handlers: Avatar
  # ===========================================================================

  def handle_event("remove_avatar", _params, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      page = socket.assigns.page

      case Pages.update_page(page, %{avatar_asset_id: nil}) do
        {:ok, updated_page} ->
          updated_page = Repo.preload(updated_page, :avatar_asset)
          pages_tree = Pages.list_pages_tree(socket.assigns.project.id)

          {:noreply,
           socket
           |> assign(:page, updated_page)
           |> assign(:pages_tree, pages_tree)
           |> assign(:save_status, :saved)
           |> schedule_save_status_reset()}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, gettext("Could not remove avatar."))}
      end
    end)
  end

  def handle_event("set_avatar", %{"asset_id" => asset_id}, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      page = socket.assigns.page

      case Pages.update_page(page, %{avatar_asset_id: asset_id}) do
        {:ok, updated_page} ->
          updated_page = Repo.preload(updated_page, :avatar_asset)
          pages_tree = Pages.list_pages_tree(socket.assigns.project.id)

          {:noreply,
           socket
           |> assign(:page, updated_page)
           |> assign(:pages_tree, pages_tree)
           |> assign(:save_status, :saved)
           |> schedule_save_status_reset()}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, gettext("Could not set avatar."))}
      end
    end)
  end

  def handle_event(
        "upload_avatar",
        %{"filename" => filename, "content_type" => content_type, "data" => data},
        socket
      ) do
    with_authorization(socket, :edit_content, fn socket ->
      # Extract binary data from base64 data URL
      [_header, base64_data] = String.split(data, ",", parts: 2)

      case Base.decode64(base64_data) do
        {:ok, binary_data} ->
          upload_avatar_file(socket, filename, content_type, binary_data)

        :error ->
          {:noreply, put_flash(socket, :error, gettext("Invalid file data."))}
      end
    end)
  end

  # ===========================================================================
  # Event Handlers: Banner
  # ===========================================================================

  def handle_event("remove_banner", _params, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      page = socket.assigns.page

      case Pages.update_page(page, %{banner_asset_id: nil}) do
        {:ok, updated_page} ->
          updated_page = Repo.preload(updated_page, [:avatar_asset, :banner_asset])

          {:noreply,
           socket
           |> assign(:page, updated_page)
           |> assign(:save_status, :saved)
           |> schedule_save_status_reset()}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, gettext("Could not remove banner."))}
      end
    end)
  end

  def handle_event(
        "upload_banner",
        %{"filename" => filename, "content_type" => content_type, "data" => data},
        socket
      ) do
    with_authorization(socket, :edit_content, fn socket ->
      # Extract binary data from base64 data URL
      [_header, base64_data] = String.split(data, ",", parts: 2)

      case Base.decode64(base64_data) do
        {:ok, binary_data} ->
          upload_banner_file(socket, filename, content_type, binary_data)

        :error ->
          {:noreply, put_flash(socket, :error, gettext("Invalid file data."))}
      end
    end)
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

  # ===========================================================================
  # Event Handlers: Block Menu
  # ===========================================================================

  def handle_event("show_block_menu", _params, socket) do
    {:noreply, assign(socket, :show_block_menu, true)}
  end

  def handle_event("hide_block_menu", _params, socket) do
    {:noreply, assign(socket, :show_block_menu, false)}
  end

  # ===========================================================================
  # Event Handlers: Blocks
  # ===========================================================================

  def handle_event("add_block", %{"type" => type}, socket) do
    with_authorization(socket, :edit_content, &BlockHelpers.add_block(&1, type))
  end

  def handle_event("update_block_value", %{"id" => block_id, "value" => value}, socket) do
    with_authorization(
      socket,
      :edit_content,
      &BlockHelpers.update_block_value(&1, block_id, value)
    )
  end

  def handle_event("delete_block", %{"id" => block_id}, socket) do
    with_authorization(socket, :edit_content, &BlockHelpers.delete_block(&1, block_id))
  end

  def handle_event("reorder", %{"ids" => ids, "group" => "blocks"}, socket) do
    with_authorization(socket, :edit_content, &BlockHelpers.reorder_blocks(&1, ids))
  end

  def handle_event("toggle_multi_select", %{"id" => block_id, "key" => key}, socket) do
    with_authorization(
      socket,
      :edit_content,
      &BlockHelpers.toggle_multi_select(&1, block_id, key)
    )
  end

  def handle_event(
        "multi_select_keydown",
        %{"key" => "Enter", "value" => value, "id" => block_id},
        socket
      ) do
    with_authorization(
      socket,
      :edit_content,
      &BlockHelpers.handle_multi_select_enter(&1, block_id, value)
    )
  end

  def handle_event("multi_select_keydown", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("update_rich_text", %{"id" => block_id, "content" => content}, socket) do
    with_authorization(
      socket,
      :edit_content,
      &BlockHelpers.update_rich_text(&1, block_id, content)
    )
  end

  def handle_event("set_boolean_block", %{"id" => block_id, "value" => value}, socket) do
    with_authorization(
      socket,
      :edit_content,
      &BlockHelpers.set_boolean_block(&1, block_id, value)
    )
  end

  # ===========================================================================
  # Event Handlers: Configuration Panel
  # ===========================================================================

  def handle_event("configure_block", %{"id" => block_id}, socket) do
    with_authorization(socket, :edit_content, &ConfigHelpers.configure_block(&1, block_id))
  end

  def handle_event("close_config_panel", _params, socket) do
    ConfigHelpers.close_config_panel(socket)
  end

  def handle_event("save_block_config", %{"config" => config_params}, socket) do
    with_authorization(socket, :edit_content, &ConfigHelpers.save_block_config(&1, config_params))
  end

  def handle_event("toggle_constant", _params, socket) do
    with_authorization(socket, :edit_content, &ConfigHelpers.toggle_constant/1)
  end

  def handle_event("add_select_option", _params, socket) do
    ConfigHelpers.add_select_option(socket)
  end

  def handle_event("remove_select_option", %{"index" => index}, socket) do
    ConfigHelpers.remove_select_option(socket, index)
  end

  def handle_event(
        "update_select_option",
        %{"index" => index, "key" => key, "value" => value},
        socket
      ) do
    ConfigHelpers.update_select_option(socket, index, key, value)
  end

  # ===========================================================================
  # Handle Info
  # ===========================================================================

  @impl true
  def handle_info(:reset_save_status, socket) do
    {:noreply, assign(socket, :save_status, :idle)}
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp upload_avatar_file(socket, filename, content_type, binary_data) do
    project = socket.assigns.project
    user = socket.assigns.current_scope.user
    page = socket.assigns.page
    key = Assets.generate_key(project, filename)

    asset_attrs = %{
      filename: filename,
      content_type: content_type,
      size: byte_size(binary_data),
      key: key
    }

    with {:ok, url} <- Assets.Storage.upload(key, binary_data, content_type),
         {:ok, asset} <- Assets.create_asset(project, user, Map.put(asset_attrs, :url, url)),
         {:ok, updated_page} <- Pages.update_page(page, %{avatar_asset_id: asset.id}) do
      updated_page = Repo.preload(updated_page, :avatar_asset)
      pages_tree = Pages.list_pages_tree(project.id)

      {:noreply,
       socket
       |> assign(:page, updated_page)
       |> assign(:pages_tree, pages_tree)
       |> assign(:save_status, :saved)
       |> schedule_save_status_reset()}
    else
      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not upload avatar."))}
    end
  end

  defp upload_banner_file(socket, filename, content_type, binary_data) do
    project = socket.assigns.project
    user = socket.assigns.current_scope.user
    page = socket.assigns.page
    key = Assets.generate_key(project, filename)

    asset_attrs = %{
      filename: filename,
      content_type: content_type,
      size: byte_size(binary_data),
      key: key
    }

    with {:ok, url} <- Assets.Storage.upload(key, binary_data, content_type),
         {:ok, asset} <- Assets.create_asset(project, user, Map.put(asset_attrs, :url, url)),
         {:ok, updated_page} <- Pages.update_page(page, %{banner_asset_id: asset.id}) do
      updated_page = Repo.preload(updated_page, [:avatar_asset, :banner_asset])

      {:noreply,
       socket
       |> assign(:page, updated_page)
       |> assign(:save_status, :saved)
       |> schedule_save_status_reset()}
    else
      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not upload banner."))}
    end
  end

  defp format_shortcut_error(changeset) do
    case changeset.errors[:shortcut] do
      {msg, _opts} -> gettext("Shortcut %{error}", error: msg)
      nil -> gettext("Could not save shortcut.")
    end
  end

  defp schedule_save_status_reset(socket) do
    Process.send_after(self(), :reset_save_status, 4000)
    socket
  end

  # ===========================================================================
  # Components
  # ===========================================================================

  defp references_tab_placeholder(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Backlinks Section --%>
      <section>
        <h2 class="text-lg font-semibold mb-4 flex items-center gap-2">
          <.icon name="arrow-left" class="size-5" />
          {gettext("Backlinks")}
        </h2>
        <div class="bg-base-200/50 rounded-lg p-8 text-center">
          <.icon name="link" class="size-12 mx-auto text-base-content/30 mb-4" />
          <p class="text-base-content/70 mb-2">{gettext("No backlinks yet")}</p>
          <p class="text-sm text-base-content/50">
            {gettext("Pages and flows that reference this page will appear here.")}
          </p>
        </div>
      </section>

      <%!-- Version History Section --%>
      <section>
        <h2 class="text-lg font-semibold mb-4 flex items-center gap-2">
          <.icon name="history" class="size-5" />
          {gettext("Version History")}
        </h2>
        <div class="bg-base-200/50 rounded-lg p-8 text-center">
          <.icon name="clock" class="size-12 mx-auto text-base-content/30 mb-4" />
          <p class="text-base-content/70 mb-2">{gettext("No versions yet")}</p>
          <p class="text-sm text-base-content/50">
            {gettext("Page versions will be recorded automatically as you make changes.")}
          </p>
        </div>
      </section>
    </div>
    """
  end
end
