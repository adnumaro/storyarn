defmodule StoryarnWeb.SheetLive.Components.ContentTab do
  @moduledoc """
  LiveComponent for the Content tab in the sheet editor.
  Handles all block-related events: add, update, delete, reorder, configure.
  """

  use StoryarnWeb, :live_component

  import StoryarnWeb.Components.BlockComponents
  import StoryarnWeb.SheetLive.Components.InheritedBlockComponents
  import StoryarnWeb.SheetLive.Components.ChildrenSheetsSection
  import StoryarnWeb.SheetLive.Components.OwnBlocksComponents

  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Handlers.BlockCrudHandlers
  alias StoryarnWeb.SheetLive.Handlers.ConfigPanelHandlers
  alias StoryarnWeb.SheetLive.Handlers.InheritanceHandlers
  alias StoryarnWeb.SheetLive.Helpers.BlockHelpers
  alias StoryarnWeb.SheetLive.Helpers.ConfigHelpers
  alias StoryarnWeb.SheetLive.Helpers.ContentTabHelpers
  alias StoryarnWeb.SheetLive.Helpers.ReferenceHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <%!-- Inherited Properties (grouped by source sheet) --%>
      <div :for={group <- @inherited_groups} class="mb-6">
        <.inherited_section_header
          source_sheet={group.source_sheet}
          block_count={length(group.blocks)}
          workspace={@workspace}
          project={@project}
        />
        <div class="flex flex-col gap-2 -mx-2 sm:-mx-8 md:-mx-16 border-l-2 border-info/30 ml-1">
          <div
            :for={block <- group.blocks}
            class="group relative w-full px-2 sm:px-8 md:px-16"
            id={"block-#{block.id}"}
          >
            <.inherited_block_wrapper
              block={block}
              can_edit={@can_edit}
              editing_block_id={@editing_block_id}
              target={@myself}
            />
          </div>
        </div>
      </div>

      <%!-- Own Properties label (only shown when inherited blocks are present) --%>
      <.own_properties_label show={@inherited_groups != []} />

      <%!-- Sortable own-block list (full-width and column groups) --%>
      <.blocks_container
        layout_items={@layout_items}
        can_edit={@can_edit}
        editing_block_id={@editing_block_id}
        target={@myself}
        component_id={@id}
      />

      <%!-- Add block button / slash command --%>
      <.add_block_prompt
        can_edit={@can_edit}
        show_block_menu={@show_block_menu}
        block_scope={@block_scope}
        target={@myself}
      />

      <%!-- Children sheets --%>
      <.children_sheets_section
        :if={@children != []}
        children={@children}
        workspace={@workspace}
        project={@project}
      />

      <%!-- Configuration Panel (Right Sidebar) --%>
      <.config_panel :if={@configuring_block} block={@configuring_block} target={@myself} />

      <%!-- Propagation Modal --%>
      <.live_component
        :if={@propagation_block}
        module={StoryarnWeb.SheetLive.Components.PropagationModal}
        id="propagation-modal"
        block={@propagation_block}
        sheet={@sheet}
        target={@myself}
      />
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
      |> assign_new(:block_scope, fn -> "self" end)
      |> assign_new(:propagation_block, fn -> nil end)

    # Split blocks into inherited and own groups using optimized batch query
    {inherited_groups, own_blocks} =
      Sheets.get_sheet_blocks_grouped(socket.assigns.sheet.id)

    # Enrich blocks with reference_target for reference-type blocks
    project_id = socket.assigns.project.id

    inherited_groups =
      Enum.map(inherited_groups, fn group ->
        %{group | blocks: ContentTabHelpers.enrich_with_references(group.blocks, project_id)}
      end)

    own_blocks = ContentTabHelpers.enrich_with_references(own_blocks, project_id)

    layout_items = ContentTabHelpers.group_blocks_for_layout(own_blocks)

    socket =
      socket
      |> assign(:inherited_groups, inherited_groups)
      |> assign(:own_blocks, own_blocks)
      |> assign(:layout_items, layout_items)

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
  # Block Scope Events
  # ===========================================================================

  def handle_event("set_block_scope", %{"scope" => scope}, socket)
      when scope in ["self", "children"] do
    {:noreply, assign(socket, :block_scope, scope)}
  end

  # ===========================================================================
  # Block CRUD Events
  # ===========================================================================

  def handle_event("add_block", %{"type" => type}, socket) do
    with_authorization(socket, fn socket ->
      BlockCrudHandlers.handle_add_block(type, socket, block_crud_helpers())
    end)
  end

  def handle_event("update_block_value", %{"id" => block_id, "value" => value}, socket) do
    with_authorization(socket, fn socket ->
      BlockCrudHandlers.handle_update_block_value(block_id, value, socket, block_crud_helpers())
    end)
  end

  def handle_event("delete_block", %{"id" => block_id}, socket) do
    with_authorization(socket, fn socket ->
      BlockCrudHandlers.handle_delete_block(block_id, socket, block_crud_helpers())
    end)
  end

  def handle_event("reorder", %{"ids" => ids, "group" => "blocks"}, socket) do
    with_authorization(socket, fn socket ->
      BlockCrudHandlers.handle_reorder(ids, socket, block_crud_helpers())
    end)
  end

  def handle_event("reorder_with_columns", %{"items" => items}, socket) do
    with_authorization(socket, fn socket ->
      BlockCrudHandlers.handle_reorder_with_columns(items, socket, block_crud_helpers())
    end)
  end

  def handle_event("create_column_group", %{"block_ids" => block_ids}, socket) do
    with_authorization(socket, fn socket ->
      BlockCrudHandlers.handle_create_column_group(block_ids, socket, block_crud_helpers())
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
      ConfigPanelHandlers.handle_configure_block(block_id, socket, block_crud_helpers())
    end)
  end

  def handle_event("close_config_panel", _params, socket) do
    {:noreply, assign(socket, :configuring_block, nil)}
  end

  def handle_event("save_block_config", %{"config" => config_params}, socket) do
    with_authorization(socket, fn socket ->
      ConfigPanelHandlers.handle_save_block_config(config_params, socket, block_crud_helpers())
    end)
  end

  def handle_event("toggle_constant", _params, socket) do
    with_authorization(socket, fn socket ->
      ConfigPanelHandlers.handle_toggle_constant(socket, block_crud_helpers())
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
  # Inheritance Action Events
  # ===========================================================================

  def handle_event("detach_inherited_block", %{"id" => block_id}, socket) do
    with_authorization(socket, fn socket ->
      InheritanceHandlers.handle_detach(block_id, socket, inheritance_helpers(socket))
    end)
  end

  def handle_event("reattach_block", %{"id" => block_id}, socket) do
    with_authorization(socket, fn socket ->
      InheritanceHandlers.handle_reattach(block_id, socket, inheritance_helpers(socket))
    end)
  end

  def handle_event("hide_inherited_for_children", %{"id" => block_id}, socket) do
    with_authorization(socket, fn socket ->
      InheritanceHandlers.handle_hide_for_children(block_id, socket, inheritance_helpers(socket))
    end)
  end

  def handle_event("unhide_inherited_for_children", %{"id" => block_id}, socket) do
    with_authorization(socket, fn socket ->
      InheritanceHandlers.handle_unhide_for_children(
        block_id,
        socket,
        inheritance_helpers(socket)
      )
    end)
  end

  def handle_event("navigate_to_source", %{"id" => block_id}, socket) do
    InheritanceHandlers.handle_navigate_to_source(block_id, socket, inheritance_helpers(socket))
  end

  def handle_event("change_block_scope", %{"scope" => scope}, socket)
      when scope in ["self", "children"] do
    with_authorization(socket, fn socket ->
      InheritanceHandlers.handle_change_scope(scope, socket, inheritance_helpers(socket))
    end)
  end

  def handle_event("toggle_required", _params, socket) do
    with_authorization(socket, fn socket ->
      InheritanceHandlers.handle_toggle_required(socket, inheritance_helpers(socket))
    end)
  end

  # ===========================================================================
  # Propagation Events
  # ===========================================================================

  def handle_event("open_propagation_modal", %{"block-id" => block_id}, socket) do
    InheritanceHandlers.handle_open_propagation_modal(
      block_id,
      socket,
      inheritance_helpers(socket)
    )
  end

  def handle_event("cancel_propagation", _params, socket) do
    InheritanceHandlers.handle_cancel_propagation(socket)
  end

  def handle_event("propagate_property", %{"sheet_ids" => sheet_ids_json}, socket) do
    with_authorization(socket, fn socket ->
      InheritanceHandlers.handle_propagate_property(
        sheet_ids_json,
        socket,
        inheritance_helpers(socket)
      )
    end)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp with_authorization(socket, fun) do
    if socket.assigns.can_edit do
      fun.(socket)
    else
      {:noreply, put_flash(socket, :error, dgettext("sheets", "You don't have permission to edit."))}
    end
  end

  defp handle_block_result(socket, {:ok, _blocks}) do
    maybe_create_version(socket)
    notify_parent(socket, :saved)
    {:noreply, reload_blocks(socket)}
  end

  defp handle_block_result(socket, {:error, message}) do
    {:noreply, put_flash(socket, :error, message)}
  end

  defp reload_blocks(socket) do
    sheet_id = socket.assigns.sheet.id
    project_id = socket.assigns.project.id

    {inherited_groups, own_blocks} = Sheets.get_sheet_blocks_grouped(sheet_id)

    inherited_groups =
      Enum.map(inherited_groups, fn group ->
        %{group | blocks: ContentTabHelpers.enrich_with_references(group.blocks, project_id)}
      end)

    own_blocks = ContentTabHelpers.enrich_with_references(own_blocks, project_id)
    layout_items = ContentTabHelpers.group_blocks_for_layout(own_blocks)

    socket
    |> assign(:inherited_groups, inherited_groups)
    |> assign(:own_blocks, own_blocks)
    |> assign(:layout_items, layout_items)
  end

  defp maybe_create_version(socket) do
    sheet = socket.assigns.sheet
    user_id = socket.assigns.current_user_id
    Sheets.maybe_create_version(sheet, user_id)
  end

  defp notify_parent(_socket, status) do
    send(self(), {:content_tab, status})
  end

  # Builds the helpers map required by InheritanceHandlers.
  defp inheritance_helpers(_socket) do
    %{
      reload_blocks: &reload_blocks/1,
      maybe_create_version: &maybe_create_version/1,
      notify_parent: &notify_parent/2
    }
  end

  # Builds the helpers map required by BlockCrudHandlers.
  defp block_crud_helpers do
    %{
      reload_blocks: &reload_blocks/1,
      maybe_create_version: &maybe_create_version/1,
      notify_parent: &notify_parent/2
    }
  end

end
