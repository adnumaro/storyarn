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
  import StoryarnWeb.SheetLive.Helpers.FormulaHelpers

  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Handlers.BlockCrudHandlers
  alias StoryarnWeb.SheetLive.Handlers.BlockToolbarHandlers
  alias StoryarnWeb.SheetLive.Handlers.GalleryHandlers
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
            data-id={block.id}
            data-inherited="true"
            data-inherited-from-block-id={block.inherited_from_block_id}
            data-detached={to_string(block.detached || false)}
          >
            <.inherited_block_wrapper
              block={block}
              can_edit={@can_edit}
              editing_block_id={@editing_block_id}
              selected_block_id={@selected_block_id}
              target={@myself}
              component_id={@id}
              table_data={@table_data}
              gallery_data={@gallery_data}
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
        gallery_data={@gallery_data}
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

      <%!-- Formula Sidebar (right panel) --%>
      <div
        :if={@formula_editing != nil}
        id="formula-sidebar"
        phx-hook="FormulaSidebar"
        data-close-event="close_formula_sidebar"
        data-phx-target={"##{@id}"}
        class={[
          "fixed flex flex-col overflow-hidden",
          "inset-0 z-[1030] bg-base-100",
          "xl:inset-auto xl:right-3 xl:top-[76px] xl:bottom-3 xl:z-[1010] xl:w-[400px]",
          "xl:bg-base-200/95 xl:backdrop-blur xl:border xl:border-base-300 xl:rounded-xl xl:shadow-sm"
        ]}
      >
        <.formula_sidebar_content
          formula={@formula_editing}
          variables={@project_variables}
          target={@myself}
        />
      </div>
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
      |> assign_new(:formula_editing, fn -> nil end)
      |> assign_new(:project_variables, fn -> [] end)

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

    # Annotate blocks with :is_referenced for variable_name editability
    referenced_ids =
      ContentTabHelpers.compute_referenced_block_ids(own_blocks, inherited_groups)

    own_blocks = ContentTabHelpers.enrich_with_referenced_status(own_blocks, referenced_ids)

    inherited_groups =
      Enum.map(inherited_groups, fn group ->
        %{
          group
          | blocks: ContentTabHelpers.enrich_with_referenced_status(group.blocks, referenced_ids)
        }
      end)

    layout_items = ContentTabHelpers.group_blocks_for_layout(own_blocks)

    # Batch-load table data for all table blocks (own + inherited)
    table_data = load_table_data(own_blocks, inherited_groups, project_id)
    gallery_data = load_gallery_data(own_blocks, inherited_groups)
    reference_options = load_reference_options(table_data, project_id)

    socket =
      socket
      |> assign(:inherited_groups, inherited_groups)
      |> assign(:own_blocks, own_blocks)
      |> assign(:layout_items, layout_items)
      |> assign(:table_data, table_data)
      |> assign(:gallery_data, gallery_data)
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

  def handle_event(
        "update_variable_name",
        %{"block_id" => block_id, "variable_name" => variable_name},
        socket
      ) do
    with_edit_authorization(socket, fn socket ->
      BlockToolbarHandlers.handle_update_variable_name(
        block_id,
        variable_name,
        socket,
        content_helpers()
      )
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

  def handle_event("update_formula_cell", params, socket) do
    with_edit_authorization(socket, fn socket ->
      TableHandlers.handle_update_formula_cell(params, socket, content_helpers())
    end)
  end

  def handle_event("open_formula_sidebar", params, socket) do
    row_id = ContentTabHelpers.to_integer(params["row-id"])
    block_id = ContentTabHelpers.to_integer(params["block-id"])
    slug = params["column-slug"]

    row = Sheets.get_table_row!(row_id)
    table_entry = Map.get(socket.assigns.table_data, block_id, %{columns: [], rows: []})

    {:noreply,
     assign(socket, :formula_editing, %{
       row_id: row_id,
       column_slug: slug,
       block_id: block_id,
       value: row.cells[slug],
       columns: table_entry.columns
     })}
  end

  def handle_event("close_formula_sidebar", _params, socket) do
    {:noreply, assign(socket, :formula_editing, nil)}
  end

  def handle_event("save_formula_expression", %{"value" => expression} = params, socket) do
    with_edit_authorization(socket, fn socket ->
      current = socket.assigns.formula_editing
      current_bindings = if is_map(current.value), do: current.value["bindings"] || %{}, else: %{}
      raw_bindings = encode_bindings(current_bindings)

      {:noreply, updated_socket} =
        TableHandlers.handle_update_formula_cell(
          %{
            "row-id" => params["row-id"],
            "column-slug" => params["column-slug"],
            "expression" => expression,
            "bindings" => raw_bindings
          },
          socket,
          content_helpers()
        )

      {:noreply, refresh_formula_editing(updated_socket)}
    end)
  end

  def handle_event(
        "save_formula_binding",
        %{"binding_value" => value, "symbol" => symbol} = params,
        socket
      ) do
    with_edit_authorization(socket, fn socket ->
      current = socket.assigns.formula_editing
      current_value = current.value || %{}

      expression = if is_map(current_value), do: current_value["expression"] || "", else: ""
      current_bindings = if is_map(current_value), do: current_value["bindings"] || %{}, else: %{}

      binding = parse_binding_value(value)

      updated_bindings =
        if binding,
          do: Map.put(current_bindings, symbol, binding),
          else: Map.delete(current_bindings, symbol)

      raw_bindings = encode_bindings(updated_bindings)

      {:noreply, updated_socket} =
        TableHandlers.handle_update_formula_cell(
          %{
            "row-id" => params["row-id"],
            "column-slug" => params["column-slug"],
            "expression" => expression,
            "bindings" => raw_bindings
          },
          socket,
          content_helpers()
        )

      {:noreply, refresh_formula_editing(updated_socket)}
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
  # Gallery Block Events
  # ===========================================================================

  def handle_event("upload_gallery_image", params, socket) do
    with_edit_authorization(socket, fn socket ->
      GalleryHandlers.handle_upload_gallery_image(params, socket, content_helpers())
    end)
  end

  def handle_event("upload_gallery_validation_error", params, socket) do
    GalleryHandlers.handle_upload_validation_error(params, socket)
  end

  def handle_event("remove_gallery_image", params, socket) do
    with_edit_authorization(socket, fn socket ->
      GalleryHandlers.handle_remove_gallery_image(params, socket, content_helpers())
    end)
  end

  def handle_event("update_gallery_image", params, socket) do
    with_edit_authorization(socket, fn socket ->
      GalleryHandlers.handle_update_gallery_image(params, socket, content_helpers())
    end)
  end

  def handle_event("reorder_gallery_images", params, socket) do
    with_edit_authorization(socket, fn socket ->
      GalleryHandlers.handle_reorder_gallery_images(params, socket, content_helpers())
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
    table_data = load_table_data(own_blocks, inherited_groups, project_id)
    gallery_data = load_gallery_data(own_blocks, inherited_groups)
    reference_options = load_reference_options(table_data, project_id)

    socket
    |> assign(:inherited_groups, inherited_groups)
    |> assign(:own_blocks, own_blocks)
    |> assign(:layout_items, layout_items)
    |> assign(:table_data, table_data)
    |> assign(:gallery_data, gallery_data)
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

  defp load_table_data(own_blocks, inherited_groups, project_id) do
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

    table_data =
      if all_table_ids != [], do: Sheets.batch_load_table_data(all_table_ids), else: %{}

    # Compute formula column values and inject into row cells
    compute_formulas(table_data, project_id)
  end

  defp compute_formulas(table_data, project_id) do
    alias Storyarn.Sheets.FormulaResolver

    Map.new(table_data, fn {block_id, %{columns: cols, rows: rows} = data} ->
      formula_cols = Enum.filter(cols, &(&1.type == "formula"))

      if formula_cols == [] do
        {block_id, data}
      else
        computed = safe_compute_all(cols, rows, project_id)
        {block_id, %{data | rows: inject_formula_results(rows, computed)}}
      end
    end)
  end

  defp safe_compute_all(cols, rows, project_id) do
    alias Storyarn.Sheets.FormulaResolver

    try do
      FormulaResolver.compute_all(cols, rows, project_id)
    rescue
      _ -> %{}
    end
  end

  defp inject_formula_results(rows, computed) do
    Enum.map(rows, fn row ->
      formula_results = Map.get(computed, row.id, %{})

      updated_cells =
        Enum.reduce(formula_results, row.cells, fn {slug, result}, cells ->
          enriched = enrich_cell(cells[slug], result)
          Map.put(cells, slug, enriched)
        end)

      %{row | cells: updated_cells}
    end)
  end

  defp enrich_cell(current, result) when is_map(current), do: Map.put(current, "__result", result)
  defp enrich_cell(_current, result), do: %{"__result" => result}

  defp load_gallery_data(own_blocks, inherited_groups) do
    own_gallery_ids =
      own_blocks
      |> Enum.filter(&(&1.type == "gallery"))
      |> Enum.map(& &1.id)

    inherited_gallery_ids =
      inherited_groups
      |> Enum.flat_map(& &1.blocks)
      |> Enum.filter(&(&1.type == "gallery"))
      |> Enum.map(& &1.id)

    all_gallery_ids = own_gallery_ids ++ inherited_gallery_ids

    if all_gallery_ids != [], do: Sheets.batch_load_gallery_data(all_gallery_ids), else: %{}
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

  defp refresh_formula_editing(socket) do
    case socket.assigns.formula_editing do
      nil ->
        socket

      %{row_id: row_id, column_slug: slug} = fe ->
        row = Sheets.get_table_row!(row_id)
        assign(socket, :formula_editing, %{fe | value: row.cells[slug]})
    end
  end

  # ===========================================================================
  # Formula Sidebar Content
  # ===========================================================================

  defp formula_sidebar_content(assigns) do
    expr = formula_cell_expression(assigns.formula.value)
    symbols = formula_symbols(expr)

    # Include number and formula variables (constants are now included in project_variables)
    numeric_vars = Enum.filter(assigns.variables, &(&1.block_type in ["number", "formula"]))
    vars_by_sheet = Enum.group_by(numeric_vars, & &1.sheet_shortcut)
    same_row_cols = Enum.filter(assigns.formula.columns, &(&1.type in ["number", "formula"]))

    assigns =
      assigns
      |> assign(:expr, expr)
      |> assign(:symbols, symbols)
      |> assign(:vars_by_sheet, vars_by_sheet)
      |> assign(:same_row_cols, same_row_cols)

    ~H"""
    <%!-- Header --%>
    <div class="flex items-center justify-between px-4 py-3 border-b border-base-300">
      <div class="flex items-center gap-2">
        <.icon name="sigma" class="size-4 opacity-60" />
        <span class="font-semibold text-sm">{dgettext("sheets", "Formula Editor")}</span>
      </div>
      <button
        type="button"
        class="btn btn-ghost btn-xs btn-square"
        phx-click="close_formula_sidebar"
        phx-target={@target}
      >
        <.icon name="x" class="size-4" />
      </button>
    </div>

    <%!-- Scrollable content --%>
    <div class="flex-1 overflow-y-auto p-4 space-y-4">
      <%!-- Expression input --%>
      <div>
        <label class="text-xs font-medium opacity-70 mb-1 block">
          {dgettext("sheets", "Expression")}
        </label>
        <input
          type="text"
          value={@expr}
          placeholder="a - 3"
          class="input input-sm input-bordered w-full font-mono"
          phx-blur="save_formula_expression"
          phx-value-row-id={@formula.row_id}
          phx-value-column-slug={@formula.column_slug}
          phx-target={@target}
        />
      </div>

      <%!-- Symbol bindings (searchable combobox per symbol) --%>
      <div :if={@symbols != []} class="space-y-3">
        <label class="text-xs font-medium opacity-70 block">
          {dgettext("sheets", "Variable Bindings")}
        </label>

        <div :for={sym <- @symbols} class="flex items-center gap-2">
          <span class="text-sm font-mono font-bold text-primary w-8 text-center shrink-0">
            {sym}
          </span>
          <span class="text-xs opacity-40">=</span>
          <div
            id={"formula-binding-#{@formula.row_id}-#{@formula.column_slug}-#{sym}"}
            phx-hook="FormulaBinding"
            phx-update="ignore"
            data-symbol={sym}
            data-value={formula_cell_binding(@formula.value, sym)}
            data-display={formula_binding_display(@formula.value, sym, @same_row_cols)}
            data-options={Jason.encode!(build_binding_options(@same_row_cols, @vars_by_sheet))}
            data-row-id={@formula.row_id}
            data-column-slug={@formula.column_slug}
            class="flex-1"
          >
          </div>
        </div>
      </div>

      <%!-- LaTeX preview — keep this below bindings --%>
      <div :if={@expr != ""} class="p-3 bg-base-300/50 rounded-lg">
        <label class="text-xs font-medium opacity-70 mb-1 block">
          {dgettext("sheets", "Preview")}
        </label>
        <div class="text-sm font-mono opacity-80">
          {formula_preview_from_cell(@formula.value)}
        </div>
      </div>
    </div>
    """
  end
end
