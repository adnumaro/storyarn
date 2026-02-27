defmodule StoryarnWeb.SheetLive.Components.ContentTab do
  @moduledoc """
  LiveComponent for the Content tab in the sheet editor.
  Handles all block-related events: add, update, delete, reorder, configure.
  """

  use StoryarnWeb, :live_component
  use StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.SheetLive.Components.InheritedBlockComponents
  import StoryarnWeb.SheetLive.Components.ChildrenSheetsSection
  import StoryarnWeb.SheetLive.Components.OwnBlocksComponents

  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Handlers.BlockCrudHandlers
  alias StoryarnWeb.SheetLive.Handlers.BlockToolbarHandlers
  alias StoryarnWeb.SheetLive.Handlers.InheritanceHandlers
  alias StoryarnWeb.SheetLive.Handlers.TableHandlers
  alias StoryarnWeb.SheetLive.Helpers.BlockHelpers
  alias StoryarnWeb.SheetLive.Helpers.ContentTabHelpers
  alias StoryarnWeb.SheetLive.Helpers.ReferenceHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="BlockKeyboard"
      data-selected-block-id={@selected_block_id}
      data-phx-target={"##{@id}"}
    >
      <%!-- Inherited Properties (grouped by source sheet) --%>
      <div :for={group <- @inherited_groups} class="mb-6">
        <.inherited_section_header
          source_sheet={group.source_sheet}
          block_count={length(group.blocks)}
          workspace={@workspace}
          project={@project}
        />
        <div class="flex flex-col gap-2 -mx-2 sm:-mx-8 md:-mx-16 -mt-2 border-l-2 border-info/30 ml-1">
          <div
            :for={block <- group.blocks}
            class="group relative w-full px-2 sm:px-8 md:px-16 pt-2"
            id={"block-#{block.id}"}
          >
            <.inherited_block_wrapper
              block={block}
              can_edit={@can_edit}
              editing_block_id={@editing_block_id}
              selected_block_id={@selected_block_id}
              target={@myself}
              component_id={@id}
              table_data={@table_data}
              reference_options={@reference_options}
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
        selected_block_id={@selected_block_id}
        target={@myself}
        component_id={@id}
        table_data={@table_data}
        reference_options={@reference_options}
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
      |> assign_new(:selected_block_id, fn -> nil end)
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

    # Batch-load table data for all table blocks (own + inherited)
    table_data = load_table_data(own_blocks, inherited_groups)
    reference_options = load_reference_options(table_data, project_id)

    socket =
      socket
      |> assign(:inherited_groups, inherited_groups)
      |> assign(:own_blocks, own_blocks)
      |> assign(:layout_items, layout_items)
      |> assign(:table_data, table_data)
      |> assign(:reference_options, reference_options)

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
    with_edit_authorization(socket, fn socket ->
      BlockCrudHandlers.handle_add_block(type, socket, content_helpers())
    end)
  end

  def handle_event("update_block_value", %{"id" => block_id, "value" => value}, socket) do
    with_edit_authorization(socket, fn socket ->
      BlockCrudHandlers.handle_update_block_value(block_id, value, socket, content_helpers())
    end)
  end

  def handle_event("delete_block", %{"id" => block_id}, socket) do
    with_edit_authorization(socket, fn socket ->
      BlockCrudHandlers.handle_delete_block(block_id, socket, content_helpers())
    end)
  end

  def handle_event("duplicate_block", %{"id" => block_id}, socket) do
    with_edit_authorization(socket, fn socket ->
      BlockToolbarHandlers.handle_duplicate_block(block_id, socket, content_helpers())
    end)
  end

  def handle_event("toolbar_toggle_constant", %{"id" => block_id}, socket) do
    with_edit_authorization(socket, fn socket ->
      BlockToolbarHandlers.handle_toggle_constant(block_id, socket, content_helpers())
    end)
  end

  def handle_event("move_block_up", %{"id" => block_id}, socket) do
    with_edit_authorization(socket, fn socket ->
      BlockToolbarHandlers.handle_move_block_up(block_id, socket, content_helpers())
    end)
  end

  def handle_event("move_block_down", %{"id" => block_id}, socket) do
    with_edit_authorization(socket, fn socket ->
      BlockToolbarHandlers.handle_move_block_down(block_id, socket, content_helpers())
    end)
  end

  def handle_event("select_block", %{"id" => block_id}, socket) do
    {:noreply, assign(socket, :selected_block_id, ContentTabHelpers.to_integer(block_id))}
  end

  def handle_event("deselect_block", _params, socket) do
    {:noreply, assign(socket, :selected_block_id, nil)}
  end

  def handle_event("reorder", %{"ids" => ids, "group" => "blocks"}, socket) do
    with_edit_authorization(socket, fn socket ->
      BlockCrudHandlers.handle_reorder(ids, socket, content_helpers())
    end)
  end

  def handle_event("reorder_with_columns", %{"items" => items}, socket) do
    with_edit_authorization(socket, fn socket ->
      BlockCrudHandlers.handle_reorder_with_columns(items, socket, content_helpers())
    end)
  end

  def handle_event("create_column_group", %{"block_ids" => block_ids}, socket) do
    with_edit_authorization(socket, fn socket ->
      BlockCrudHandlers.handle_create_column_group(block_ids, socket, content_helpers())
    end)
  end

  # ===========================================================================
  # Multi-Select Events
  # ===========================================================================

  def handle_event("toggle_multi_select", %{"id" => block_id, "key" => key}, socket) do
    with_edit_authorization(socket, fn socket ->
      with_block_value_undo(socket, block_id, fn ->
        BlockHelpers.toggle_multi_select_value(socket, block_id, key)
      end)
    end)
  end

  def handle_event(
        "multi_select_keydown",
        %{"key" => "Enter", "value" => value, "id" => block_id},
        socket
      ) do
    with_edit_authorization(socket, fn socket ->
      with_block_value_undo(socket, block_id, fn ->
        BlockHelpers.handle_multi_select_enter_value(socket, block_id, value)
      end)
    end)
  end

  def handle_event("multi_select_keydown", _params, socket) do
    {:noreply, socket}
  end

  # ===========================================================================
  # Rich Text Events
  # ===========================================================================

  def handle_event("update_rich_text", %{"id" => block_id, "content" => content}, socket) do
    with_edit_authorization(socket, fn socket ->
      with_block_value_undo(socket, block_id, fn ->
        BlockHelpers.update_rich_text_value(socket, block_id, content)
      end)
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
    with_edit_authorization(socket, fn socket ->
      with_block_value_undo(socket, block_id, fn ->
        BlockHelpers.set_boolean_block_value(socket, block_id, value)
      end)
    end)
  end

  # ===========================================================================
  # Table Block Events
  # ===========================================================================

  def handle_event("resize_table_column", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_resize_column(params, socket)
    end)
  end

  def handle_event("update_table_cell", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_update_cell(params, socket, content_helpers())
    end)
  end

  def handle_event("toggle_table_collapse", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_toggle_collapse(params, socket, content_helpers())
    end)
  end

  def handle_event("toggle_table_cell_boolean", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_toggle_cell_boolean(params, socket, content_helpers())
    end)
  end

  def handle_event("add_table_column", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_add_column(params, socket, content_helpers())
    end)
  end

  def handle_event("add_table_row", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_add_row(params, socket, content_helpers())
    end)
  end

  def handle_event("rename_table_column", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_rename_column(params, socket, content_helpers())
    end)
  end

  def handle_event("change_table_column_type", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_change_column_type(params, socket, content_helpers())
    end)
  end

  def handle_event("toggle_table_column_constant", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_toggle_column_constant(params, socket, content_helpers())
    end)
  end

  def handle_event("toggle_table_column_required", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_toggle_column_required(params, socket, content_helpers())
    end)
  end

  def handle_event("delete_table_column", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_delete_column(params, socket, content_helpers())
    end)
  end

  def handle_event("rename_table_row", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_rename_row(params, socket, content_helpers())
    end)
  end

  def handle_event("rename_table_row_keydown", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_rename_row_keydown(params, socket, content_helpers())
    end)
  end

  def handle_event("delete_table_row", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_delete_row(params, socket, content_helpers())
    end)
  end

  def handle_event("reorder_table_rows", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_reorder_rows(params, socket, content_helpers())
    end)
  end

  def handle_event("toggle_reference_multiple", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_toggle_reference_multiple(params, socket, content_helpers())
    end)
  end

  def handle_event("update_number_constraint", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_update_number_constraint(params, socket, content_helpers())
    end)
  end

  def handle_event("select_table_cell", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_select_table_cell(params, socket, content_helpers())
    end)
  end

  def handle_event("toggle_table_cell_multi_select", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_toggle_table_cell_multi_select(params, socket, content_helpers())
    end)
  end

  def handle_event("add_table_cell_option", %{"key" => "Enter"} = params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_add_table_cell_option(params, socket, content_helpers())
    end)
  end

  def handle_event("add_table_cell_option", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("add_table_column_option_keydown", %{"key" => "Enter"} = params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_add_column_option(params, socket, content_helpers())
    end)
  end

  def handle_event("add_table_column_option_keydown", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("remove_table_column_option", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_remove_column_option(params, socket, content_helpers())
    end)
  end

  def handle_event("update_table_column_option", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_update_column_option(params, socket, content_helpers())
    end)
  end

  # ===========================================================================
  # Configuration Events (popover-based)
  # ===========================================================================

  def handle_event(
        "save_config_field",
        %{"block_id" => block_id, "field" => field, "value" => value},
        socket
      ) do
    with_edit_authorization(socket, fn socket ->
      BlockToolbarHandlers.handle_save_config_field(
        block_id,
        field,
        value,
        socket,
        content_helpers()
      )
    end)
  end

  def handle_event("add_select_option", %{"block_id" => block_id}, socket) do
    with_edit_authorization(socket, fn socket ->
      BlockToolbarHandlers.handle_add_option(block_id, socket, content_helpers())
    end)
  end

  def handle_event("remove_select_option", %{"block_id" => block_id, "index" => index}, socket) do
    with_edit_authorization(socket, fn socket ->
      BlockToolbarHandlers.handle_remove_option(block_id, index, socket, content_helpers())
    end)
  end

  def handle_event(
        "update_select_option",
        %{"block_id" => block_id, "index" => index, "key_field" => key_field, "value" => value},
        socket
      ) do
    with_edit_authorization(socket, fn socket ->
      BlockToolbarHandlers.handle_update_option(
        block_id,
        index,
        key_field,
        value,
        socket,
        content_helpers()
      )
    end)
  end

  def handle_event(
        "toggle_allowed_type",
        %{"block_id" => block_id, "type" => type},
        socket
      ) do
    with_edit_authorization(socket, fn socket ->
      BlockToolbarHandlers.handle_toggle_allowed_type(
        block_id,
        type,
        socket,
        content_helpers()
      )
    end)
  end

  def handle_event("update_block_label", %{"id" => block_id, "label" => label}, socket) do
    with_edit_authorization(socket, fn socket ->
      block_id = ContentTabHelpers.to_integer(block_id)
      do_update_block_label(block_id, label, socket)
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
    with_edit_authorization(socket, fn socket ->
      with_block_value_undo(socket, block_id, fn ->
        ReferenceHelpers.select_reference_value(socket, block_id, target_type, target_id)
      end)
    end)
  end

  def handle_event("clear_reference", %{"block-id" => block_id}, socket) do
    with_edit_authorization(socket, fn socket ->
      with_block_value_undo(socket, block_id, fn ->
        ReferenceHelpers.clear_reference_value(socket, block_id)
      end)
    end)
  end

  # ===========================================================================
  # Inheritance Action Events
  # ===========================================================================

  def handle_event("detach_inherited_block", %{"id" => block_id}, socket) do
    with_edit_authorization(socket, fn socket ->
      InheritanceHandlers.handle_detach(block_id, socket, inheritance_helpers(socket))
    end)
  end

  def handle_event("reattach_block", %{"id" => block_id}, socket) do
    with_edit_authorization(socket, fn socket ->
      InheritanceHandlers.handle_reattach(block_id, socket, inheritance_helpers(socket))
    end)
  end

  def handle_event("hide_inherited_for_children", %{"id" => block_id}, socket) do
    with_edit_authorization(socket, fn socket ->
      InheritanceHandlers.handle_hide_for_children(block_id, socket, inheritance_helpers(socket))
    end)
  end

  def handle_event("unhide_inherited_for_children", %{"id" => block_id}, socket) do
    with_edit_authorization(socket, fn socket ->
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

  def handle_event("change_block_scope", %{"scope" => scope, "id" => block_id}, socket)
      when scope in ["self", "children"] do
    with_edit_authorization(socket, fn socket ->
      BlockToolbarHandlers.handle_change_scope(
        block_id,
        scope,
        socket,
        inheritance_helpers(socket)
      )
    end)
  end

  def handle_event("toggle_required", %{"id" => block_id}, socket) do
    with_edit_authorization(socket, fn socket ->
      BlockToolbarHandlers.handle_toggle_required_by_id(
        block_id,
        socket,
        inheritance_helpers(socket)
      )
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
    with_edit_authorization(socket, fn socket ->
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

  defp handle_block_result(socket, {:ok, _blocks}) do
    maybe_create_version(socket)
    notify_parent(socket, :saved)
    {:noreply, reload_blocks(socket)}
  end

  defp handle_block_result(socket, {:error, message}) do
    {:noreply, put_flash(socket, :error, message)}
  end

  # Wraps a block value operation with undo recording.
  # Captures prev content before operation and new content after, then pushes undo.
  defp with_block_value_undo(socket, block_id, fun) do
    block_id_int = ContentTabHelpers.to_integer(block_id)
    prev_content = get_block_content(block_id_int, socket)

    case fun.() do
      {:ok, _blocks} = result ->
        new_content = get_block_content(block_id_int, socket)

        if prev_content != new_content do
          push_undo({:update_block_value, block_id_int, prev_content, new_content})
        end

        handle_block_result(socket, result)

      error ->
        handle_block_result(socket, error)
    end
  end

  defp get_block_content(block_id, socket) do
    case Sheets.get_block_in_project(block_id, socket.assigns.project.id) do
      nil -> nil
      block -> get_in(block.value, ["content"])
    end
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

    # Batch-load table data for all table blocks (own + inherited)
    table_data = load_table_data(own_blocks, inherited_groups)
    reference_options = load_reference_options(table_data, project_id)

    socket
    |> assign(:inherited_groups, inherited_groups)
    |> assign(:own_blocks, own_blocks)
    |> assign(:layout_items, layout_items)
    |> assign(:table_data, table_data)
    |> assign(:reference_options, reference_options)
  end

  defp maybe_create_version(socket) do
    sheet = socket.assigns.sheet
    user_id = socket.assigns.current_user_id
    Sheets.maybe_create_version(sheet, user_id)
  end

  defp notify_parent(_socket, status) do
    send(self(), {:content_tab, status})
  end

  defp push_undo(action) do
    send(self(), {:content_tab, :push_undo, action})
  end

  # Builds the helpers map required by InheritanceHandlers.
  defp inheritance_helpers(_socket) do
    %{
      reload_blocks: &reload_blocks/1,
      maybe_create_version: &maybe_create_version/1,
      notify_parent: &notify_parent/2
    }
  end

  defp load_table_data(own_blocks, inherited_groups) do
    own_table_ids =
      own_blocks
      |> Enum.filter(&(&1.type == "table"))
      |> Enum.map(& &1.id)

    inherited_table_ids =
      inherited_groups
      |> Enum.flat_map(& &1.blocks)
      |> Enum.filter(&(&1.type == "table"))
      |> Enum.map(& &1.id)

    all_table_ids = own_table_ids ++ inherited_table_ids

    if all_table_ids != [], do: Sheets.batch_load_table_data(all_table_ids), else: %{}
  end

  defp load_reference_options(table_data, project_id) do
    has_reference_columns =
      Enum.any?(table_data, fn
        {_block_id, %{columns: columns}} ->
          Enum.any?(columns, &(&1.type == "reference"))

        _ ->
          false
      end)

    if has_reference_columns do
      Sheets.list_reference_options(project_id)
    else
      []
    end
  end

  defp do_update_block_label(block_id, label, socket) do
    case Sheets.get_block_in_project(block_id, socket.assigns.project.id) do
      nil ->
        {:noreply, socket}

      block ->
        case Sheets.update_block_config(block, %{"label" => label}) do
          {:ok, _updated_block} ->
            helpers = content_helpers()
            helpers.maybe_create_version.(socket)
            helpers.notify_parent.(socket, :saved)
            {:noreply, helpers.reload_blocks.(socket)}

          {:error, _} ->
            {:noreply, socket}
        end
    end
  end

  # Builds the helpers map required by BlockCrudHandlers and TableHandlers.
  defp content_helpers do
    %{
      reload_blocks: &reload_blocks/1,
      maybe_create_version: &maybe_create_version/1,
      notify_parent: &notify_parent/2,
      push_undo: &push_undo/1
    }
  end
end
