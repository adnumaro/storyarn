defmodule StoryarnWeb.SheetLive.ShowV2 do
  @moduledoc """
  V2 Sheet editor — Phase 1: Header only (banner, avatar, title, color).
  Same backend logic as SheetLive.Show, Vue + shadcn UI.
  """

  use StoryarnWeb, :live_view
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Helpers.UndoRedoStack
  alias StoryarnWeb.SheetLive.Handlers.{TableHandlers, UndoRedoHandlers}

  import StoryarnWeb.Live.Shared.TreePanelHandlers
  import StoryarnWeb.SheetLive.Helpers.FormulaHelpers

  @formula_page_size 20

  alias Storyarn.Assets
  alias Storyarn.Billing
  alias Storyarn.Collaboration
  alias Storyarn.Projects
  alias Storyarn.Sheets
  alias Storyarn.Shared.FormulaEngine

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.focus_v2
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:sheets}
      has_tree={true}
      tree_panel_open={@tree_panel_open}
      tree_panel_pinned={@tree_panel_pinned}
      can_edit={@can_edit}
      tree_props={
        %{
          sheetsTree: @sheets_tree,
          canEdit: @can_edit,
          workspaceSlug: @workspace.slug,
          projectSlug: @project.slug,
          selectedSheetId: @sheet && @sheet.id
        }
      }
    >
      <div
        :if={@sheet}
        class="max-w-4xl mx-auto bg-card border border-border rounded-2xl p-6 mb-8 shadow-sm"
      >
        <.vue
          v-component="sheets/SheetHeader"
          v-socket={@socket}
          id="sheet-header"
          sheet={prepare_sheet_for_vue(@sheet)}
          can-edit={@can_edit}
          is-draft={@is_draft}
          source-shortcut={@source_shortcut}
        />
        <div class="px-4 pb-6">
          <.vue
            v-component="sheets/BlockList"
            v-socket={@socket}
            id="block-list"
            blocks={prepare_blocks_for_vue(@blocks, @gallery_data, @table_data)}
            inherited-groups={prepare_inherited_groups_for_vue(@inherited_groups, @gallery_data, @table_data)}
            workspace-slug={@workspace.slug}
            project-slug={@project.slug}
            can-edit={@can_edit}
            formula-editing={build_formula_editing_for_vue(@formula_editing, @formula_search_results, @formula_search_has_more)}
          />
        </div>
      </div>

      <div :if={!@sheet} class="flex justify-center py-20">
        <div class="size-6 border-2 border-muted-foreground/20 border-t-muted-foreground/60 rounded-full animate-spin" />
      </div>
    </Layouts.focus_v2>
    """
  end

  # ===========================================================================
  # Mount & Lifecycle
  # ===========================================================================

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
        can_edit = Projects.can?(membership.role, :edit_content)

        {:ok,
         socket
         |> assign(focus_layout_defaults())
         |> assign(:project, project)
         |> assign(:workspace, project.workspace)
         |> assign(:membership, membership)
         |> assign(:can_edit, can_edit)
         |> assign(:sheet, nil)
         |> assign(:blocks, [])
         |> assign(:inherited_groups, [])
         |> assign(:gallery_data, %{})
         |> assign(:table_data, %{})
         |> assign(:sheets_tree, prepare_tree(Sheets.list_sheets_tree(project.id)))
         |> assign(:is_draft, false)
         |> assign(:source_shortcut, nil)
         |> assign(:pending_delete_id, nil)
         |> assign(:formula_editing, nil)
         |> assign(:formula_search_results, [])
         |> assign(:formula_search_query, "")
         |> assign(:formula_search_offset, 0)
         |> assign(:formula_search_has_more, false)
         |> UndoRedoStack.init()}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("sheets", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(%{"id" => sheet_id}, _url, socket) do
    current_sheet_id =
      case socket.assigns.sheet do
        %{id: id} -> to_string(id)
        _ -> nil
      end

    if sheet_id == current_sheet_id do
      {:noreply, socket}
    else
      {:noreply, load_sheet(socket, sheet_id)}
    end
  end

  defp load_sheet(socket, sheet_id) do
    %{project: project} = socket.assigns

    case Sheets.get_sheet_full(project.id, sheet_id) do
      nil ->
        socket
        |> put_flash(:error, dgettext("sheets", "Sheet not found."))
        |> push_navigate(
          to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/v2/sheets"
        )

      sheet ->
        {inherited_groups, own_blocks} = Sheets.get_sheet_blocks_grouped(sheet.id)
        all_blocks = Enum.flat_map(inherited_groups, & &1.blocks) ++ own_blocks

        gallery_block_ids =
          all_blocks |> Enum.filter(&(&1.type == "gallery")) |> Enum.map(& &1.id)

        gallery_data =
          if gallery_block_ids != [],
            do: Sheets.batch_load_gallery_data(gallery_block_ids),
            else: %{}

        table_block_ids =
          all_blocks |> Enum.filter(&(&1.type == "table")) |> Enum.map(& &1.id)

        table_data =
          if table_block_ids != [],
            do:
              Sheets.batch_load_table_data(table_block_ids)
              |> compute_formulas(project.id),
            else: %{}

        socket
        |> assign(:sheet, sheet)
        |> assign(:blocks, own_blocks)
        |> assign(:inherited_groups, inherited_groups)
        |> assign(:gallery_data, gallery_data)
        |> assign(:table_data, table_data)
    end
  end

  # ===========================================================================
  # Event Handlers: Header
  # ===========================================================================

  @impl true
  def handle_event("tree_panel_" <> _ = event, params, socket),
    do: handle_tree_panel_event(event, params, socket)

  # --- Title / Shortcut ---

  def handle_event("save_name", %{"name" => name}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      sheet = socket.assigns.sheet

      case Sheets.update_sheet(sheet, %{name: name}) do
        {:ok, updated_sheet} ->
          sheets_tree = prepare_tree(Sheets.list_sheets_tree(socket.assigns.project.id))

          if name != sheet.name do
            Sheets.maybe_create_version(updated_sheet, socket.assigns.current_scope.user.id)
          end

          {:noreply,
           socket
           |> assign(:sheet, Sheets.get_sheet_full!(socket.assigns.project.id, sheet.id))
           |> assign(:sheets_tree, sheets_tree)}

        {:error, _changeset} ->
          {:noreply, socket}
      end
    end)
  end

  def handle_event("save_shortcut", %{"shortcut" => shortcut}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      sheet = socket.assigns.sheet
      shortcut = if shortcut == "", do: nil, else: shortcut

      case Sheets.update_sheet(sheet, %{shortcut: shortcut}) do
        {:ok, _updated_sheet} ->
          updated_sheet = Sheets.get_sheet_full!(socket.assigns.project.id, sheet.id)

          if shortcut != sheet.shortcut do
            Sheets.maybe_create_version(updated_sheet, socket.assigns.current_scope.user.id)
          end

          {:noreply, assign(socket, :sheet, updated_sheet)}

        {:error, changeset} ->
          error_msg =
            case changeset.errors[:shortcut] do
              {msg, _opts} -> dgettext("sheets", "Shortcut %{error}", error: msg)
              nil -> dgettext("sheets", "Could not save shortcut.")
            end

          {:noreply, put_flash(socket, :error, error_msg)}
      end
    end)
  end

  # --- Color ---

  def handle_event("set_sheet_color", %{"color" => color}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      update_sheet_field(socket, %{color: color})
    end)
  end

  def handle_event("clear_sheet_color", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      update_sheet_field(socket, %{color: nil})
    end)
  end

  # --- Banner ---

  def handle_event("remove_banner", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      sheet = socket.assigns.sheet

      case Sheets.update_sheet(sheet, %{banner_asset_id: nil}) do
        {:ok, _} ->
          {:noreply, reload_sheet(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not remove banner."))}
      end
    end)
  end

  def handle_event(
        "upload_banner",
        %{"filename" => filename, "content_type" => content_type, "data" => data},
        socket
      ) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with [_header, base64_data] <- String.split(data, ",", parts: 2),
           {:ok, binary_data} <- Base.decode64(base64_data) do
        upload_asset(socket, filename, content_type, binary_data, :banner)
      else
        _ ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Invalid file data."))}
      end
    end)
  end

  # --- Avatars ---

  def handle_event(
        "upload_avatar",
        %{"filename" => filename, "content_type" => content_type, "data" => data},
        socket
      ) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with [_header, base64_data] <- String.split(data, ",", parts: 2),
           {:ok, binary_data} <- Base.decode64(base64_data) do
        upload_asset(socket, filename, content_type, binary_data, :avatar)
      else
        _ ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Invalid file data."))}
      end
    end)
  end

  def handle_event("remove_avatar", %{"id" => id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      id = parse_id(id)

      case Sheets.remove_avatar(id) do
        {:ok, _} ->
          {:noreply, reload_sheet_and_tree(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not remove avatar."))}
      end
    end)
  end

  def handle_event("set_default_avatar", %{"id" => id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      id = parse_id(id)
      avatar = Sheets.get_avatar(id)

      if avatar && avatar.sheet_id == socket.assigns.sheet.id do
        Sheets.set_avatar_default(avatar)
        {:noreply, reload_sheet_and_tree(socket)}
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_event("gallery_update_name", %{"id" => id, "value" => value}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with avatar when not is_nil(avatar) <- Sheets.get_avatar(parse_id(id)),
           true <- avatar.sheet_id == socket.assigns.sheet.id do
        Sheets.update_avatar(avatar, %{name: value})
        {:noreply, reload_sheet(socket)}
      else
        _ -> {:noreply, socket}
      end
    end)
  end

  def handle_event("gallery_update_notes", %{"id" => id, "value" => value}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with avatar when not is_nil(avatar) <- Sheets.get_avatar(parse_id(id)),
           true <- avatar.sheet_id == socket.assigns.sheet.id do
        Sheets.update_avatar(avatar, %{notes: value})
        {:noreply, reload_sheet(socket)}
      else
        _ -> {:noreply, socket}
      end
    end)
  end

  # --- Blocks ---

  def handle_event("add_block", %{"type" => type}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case Sheets.create_block(socket.assigns.sheet, %{type: type}) do
        {:ok, block} ->
          snapshot = UndoRedoHandlers.block_to_snapshot(block)

          {:noreply,
           socket
           |> UndoRedoStack.push_undo({:create_block, snapshot})
           |> reload_blocks()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not create block."))}
      end
    end)
  end

  def handle_event("update_block_value", %{"id" => id, "value" => value}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(parse_id(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        prev = get_in(block.value, ["content"])

        case Sheets.update_block_value(block, %{"content" => value}) do
          {:ok, _} ->
            {:noreply,
             socket
             |> UndoRedoHandlers.push_block_value_coalesced(block.id, prev, value)
             |> reload_blocks()}

          {:error, _} ->
            {:noreply, socket}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_event("toggle_multi_select", %{"id" => id, "key" => key}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(parse_id(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        current = get_in(block.value, ["content"]) || []

        new_content =
          if key in current,
            do: List.delete(current, key),
            else: current ++ [key]

        case Sheets.update_block_value(block, %{"content" => new_content}) do
          {:ok, _} -> {:noreply, reload_blocks(socket)}
          {:error, _} -> {:noreply, socket}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_event(
        "update_block_config",
        %{"id" => id, "field" => field, "value" => value},
        socket
      ) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(parse_id(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        new_config = Map.put(block.config || %{}, field, value)

        case Sheets.update_block_config(block, new_config) do
          {:ok, _} -> {:noreply, reload_blocks(socket)}
          {:error, _} -> {:noreply, socket}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_event("delete_block", %{"id" => id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(parse_id(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        snapshot = UndoRedoHandlers.block_to_snapshot(block)

        case Sheets.delete_block(block) do
          {:ok, _} ->
            {:noreply,
             socket
             |> UndoRedoStack.push_undo({:delete_block, snapshot})
             |> reload_blocks()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not delete block."))}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_event("duplicate_block", %{"id" => id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(parse_id(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        case Sheets.duplicate_block(block) do
          {:ok, new_block} ->
            snapshot = UndoRedoHandlers.block_to_snapshot(new_block)

            {:noreply,
             socket
             |> UndoRedoStack.push_undo({:create_block, snapshot})
             |> reload_blocks()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not duplicate block."))}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_event("undo", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case UndoRedoHandlers.handle_undo(params, socket) do
        {:noreply, socket} -> {:noreply, reload_blocks(socket)}
      end
    end)
  end

  def handle_event("redo", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case UndoRedoHandlers.handle_redo(params, socket) do
        {:noreply, socket} -> {:noreply, reload_blocks(socket)}
      end
    end)
  end

  def handle_event("reorder_column_group", %{"group_id" => _group_id, "items" => items}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      Enum.each(items, fn item ->
        block = Sheets.get_block(parse_id(item["id"]))

        if block && block.sheet_id == socket.assigns.sheet.id do
          Sheets.update_block(block, %{column_index: item["column_index"]})
        end
      end)

      {:noreply, reload_blocks(socket)}
    end)
  end

  def handle_event("reorder_with_columns", %{"items" => items}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      sanitized =
        items
        |> Enum.map(fn item ->
          %{
            id: parse_id(item["id"]),
            column_group_id: normalize_column_group_id(item["column_group_id"]),
            column_index: item["column_index"] || 0
          }
        end)

      sheet_id = socket.assigns.sheet.id

      prev_layout =
        Sheets.list_blocks(sheet_id)
        |> Enum.sort_by(& &1.position)
        |> Enum.map(fn b ->
          %{id: b.id, column_group_id: b.column_group_id, column_index: b.column_index}
        end)

      case Sheets.reorder_blocks_with_columns(sheet_id, sanitized) do
        {:ok, _} ->
          {:noreply,
           socket
           |> UndoRedoStack.push_undo({:reorder_blocks_with_columns, prev_layout, sanitized})
           |> reload_blocks()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not reorder blocks."))}
      end
    end)
  end

  # --- Block toolbar ---

  def handle_event("toggle_constant", %{"id" => id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(parse_id(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        prev = block.is_constant

        case Sheets.update_block(block, %{is_constant: !prev}) do
          {:ok, _} ->
            {:noreply,
             socket
             |> UndoRedoStack.push_undo({:toggle_constant, block.id, prev, !prev})
             |> reload_blocks()}

          {:error, _} ->
            {:noreply, socket}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_event("update_variable_name", %{"id" => id, "variable_name" => name}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(parse_id(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        Sheets.update_variable_name(block, name)
        {:noreply, reload_blocks(socket)}
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_event("change_block_scope", %{"id" => id, "scope" => scope}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(parse_id(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        Sheets.update_block(block, %{scope: scope})
        {:noreply, reload_blocks(socket)}
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_event("toggle_required", %{"id" => id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(parse_id(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        Sheets.update_block(block, %{required: !block.required})
        {:noreply, reload_blocks(socket)}
      else
        {:noreply, socket}
      end
    end)
  end

  # --- Block reorder ---

  def handle_event("reorder_blocks", %{"ids" => ids}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      int_ids = Enum.map(ids, &parse_id/1)
      prev_ids = Sheets.list_blocks(socket.assigns.sheet.id) |> Enum.map(& &1.id)

      case Sheets.reorder_blocks(socket.assigns.sheet.id, int_ids) do
        {:ok, _} ->
          {:noreply,
           socket
           |> UndoRedoStack.push_undo({:reorder_blocks, prev_ids, int_ids})
           |> reload_blocks()}

        {:error, _} ->
          {:noreply, reload_blocks(socket)}
      end
    end)
  end

  # --- Inheritance ---

  def handle_event("detach_block", %{"id" => id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(parse_id(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        case Sheets.detach_block(block) do
          {:ok, _} ->
            {:noreply, reload_blocks(socket)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not detach block."))}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_event("reattach_block", %{"id" => id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(parse_id(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        case Sheets.reattach_block(block) do
          {:ok, _} ->
            {:noreply, reload_blocks(socket)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not reattach block."))}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  # --- Gallery blocks ---

  def handle_event(
        "upload_gallery_image",
        %{
          "block_id" => block_id,
          "filename" => filename,
          "content_type" => content_type,
          "data" => data
        },
        socket
      ) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(parse_id(block_id))

      if block && block.sheet_id == socket.assigns.sheet.id && block.type == "gallery" do
        with [_header, base64_data] <- String.split(data, ",", parts: 2),
             {:ok, binary_data} <- Base.decode64(base64_data) do
          case Billing.can_upload_asset_for_project?(
                 socket.assigns.project,
                 byte_size(binary_data)
               ) do
            :ok ->
              case Assets.upload_binary_and_create_asset(
                     binary_data,
                     %{filename: filename, content_type: content_type, purpose: :gallery},
                     socket.assigns.project,
                     socket.assigns.current_scope.user
                   ) do
                {:ok, asset} ->
                  Sheets.add_gallery_image(block, asset.id)
                  {:noreply, reload_blocks(socket)}

                {:error, _} ->
                  {:noreply,
                   put_flash(socket, :error, dgettext("sheets", "Could not upload image."))}
              end

            {:error, :limit_reached, _} ->
              {:noreply, put_flash(socket, :error, dgettext("sheets", "Storage limit reached."))}
          end
        else
          _ -> {:noreply, put_flash(socket, :error, dgettext("sheets", "Invalid file data."))}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_event(
        "update_gallery_image",
        %{"gallery_image_id" => id, "field" => field, "value" => value},
        socket
      ) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case Sheets.get_gallery_image(parse_id(id)) do
        nil ->
          {:noreply, socket}

        gi ->
          Sheets.update_gallery_image(gi, %{String.to_existing_atom(field) => value})
          {:noreply, reload_blocks(socket)}
      end
    end)
  end

  def handle_event("remove_gallery_image", %{"gallery_image_id" => id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case Sheets.remove_gallery_image(parse_id(id)) do
        {:ok, _} -> {:noreply, reload_blocks(socket)}
        _ -> {:noreply, socket}
      end
    end)
  end

  def handle_event("reorder_gallery_images", %{"block_id" => block_id, "ids" => ids}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      int_ids = Enum.map(ids, &parse_id/1)
      Sheets.reorder_gallery_images(parse_id(block_id), int_ids)
      {:noreply, reload_blocks(socket)}
    end)
  end

  # --- Table blocks ---

  def handle_event("add_table_column", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_add_column(params, socket, table_helpers(socket))
    end)
  end

  def handle_event("add_table_row", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_add_row(params, socket, table_helpers(socket))
    end)
  end

  def handle_event("update_table_cell", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_update_cell(params, socket, table_helpers(socket))
    end)
  end

  def handle_event("toggle_table_cell_boolean", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_toggle_cell_boolean(params, socket, table_helpers(socket))
    end)
  end

  def handle_event("select_table_cell", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_select_table_cell(params, socket, table_helpers(socket))
    end)
  end

  def handle_event("toggle_table_collapse", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_toggle_collapse(params, socket, table_helpers(socket))
    end)
  end

  def handle_event("rename_table_column", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_rename_column(params, socket, table_helpers(socket))
    end)
  end

  def handle_event("rename_table_row", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_rename_row(params, socket, table_helpers(socket))
    end)
  end

  def handle_event("delete_table_column", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_delete_column(params, socket, table_helpers(socket))
    end)
  end

  def handle_event("delete_table_row", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_delete_row(params, socket, table_helpers(socket))
    end)
  end

  def handle_event("reorder_table_rows", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_reorder_rows(params, socket, table_helpers(socket))
    end)
  end

  def handle_event("resize_table_column", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_resize_column(params, socket)
    end)
  end

  def handle_event("change_table_column_type", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_change_column_type(params, socket, table_helpers(socket))
    end)
  end

  def handle_event("toggle_table_column_constant", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_toggle_column_constant(params, socket, table_helpers(socket))
    end)
  end

  def handle_event("toggle_table_column_required", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_toggle_column_required(params, socket, table_helpers(socket))
    end)
  end

  def handle_event("toggle_reference_multiple", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_toggle_reference_multiple(params, socket, table_helpers(socket))
    end)
  end

  def handle_event("update_number_constraint", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_update_number_constraint(params, socket, table_helpers(socket))
    end)
  end

  def handle_event("toggle_table_cell_multi_select", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_toggle_table_cell_multi_select(params, socket, table_helpers(socket))
    end)
  end

  def handle_event("add_table_cell_option", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_add_table_cell_option(params, socket, table_helpers(socket))
    end)
  end

  def handle_event("add_table_column_option", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_add_column_option(params, socket, table_helpers(socket))
    end)
  end

  def handle_event("remove_table_column_option", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_remove_column_option(params, socket, table_helpers(socket))
    end)
  end

  def handle_event("update_table_column_option", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_update_column_option(params, socket, table_helpers(socket))
    end)
  end

  # --- Formula sidebar ---

  def handle_event("open_formula_sidebar", params, socket) do
    row_id = parse_id(params["row-id"])
    block_id = parse_id(params["block-id"])
    slug = params["column-slug"]

    table_entry = Map.get(socket.assigns.table_data, block_id, %{columns: [], rows: []})
    enriched_row = Enum.find(table_entry.rows, &(&1.id == row_id))
    row = enriched_row || Sheets.get_table_row!(row_id)

    all_blocks =
      socket.assigns.blocks ++
        Enum.flat_map(socket.assigns.inherited_groups, fn g -> g.blocks end)

    table_name =
      case Enum.find(all_blocks, &(&1.id == block_id)) do
        nil -> nil
        block -> block.config["label"]
      end

    column_name =
      case Enum.find(table_entry.columns, &(&1.slug == slug)) do
        nil -> nil
        col -> col.name
      end

    {:noreply,
     assign(socket, :formula_editing, %{
       row_id: row_id,
       column_slug: slug,
       block_id: block_id,
       value: row.cells[slug],
       columns: table_entry.columns,
       table_name: table_name,
       row_name: row.name,
       column_name: column_name
     })}
  end

  def handle_event("close_formula_sidebar", _params, socket) do
    {:noreply, assign(socket, :formula_editing, nil)}
  end

  def handle_event("save_formula_expression", %{"value" => expression} = params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
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
          table_helpers(socket)
        )

      {:noreply, refresh_formula_editing(updated_socket)}
    end)
  end

  def handle_event(
        "save_formula_binding",
        %{"binding_value" => value, "symbol" => symbol} = params,
        socket
      ) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
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
          table_helpers(socket)
        )

      {:noreply, refresh_formula_editing(updated_socket)}
    end)
  end

  def handle_event("search_formula_bindings", %{"query" => query}, socket) do
    {results, has_more} = search_binding_variables(socket.assigns.project.id, query, 0)

    {:noreply,
     socket
     |> assign(:formula_search_results, results)
     |> assign(:formula_search_query, query)
     |> assign(:formula_search_offset, @formula_page_size)
     |> assign(:formula_search_has_more, has_more)}
  end

  def handle_event("load_more_formula_bindings", _params, socket) do
    query = socket.assigns.formula_search_query
    offset = ensure_integer(socket.assigns.formula_search_offset)

    {new_results, has_more} =
      search_binding_variables(socket.assigns.project.id, query, offset)

    merged = merge_search_results(socket.assigns.formula_search_results, new_results)
    next_offset = offset + @formula_page_size

    {:noreply,
     socket
     |> assign(:formula_search_results, merged)
     |> assign(:formula_search_offset, next_offset)
     |> assign(:formula_search_has_more, has_more)}
  end

  # Tree events (create, delete, move)
  def handle_event("create_sheet", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case Sheets.create_sheet(socket.assigns.project, %{name: dgettext("sheets", "Untitled")}) do
        {:ok, new_sheet} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/v2/sheets/#{new_sheet.id}"
           )}

        {:error, :limit_reached, _} ->
          {:noreply, put_flash(socket, :error, gettext("Item limit reached for your plan"))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not create sheet."))}
      end
    end)
  end

  def handle_event("create_child_sheet", %{"parent_id" => parent_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      attrs = %{name: dgettext("sheets", "New Sheet"), parent_id: parent_id}

      case Sheets.create_sheet(socket.assigns.project, attrs) do
        {:ok, new_sheet} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/v2/sheets/#{new_sheet.id}"
           )}

        {:error, :limit_reached, _} ->
          {:noreply, put_flash(socket, :error, gettext("Item limit reached for your plan"))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not create sheet."))}
      end
    end)
  end

  def handle_event(event, %{"id" => id}, socket)
      when event in ~w(set_pending_delete_sheet) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_event("confirm_delete_sheet", _params, socket) do
    if id = socket.assigns[:pending_delete_id] do
      Authorize.with_authorization(socket, :edit_content, fn socket ->
        with %{} = sheet <- Sheets.get_sheet(socket.assigns.project.id, id),
             {:ok, _} <- Sheets.delete_sheet(sheet) do
          {:noreply,
           socket
           |> put_flash(:info, dgettext("sheets", "Sheet moved to trash."))
           |> assign(
             :sheets_tree,
             prepare_tree(Sheets.list_sheets_tree(socket.assigns.project.id))
           )}
        else
          _ ->
            {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not delete sheet."))}
        end
      end)
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "move_to_parent",
        %{"item_id" => id, "new_parent_id" => new_parent_id, "position" => position},
        socket
      ) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      sheet = Sheets.get_sheet(socket.assigns.project.id, parse_id(id))

      if sheet do
        parsed_parent = if new_parent_id in [nil, ""], do: nil, else: parse_id(new_parent_id)
        parsed_pos = parse_id(position) || 0

        case Sheets.move_sheet_to_position(sheet, parsed_parent, parsed_pos) do
          {:ok, _} ->
            {:noreply,
             assign(socket, :sheets_tree,
               prepare_tree(Sheets.list_sheets_tree(socket.assigns.project.id))
             )}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, dgettext("sheets", "Could not move sheet."))}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  # ===========================================================================
  # Handle Info
  # ===========================================================================

  @impl true
  def handle_info({:table_push_undo, action}, socket) do
    {:noreply, UndoRedoStack.push_undo(socket, action)}
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp table_helpers(_socket) do
    pid = self()

    %{
      reload_blocks: &reload_blocks/1,
      maybe_create_version: fn _socket -> :ok end,
      notify_parent: fn _socket, _status -> :ok end,
      push_undo: fn action -> send(pid, {:table_push_undo, action}) end
    }
  end

  defp compute_formulas(table_data, project_id) do
    alias Storyarn.Sheets.FormulaResolver

    Map.new(table_data, fn {block_id, %{columns: cols, rows: rows} = data} ->
      formula_cols = Enum.filter(cols, &(&1.type == "formula"))

      if formula_cols == [] do
        {block_id, data}
      else
        computed =
          try do
            FormulaResolver.compute_all(cols, rows, project_id)
          rescue
            _ -> %{}
          end

        enriched_rows =
          Enum.map(rows, fn row ->
            formula_results = Map.get(computed, row.id, %{})

            updated_cells =
              Enum.reduce(formula_results, row.cells, fn {slug, %{result: result} = computed_entry}, cells ->
                current = cells[slug]
                resolved = Map.get(computed_entry, :resolved, %{})

                enriched =
                  if is_map(current),
                    do: current |> Map.put("__result", result) |> Map.put("__resolved", resolved),
                    else: %{"__result" => result, "__resolved" => resolved}

                Map.put(cells, slug, enriched)
              end)

            %{row | cells: updated_cells}
          end)

        {block_id, %{data | rows: enriched_rows}}
      end
    end)
  end

  defp refresh_formula_editing(socket) do
    case socket.assigns.formula_editing do
      nil ->
        socket

      %{row_id: row_id, column_slug: slug, block_id: block_id} = fe ->
        table_entry = Map.get(socket.assigns.table_data, block_id, %{columns: [], rows: []})
        enriched_row = Enum.find(table_entry.rows, &(&1.id == row_id))
        row = enriched_row || Sheets.get_table_row!(row_id)
        assign(socket, :formula_editing, %{fe | value: row.cells[slug]})
    end
  end

  defp build_formula_editing_for_vue(nil, _search_results, _has_more), do: nil

  defp build_formula_editing_for_vue(fe, search_results, has_more) do
    cell_value = fe.value
    expr = formula_cell_expression(cell_value)
    symbols = formula_symbols(expr)

    # Same-row columns (number + formula, excluding current column) — always small/bounded
    same_row_options =
      (fe.columns || [])
      |> Enum.filter(fn c -> c.type in ["number", "formula"] and c.slug != fe.column_slug end)
      |> Enum.map(fn c -> %{value: "same_row:" <> c.slug, label: c.name} end)

    # Per-symbol current bindings
    symbol_bindings =
      Map.new(symbols, fn s ->
        {s, formula_cell_binding(cell_value, s)}
      end)

    # Pre-compute LaTeX strings
    preview_latex = formula_preview_from_cell(cell_value)
    result_latex = formula_result_latex(cell_value)

    # Validation error
    parse_error =
      if expr != "" do
        case FormulaEngine.parse(expr) do
          {:ok, _} -> nil
          {:error, reason} -> reason
        end
      end

    %{
      row_id: fe.row_id,
      column_slug: fe.column_slug,
      block_id: fe.block_id,
      table_name: fe.table_name,
      row_name: fe.row_name,
      column_name: fe.column_name,
      expression: expr,
      symbols: symbols,
      symbol_bindings: symbol_bindings,
      same_row_options: same_row_options,
      search_results: search_results,
      has_more: has_more || false,
      preview_latex: preview_latex,
      result_latex: result_latex,
      parse_error: parse_error,
      result: formula_cell_result(cell_value)
    }
  end

  # Returns {grouped_results, has_more}
  defp search_binding_variables(project_id, query, offset) do
    all_vars = Sheets.list_project_variables(project_id)

    filtered =
      all_vars
      |> Enum.filter(fn v -> v.block_type in ["number", "formula"] end)
      |> then(fn vars ->
        if query == "" do
          vars
        else
          q = String.downcase(query)

          Enum.filter(vars, fn v ->
            String.contains?(String.downcase(v.variable_name), q) or
              String.contains?(String.downcase(v.sheet_shortcut), q)
          end)
        end
      end)

    total = length(filtered)
    page = filtered |> Enum.drop(offset) |> Enum.take(@formula_page_size)
    has_more = offset + @formula_page_size < total

    grouped =
      page
      |> Enum.group_by(fn v -> v.sheet_shortcut end)
      |> Enum.sort_by(fn {sheet, _} -> sheet end)
      |> Enum.map(fn {sheet_shortcut, vars} ->
        %{
          heading: sheet_shortcut,
          items:
            Enum.map(vars, fn v ->
              %{value: sheet_shortcut <> "." <> v.variable_name, label: v.variable_name}
            end)
        }
      end)

    {grouped, has_more}
  end

  # Merge new page results into existing grouped results
  defp merge_search_results(existing, new_page) do
    existing_map = Map.new(existing, fn g -> {g.heading, g.items} end)

    Enum.reduce(new_page, existing_map, fn group, acc ->
      existing_items = Map.get(acc, group.heading, [])
      Map.put(acc, group.heading, existing_items ++ group.items)
    end)
    |> Enum.sort_by(fn {heading, _} -> heading end)
    |> Enum.map(fn {heading, items} -> %{heading: heading, items: items} end)
  end

  defp reload_sheet(socket) do
    sheet = Sheets.get_sheet_full!(socket.assigns.project.id, socket.assigns.sheet.id)
    assign(socket, :sheet, sheet)
  end

  defp reload_blocks(socket) do
    sheet_id = socket.assigns.sheet.id
    {inherited_groups, own_blocks} = Sheets.get_sheet_blocks_grouped(sheet_id)
    all_blocks = Enum.flat_map(inherited_groups, & &1.blocks) ++ own_blocks

    gallery_block_ids = all_blocks |> Enum.filter(&(&1.type == "gallery")) |> Enum.map(& &1.id)

    gallery_data =
      if gallery_block_ids != [], do: Sheets.batch_load_gallery_data(gallery_block_ids), else: %{}

    table_block_ids = all_blocks |> Enum.filter(&(&1.type == "table")) |> Enum.map(& &1.id)

    project_id = socket.assigns.project.id

    table_data =
      if table_block_ids != [],
        do:
          Sheets.batch_load_table_data(table_block_ids)
          |> compute_formulas(project_id),
        else: %{}

    socket
    |> assign(:blocks, own_blocks)
    |> assign(:inherited_groups, inherited_groups)
    |> assign(:gallery_data, gallery_data)
    |> assign(:table_data, table_data)
  end

  defp reload_sheet_and_tree(socket) do
    socket
    |> reload_sheet()
    |> assign(:sheets_tree, prepare_tree(Sheets.list_sheets_tree(socket.assigns.project.id)))
  end

  defp update_sheet_field(socket, attrs) do
    case Sheets.update_sheet(socket.assigns.sheet, attrs) do
      {:ok, _} -> {:noreply, reload_sheet(socket)}
      {:error, _} -> {:noreply, socket}
    end
  end

  defp upload_asset(socket, filename, content_type, binary_data, purpose) do
    project = socket.assigns.project

    case Billing.can_upload_asset_for_project?(project, byte_size(binary_data)) do
      :ok ->
        user = socket.assigns.current_scope.user
        sheet = socket.assigns.sheet

        case Assets.upload_binary_and_create_asset(
               binary_data,
               %{filename: filename, content_type: content_type, purpose: purpose},
               project,
               user
             ) do
          {:ok, asset} ->
            case purpose do
              :banner ->
                Sheets.update_sheet(sheet, %{banner_asset_id: asset.id})

              :avatar ->
                Sheets.add_avatar(sheet, asset.id)
            end

            Collaboration.broadcast_change({:assets, project.id}, :asset_created, %{})
            {:noreply, reload_sheet_and_tree(socket)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not upload file."))}
        end

      {:error, :limit_reached, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("sheets", "Storage limit reached. Upgrade your plan.")
         )}
    end
  end

  defp prepare_sheet_for_vue(nil), do: nil

  defp prepare_sheet_for_vue(sheet) do
    avatars =
      case sheet.avatars do
        list when is_list(list) ->
          list
          |> Enum.sort_by(& &1.position)
          |> Enum.map(fn a ->
            %{
              id: a.id,
              url: Assets.display_url(a.asset),
              name: a.name,
              notes: a.notes,
              is_default: a.is_default
            }
          end)

        _ ->
          []
      end

    %{
      id: sheet.id,
      name: sheet.name,
      shortcut: sheet.shortcut,
      color: sheet.color,
      bannerUrl: banner_url(sheet),
      avatars: avatars
    }
  end

  defp banner_url(%{banner_asset: %{} = asset}), do: Assets.display_url(asset)
  defp banner_url(_), do: nil

  defp prepare_inherited_groups_for_vue(groups, gallery_data, table_data) do
    Enum.map(groups, fn group ->
      %{
        sourceSheet: %{
          id: group.source_sheet.id,
          name: group.source_sheet.name
        },
        blocks: prepare_blocks_for_vue_raw(group.blocks, gallery_data, table_data)
      }
    end)
  end

  defp prepare_blocks_for_vue(blocks, gallery_data, table_data) do
    raw =
      blocks
      |> Enum.sort_by(& &1.position)
      |> prepare_blocks_for_vue_raw(gallery_data, table_data)

    # Group by column_group_id into layout items
    raw
    |> Enum.chunk_by(& &1.column_group_id)
    |> Enum.flat_map(fn chunk ->
      case chunk do
        [%{column_group_id: nil} | _] ->
          Enum.map(chunk, fn b -> %{type: "full_width", block: b} end)

        [%{column_group_id: gid} | _] when not is_nil(gid) ->
          sorted = Enum.sort_by(chunk, & &1.column_index)
          [%{type: "column_group", group_id: gid, blocks: sorted, column_count: length(sorted)}]

        other ->
          Enum.map(other, fn b -> %{type: "full_width", block: b} end)
      end
    end)
  end

  defp prepare_blocks_for_vue_raw(blocks, gallery_data, table_data) do
    Enum.map(blocks, fn b ->
      base = %{
        id: b.id,
        type: b.type,
        position: b.position,
        is_constant: b.is_constant,
        variable_name: b.variable_name,
        scope: b.scope || "self",
        inherited: b.inherited_from_block_id != nil && !b.detached,
        detached: b.detached || false,
        required: b.required || false,
        column_group_id: b.column_group_id,
        column_index: b.column_index || 0,
        config: b.config || %{},
        value: b.value || %{}
      }

      cond do
        b.type == "gallery" ->
          images =
            Map.get(gallery_data, b.id, [])
            |> Enum.map(fn gi ->
              %{
                id: gi.id,
                url: Assets.display_url(gi.asset),
                label: gi.label,
                description: gi.description
              }
            end)

          Map.put(base, :gallery_images, images)

        b.type == "table" ->
          td = Map.get(table_data, b.id, %{columns: [], rows: []})

          columns =
            Enum.map(td.columns, fn c ->
              %{
                id: c.id,
                name: c.name,
                slug: c.slug,
                type: c.type,
                position: c.position,
                is_constant: c.is_constant,
                required: c.required,
                config: c.config || %{}
              }
            end)

          rows =
            Enum.map(td.rows, fn r ->
              %{id: r.id, name: r.name, slug: r.slug, position: r.position, cells: r.cells || %{}}
            end)

          collapsed = get_in(b.config, ["collapsed"]) || false

          base
          |> Map.put(:columns, columns)
          |> Map.put(:rows, rows)
          |> Map.put(:collapsed, collapsed)

        true ->
          base
      end
    end)
  end

  # Reused from index_v2
  defp prepare_tree(nodes) do
    Enum.map(nodes, fn node ->
      %{
        id: node.id,
        name: node.name,
        avatar_url: extract_avatar_url(node),
        children: prepare_tree(Map.get(node, :children, []))
      }
    end)
  end

  defp extract_avatar_url(%{avatars: avatars}) when is_list(avatars) do
    case Enum.find(avatars, & &1.is_default) || List.first(avatars) do
      %{asset: %{url: url}} when is_binary(url) -> url
      _ -> nil
    end
  end

  defp extract_avatar_url(_), do: nil

  defp parse_id(id) when is_binary(id), do: String.to_integer(id)
  defp parse_id(id) when is_integer(id), do: id

  @spec ensure_integer(integer()) :: integer()
  defp ensure_integer(n) when is_integer(n), do: n
  defp ensure_integer(_), do: 0

  defp normalize_column_group_id(nil), do: nil
  defp normalize_column_group_id(""), do: nil
  defp normalize_column_group_id(id) when is_binary(id), do: id
end
