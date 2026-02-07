defmodule StoryarnWeb.SheetLive.Components.ContentTab do
  @moduledoc """
  LiveComponent for the Content tab in the sheet editor.
  Handles all block-related events: add, update, delete, reorder, configure.
  """

  use StoryarnWeb, :live_component

  import StoryarnWeb.Components.BlockComponents
  import StoryarnWeb.Components.SheetComponents

  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Helpers.BlockHelpers
  alias StoryarnWeb.SheetLive.Helpers.ConfigHelpers
  alias StoryarnWeb.SheetLive.Helpers.ReferenceHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <%!-- Blocks --%>
      <div
        id="blocks-container"
        class="flex flex-col gap-2 -mx-2 sm:-mx-8 md:-mx-16"
        phx-hook={if @can_edit, do: "SortableList", else: nil}
        phx-target={@myself}
        data-phx-target={"##{@id}"}
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
            target={@myself}
          />
        </div>
      </div>

      <%!-- Add block button / slash command --%>
      <div :if={@can_edit} class="relative mt-2">
        <div
          :if={!@show_block_menu}
          class="flex items-center gap-2 py-2 text-base-content/50 hover:text-base-content cursor-pointer group"
          phx-click="show_block_menu"
          phx-target={@myself}
        >
          <.icon name="plus" class="size-4 opacity-0 group-hover:opacity-100" />
          <span class="text-sm">{gettext("Type / to add a block")}</span>
        </div>

        <.block_menu :if={@show_block_menu} target={@myself} />
      </div>

      <%!-- Children sheets --%>
      <.children_sheets_section
        :if={@children != []}
        children={@children}
        workspace={@workspace}
        project={@project}
      />

      <%!-- Configuration Panel (Right Sidebar) --%>
      <.config_panel :if={@configuring_block} block={@configuring_block} target={@myself} />
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:show_block_menu, fn -> false end)
      |> assign_new(:editing_block_id, fn -> nil end)
      |> assign_new(:configuring_block, fn -> nil end)

    {:ok, socket}
  end

  # ===========================================================================
  # Block Menu Events
  # ===========================================================================

  @impl true
  def handle_event("show_block_menu", _params, socket) do
    {:noreply, assign(socket, :show_block_menu, true)}
  end

  def handle_event("hide_block_menu", _params, socket) do
    {:noreply, assign(socket, :show_block_menu, false)}
  end

  # ===========================================================================
  # Block CRUD Events
  # ===========================================================================

  def handle_event("add_block", %{"type" => type}, socket) do
    with_authorization(socket, fn socket ->
      sheet = socket.assigns.sheet
      project_id = socket.assigns.project.id

      case Sheets.create_block(sheet, %{type: type}) do
        {:ok, _block} ->
          blocks = ReferenceHelpers.load_blocks_with_references(sheet.id, project_id)

          socket =
            socket
            |> assign(:blocks, blocks)
            |> assign(:show_block_menu, false)

          notify_parent(socket, :saved)
          {:noreply, socket}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, gettext("Could not create block."))}
      end
    end)
  end

  def handle_event("update_block_value", %{"id" => block_id, "value" => value}, socket) do
    with_authorization(socket, fn socket ->
      block_id = to_integer(block_id)
      project_id = socket.assigns.project.id
      block = Sheets.get_block_in_project!(block_id, project_id)

      # Wrap raw value in %{"content" => value} structure expected by the schema
      case Sheets.update_block_value(block, %{"content" => value}) do
        {:ok, _updated} ->
          blocks =
            ReferenceHelpers.load_blocks_with_references(socket.assigns.sheet.id, project_id)

          maybe_create_version(socket)
          notify_parent(socket, :saved)
          {:noreply, assign(socket, :blocks, blocks)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, gettext("Could not update block."))}
      end
    end)
  end

  def handle_event("delete_block", %{"id" => block_id}, socket) do
    with_authorization(socket, fn socket ->
      block_id = to_integer(block_id)
      project_id = socket.assigns.project.id
      block = Sheets.get_block_in_project!(block_id, project_id)

      case Sheets.delete_block(block) do
        {:ok, _} ->
          blocks =
            ReferenceHelpers.load_blocks_with_references(socket.assigns.sheet.id, project_id)

          maybe_create_version(socket)
          notify_parent(socket, :saved)
          {:noreply, assign(socket, :blocks, blocks)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not delete block."))}
      end
    end)
  end

  def handle_event("reorder", %{"ids" => ids, "group" => "blocks"}, socket) do
    with_authorization(socket, fn socket ->
      sheet_id = socket.assigns.sheet.id
      project_id = socket.assigns.project.id
      block_ids = Enum.map(ids, &to_integer/1)

      case Sheets.reorder_blocks(sheet_id, block_ids) do
        {:ok, _} ->
          blocks = ReferenceHelpers.load_blocks_with_references(sheet_id, project_id)
          maybe_create_version(socket)
          notify_parent(socket, :saved)
          {:noreply, assign(socket, :blocks, blocks)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not reorder blocks."))}
      end
    end)
  end

  # ===========================================================================
  # Multi-Select Events
  # ===========================================================================

  def handle_event("toggle_multi_select", %{"id" => block_id, "key" => key}, socket) do
    with_authorization(socket, fn socket ->
      result = BlockHelpers.toggle_multi_select_value(socket, block_id, key)
      handle_block_result(socket, result)
    end)
  end

  def handle_event(
        "multi_select_keydown",
        %{"key" => "Enter", "value" => value, "id" => block_id},
        socket
      ) do
    with_authorization(socket, fn socket ->
      result = BlockHelpers.handle_multi_select_enter_value(socket, block_id, value)
      handle_block_result(socket, result)
    end)
  end

  def handle_event("multi_select_keydown", _params, socket) do
    {:noreply, socket}
  end

  # ===========================================================================
  # Rich Text Events
  # ===========================================================================

  def handle_event("update_rich_text", %{"id" => block_id, "content" => content}, socket) do
    with_authorization(socket, fn socket ->
      result = BlockHelpers.update_rich_text_value(socket, block_id, content)
      handle_block_result(socket, result)
    end)
  end

  def handle_event("mention_suggestions", %{"query" => query}, socket)
      when is_binary(query) and byte_size(query) <= 100 do
    project_id = socket.assigns.project.id
    results = Sheets.search_referenceable(project_id, query, ["sheet", "flow"])

    items =
      Enum.map(results, fn result ->
        %{
          id: result.id,
          type: result.type,
          name: result.name,
          shortcut: result.shortcut,
          label: result.shortcut || result.name
        }
      end)

    {:noreply, push_event(socket, "mention_suggestions_result", %{items: items})}
  end

  def handle_event("mention_suggestions", _params, socket) do
    {:noreply, push_event(socket, "mention_suggestions_result", %{items: []})}
  end

  # ===========================================================================
  # Boolean Block Events
  # ===========================================================================

  def handle_event("set_boolean_block", %{"id" => block_id, "value" => value}, socket) do
    with_authorization(socket, fn socket ->
      result = BlockHelpers.set_boolean_block_value(socket, block_id, value)
      handle_block_result(socket, result)
    end)
  end

  # ===========================================================================
  # Configuration Panel Events
  # ===========================================================================

  def handle_event("configure_block", %{"id" => block_id}, socket) do
    with_authorization(socket, fn socket ->
      block_id = to_integer(block_id)
      block = Sheets.get_block_in_project!(block_id, socket.assigns.project.id)
      {:noreply, assign(socket, :configuring_block, block)}
    end)
  end

  def handle_event("close_config_panel", _params, socket) do
    {:noreply, assign(socket, :configuring_block, nil)}
  end

  def handle_event("save_block_config", %{"config" => config_params}, socket) do
    with_authorization(socket, fn socket ->
      block = socket.assigns.configuring_block

      case Sheets.update_block_config(block, config_params) do
        {:ok, updated_block} ->
          blocks = reload_blocks(socket)
          maybe_create_version(socket)
          notify_parent(socket, :saved)

          {:noreply,
           socket
           |> assign(:blocks, blocks)
           |> assign(:configuring_block, updated_block)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, gettext("Could not save configuration."))}
      end
    end)
  end

  def handle_event("toggle_constant", _params, socket) do
    with_authorization(socket, fn socket ->
      block = socket.assigns.configuring_block
      new_value = !block.is_constant

      case Sheets.update_block(block, %{is_constant: new_value}) do
        {:ok, updated_block} ->
          blocks = reload_blocks(socket)
          maybe_create_version(socket)
          notify_parent(socket, :saved)

          {:noreply,
           socket
           |> assign(:blocks, blocks)
           |> assign(:configuring_block, updated_block)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, gettext("Could not toggle constant."))}
      end
    end)
  end

  # ===========================================================================
  # Select Options Events
  # ===========================================================================

  def handle_event("add_select_option", _params, socket) do
    with_authorization(socket, fn socket ->
      ConfigHelpers.add_select_option(socket)
    end)
  end

  def handle_event("remove_select_option", %{"index" => index}, socket) do
    with_authorization(socket, fn socket ->
      ConfigHelpers.remove_select_option(socket, index)
    end)
  end

  def handle_event(
        "update_select_option",
        %{"index" => index, "key" => key, "value" => value},
        socket
      ) do
    with_authorization(socket, fn socket ->
      ConfigHelpers.update_select_option(socket, index, key, value)
    end)
  end

  # ===========================================================================
  # Reference Block Events
  # ===========================================================================

  def handle_event("search_references", %{"value" => query, "block-id" => block_id}, socket) do
    ReferenceHelpers.search_references(socket, query, block_id)
  end

  def handle_event(
        "select_reference",
        %{"block-id" => block_id, "type" => target_type, "id" => target_id},
        socket
      ) do
    with_authorization(socket, fn socket ->
      result = ReferenceHelpers.select_reference_value(socket, block_id, target_type, target_id)
      handle_block_result(socket, result)
    end)
  end

  def handle_event("clear_reference", %{"block-id" => block_id}, socket) do
    with_authorization(socket, fn socket ->
      result = ReferenceHelpers.clear_reference_value(socket, block_id)
      handle_block_result(socket, result)
    end)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp with_authorization(socket, fun) do
    if socket.assigns.can_edit do
      fun.(socket)
    else
      {:noreply, put_flash(socket, :error, gettext("You don't have permission to edit."))}
    end
  end

  defp handle_block_result(socket, {:ok, blocks}) do
    maybe_create_version(socket)
    notify_parent(socket, :saved)
    {:noreply, assign(socket, :blocks, blocks)}
  end

  defp handle_block_result(socket, {:error, message}) do
    {:noreply, put_flash(socket, :error, message)}
  end

  defp reload_blocks(socket) do
    ReferenceHelpers.load_blocks_with_references(
      socket.assigns.sheet.id,
      socket.assigns.project.id
    )
  end

  defp maybe_create_version(socket) do
    sheet = socket.assigns.sheet
    user_id = socket.assigns.current_user_id
    Sheets.maybe_create_version(sheet, user_id)
  end

  defp notify_parent(_socket, status) do
    send(self(), {:content_tab, status})
  end

  defp to_integer(value) when is_binary(value), do: String.to_integer(value)
  defp to_integer(value) when is_integer(value), do: value

  # ===========================================================================
  # Sub-components
  # ===========================================================================

  attr :children, :list, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true

  defp children_sheets_section(assigns) do
    ~H"""
    <div class="mt-12 pt-8 border-t border-base-300">
      <h2 class="text-lg font-semibold mb-4">{gettext("Subsheets")}</h2>
      <div class="space-y-2">
        <.link
          :for={child <- @children}
          navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets/#{child.id}"}
          class="flex items-center gap-2 p-2 rounded hover:bg-base-200"
        >
          <.sheet_avatar avatar_asset={child.avatar_asset} name={child.name} size="md" />
          <span>{child.name}</span>
        </.link>
      </div>
    </div>
    """
  end
end
