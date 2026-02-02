defmodule StoryarnWeb.PageLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.LiveHelpers.Authorize

  import StoryarnWeb.Components.BlockComponents
  import StoryarnWeb.Components.PageComponents
  import StoryarnWeb.Components.SaveIndicator

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
      current_path={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages/#{@page.id}"}
      selected_page_id={to_string(@page.id)}
      can_edit={@can_edit}
    >
      <%!-- Breadcrumb --%>
      <nav class="text-sm mb-4">
        <ol class="flex flex-wrap items-center gap-1 text-base-content/70">
          <li :for={{ancestor, idx} <- Enum.with_index(@ancestors)} class="flex items-center">
            <.link
              navigate={
                ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages/#{ancestor.id}"
              }
              class="hover:text-primary flex items-center gap-1"
            >
              <.page_icon icon={ancestor.icon} size="sm" />
              {ancestor.name}
            </.link>
            <span :if={idx < length(@ancestors) - 1} class="mx-1 text-base-content/50">/</span>
          </li>
        </ol>
      </nav>

      <%!-- Page Header --%>
      <div class="relative">
        <div class="max-w-3xl mx-auto">
          <div class="flex items-start gap-4 mb-8">
            <.page_icon icon={@page.icon} size="xl" />
            <div class="flex-1">
              <h1
                :if={!@editing_name}
                class="text-3xl font-bold cursor-pointer hover:bg-base-200 rounded px-2 -mx-2 py-1"
                phx-click="edit_name"
              >
                {@page.name}
              </h1>
              <form :if={@editing_name} phx-submit="save_name" phx-click-away="cancel_edit_name">
                <input
                  type="text"
                  name="name"
                  value={@page.name}
                  class="input input-bordered text-3xl font-bold w-full"
                  autofocus
                  phx-key="escape"
                  phx-keydown="cancel_edit_name"
                />
              </form>
            </div>
          </div>
        </div>
        <%!-- Save indicator (positioned at header level) --%>
        <.save_indicator status={@save_status} variant={:floating} />
      </div>

      <div class="max-w-3xl mx-auto">
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
              <.page_icon icon={child.icon} size="md" />
              <span>{child.name}</span>
            </.link>
          </div>
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
        case Pages.get_page(project.id, page_id) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, gettext("Page not found."))
             |> redirect(to: ~p"/workspaces/#{workspace_slug}/projects/#{project_slug}/pages")}

          page ->
            project = Repo.preload(project, :workspace)
            pages_tree = Pages.list_pages_tree(project.id)
            ancestors = Pages.get_page_with_ancestors(project.id, page_id) || [page]
            children = Pages.get_children(page.id)
            blocks = Pages.list_blocks(page.id)
            can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)

            socket =
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
              |> assign(:editing_name, false)
              |> assign(:editing_block_id, nil)
              |> assign(:show_block_menu, false)
              |> assign(:save_status, :idle)
              |> assign(:configuring_block, nil)

            {:ok, socket}
        end

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
  def handle_event("edit_name", _params, socket) do
    if socket.assigns.can_edit do
      {:noreply, assign(socket, :editing_name, true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_edit_name", _params, socket) do
    {:noreply, assign(socket, :editing_name, false)}
  end

  def handle_event("save_name", %{"name" => name}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Pages.update_page(socket.assigns.page, %{name: name}) do
          {:ok, page} ->
            pages_tree = Pages.list_pages_tree(socket.assigns.project.id)

            {:noreply,
             socket
             |> assign(:page, page)
             |> assign(:pages_tree, pages_tree)
             |> assign(:editing_name, false)}

          {:error, _changeset} ->
            {:noreply, assign(socket, :editing_name, false)}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("delete_page", %{"id" => page_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        page = Pages.get_page!(socket.assigns.project.id, page_id)
        do_delete_page(socket, page)

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("show_block_menu", _params, socket) do
    {:noreply, assign(socket, :show_block_menu, true)}
  end

  def handle_event("hide_block_menu", _params, socket) do
    {:noreply, assign(socket, :show_block_menu, false)}
  end

  def handle_event("add_block", %{"type" => type}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Pages.create_block(socket.assigns.page, %{type: type}) do
          {:ok, _block} ->
            blocks = Pages.list_blocks(socket.assigns.page.id)

            {:noreply,
             socket
             |> assign(:blocks, blocks)
             |> assign(:show_block_menu, false)}

          {:error, _} ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("Could not add block."))
             |> assign(:show_block_menu, false)}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("update_block_value", %{"id" => block_id, "value" => value}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        block = Pages.get_block!(block_id)

        case Pages.update_block_value(block, %{"content" => value}) do
          {:ok, _block} ->
            blocks = Pages.list_blocks(socket.assigns.page.id)
            schedule_save_status_reset()

            {:noreply,
             socket
             |> assign(:blocks, blocks)
             |> assign(:save_status, :saved)}

          {:error, _} ->
            {:noreply, socket}
        end

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_multi_select", %{"id" => block_id, "key" => key}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        block = Pages.get_block!(block_id)
        current = get_in(block.value, ["content"]) || []

        new_content =
          if key in current do
            List.delete(current, key)
          else
            [key | current]
          end

        case Pages.update_block_value(block, %{"content" => new_content}) do
          {:ok, _block} ->
            blocks = Pages.list_blocks(socket.assigns.page.id)
            schedule_save_status_reset()

            {:noreply,
             socket
             |> assign(:blocks, blocks)
             |> assign(:save_status, :saved)}

          {:error, _} ->
            {:noreply, socket}
        end

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
  end

  def handle_event(
        "multi_select_keydown",
        %{"key" => "Enter", "value" => value, "id" => block_id},
        socket
      ) do
    value = String.trim(value)

    if value == "" do
      {:noreply, socket}
    else
      case authorize(socket, :edit_content) do
        :ok ->
          add_multi_select_option(socket, block_id, value)

        {:error, :unauthorized} ->
          {:noreply, socket}
      end
    end
  end

  def handle_event("multi_select_keydown", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("delete_block", %{"id" => block_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        block = Pages.get_block!(block_id)

        case Pages.delete_block(block) do
          {:ok, _} ->
            blocks = Pages.list_blocks(socket.assigns.page.id)

            socket =
              socket
              |> assign(:blocks, blocks)
              |> assign(:configuring_block, nil)

            {:noreply, socket}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not delete block."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("configure_block", %{"id" => block_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        block = Pages.get_block!(block_id)
        {:noreply, assign(socket, :configuring_block, block)}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("close_config_panel", _params, socket) do
    {:noreply, assign(socket, :configuring_block, nil)}
  end

  def handle_event("save_block_config", %{"config" => config_params}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        block = socket.assigns.configuring_block

        # Convert options from indexed map to list
        config_params = normalize_config_params(config_params)

        case Pages.update_block_config(block, config_params) do
          {:ok, updated_block} ->
            blocks = Pages.list_blocks(socket.assigns.page.id)
            schedule_save_status_reset()

            {:noreply,
             socket
             |> assign(:blocks, blocks)
             |> assign(:configuring_block, updated_block)
             |> assign(:save_status, :saved)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not save configuration."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("add_select_option", _params, socket) do
    block = socket.assigns.configuring_block
    options = get_in(block.config, ["options"]) || []
    new_option = %{"key" => "option-#{length(options) + 1}", "value" => ""}
    new_options = options ++ [new_option]

    case Pages.update_block_config(block, %{"options" => new_options}) do
      {:ok, updated_block} ->
        blocks = Pages.list_blocks(socket.assigns.page.id)

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> assign(:configuring_block, updated_block)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_select_option", %{"index" => index}, socket) do
    case parse_index(index) do
      {:ok, idx} ->
        block = socket.assigns.configuring_block
        options = get_in(block.config, ["options"]) || []
        new_options = List.delete_at(options, idx)

        case Pages.update_block_config(block, %{"options" => new_options}) do
          {:ok, updated_block} ->
            blocks = Pages.list_blocks(socket.assigns.page.id)

            {:noreply,
             socket
             |> assign(:blocks, blocks)
             |> assign(:configuring_block, updated_block)}

          {:error, _} ->
            {:noreply, socket}
        end

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event(
        "update_select_option",
        %{"index" => index, "key" => key, "value" => value},
        socket
      ) do
    case parse_index(index) do
      {:ok, idx} ->
        block = socket.assigns.configuring_block
        options = get_in(block.config, ["options"]) || []

        new_options =
          List.update_at(options, idx, fn _opt ->
            %{"key" => key, "value" => value}
          end)

        case Pages.update_block_config(block, %{"options" => new_options}) do
          {:ok, updated_block} ->
            blocks = Pages.list_blocks(socket.assigns.page.id)

            {:noreply,
             socket
             |> assign(:blocks, blocks)
             |> assign(:configuring_block, updated_block)}

          {:error, _} ->
            {:noreply, socket}
        end

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("update_rich_text", %{"id" => block_id, "content" => content}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        block = Pages.get_block!(block_id)

        case Pages.update_block_value(block, %{"content" => content}) do
          {:ok, _block} ->
            # Don't reload blocks to avoid disrupting the editor
            schedule_save_status_reset()
            {:noreply, assign(socket, :save_status, :saved)}

          {:error, _} ->
            {:noreply, socket}
        end

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
  end

  def handle_event("reorder", %{"ids" => ids, "group" => "blocks"}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Pages.reorder_blocks(socket.assigns.page.id, ids) do
          {:ok, blocks} ->
            {:noreply, assign(socket, :blocks, blocks)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not reorder blocks."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event(
        "move_page",
        %{"page_id" => page_id, "parent_id" => parent_id, "position" => position},
        socket
      ) do
    case authorize(socket, :edit_content) do
      :ok ->
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

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("create_child_page", %{"parent-id" => parent_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
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

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  @impl true
  def handle_info(:reset_save_status, socket) do
    {:noreply, assign(socket, :save_status, :idle)}
  end

  defp schedule_save_status_reset do
    Process.send_after(self(), :reset_save_status, 4000)
  end

  defp add_multi_select_option(socket, block_id, value) do
    block = Pages.get_block!(block_id)

    # Generate a unique key from the value
    key = generate_option_key(value)

    # Get current options and content
    current_options = get_in(block.config, ["options"]) || []
    current_content = get_in(block.value, ["content"]) || []

    # Check if option already exists (by key or value)
    existing =
      Enum.find(current_options, fn opt ->
        opt["key"] == key || String.downcase(opt["value"] || "") == String.downcase(value)
      end)

    if existing do
      # Option exists - just select it if not already selected
      if existing["key"] in current_content do
        {:noreply, socket}
      else
        new_content = [existing["key"] | current_content]
        update_multi_select_content(socket, block, new_content)
      end
    else
      # Create new option and select it
      new_option = %{"key" => key, "value" => value}
      new_options = current_options ++ [new_option]
      new_content = [key | current_content]

      # Update both config and value
      with {:ok, _} <-
             Pages.update_block_config(block, %{
               "options" => new_options,
               "label" => block.config["label"] || ""
             }),
           block <- Pages.get_block!(block_id),
           {:ok, _} <- Pages.update_block_value(block, %{"content" => new_content}) do
        blocks = Pages.list_blocks(socket.assigns.page.id)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> assign(:save_status, :saved)}
      else
        _ -> {:noreply, socket}
      end
    end
  end

  defp update_multi_select_content(socket, block, new_content) do
    case Pages.update_block_value(block, %{"content" => new_content}) do
      {:ok, _} ->
        blocks = Pages.list_blocks(socket.assigns.page.id)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> assign(:save_status, :saved)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp generate_option_key(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> then(fn key ->
      if key == "", do: "option-#{:rand.uniform(9999)}", else: key
    end)
  end

  defp do_delete_page(socket, page) do
    case Pages.delete_page(page) do
      {:ok, _} ->
        handle_page_deleted(socket, page)

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete page."))}
    end
  end

  defp handle_page_deleted(socket, deleted_page) do
    socket = put_flash(socket, :info, gettext("Page deleted successfully."))

    if deleted_page.id == socket.assigns.page.id do
      {:noreply,
       push_navigate(socket,
         to:
           ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/pages"
       )}
    else
      pages_tree = Pages.list_pages_tree(socket.assigns.project.id)
      {:noreply, assign(socket, :pages_tree, pages_tree)}
    end
  end

  defp normalize_config_params(params) do
    case Map.get(params, "options") do
      nil ->
        params

      options when is_map(options) ->
        Map.put(params, "options", options_map_to_list(options))

      _ ->
        params
    end
  end

  defp options_map_to_list(options) do
    options
    |> Enum.map(&parse_option_with_index/1)
    |> Enum.sort_by(fn {idx, _} -> idx end)
    |> Enum.map(fn {_, opt} -> opt end)
  end

  defp parse_option_with_index({idx, opt}) do
    case parse_index(idx) do
      {:ok, int} -> {int, opt}
      :error -> {0, opt}
    end
  end

  defp parse_index(index) when is_binary(index) do
    case Integer.parse(index) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_index(index) when is_integer(index), do: {:ok, index}
  defp parse_index(_), do: :error
end
