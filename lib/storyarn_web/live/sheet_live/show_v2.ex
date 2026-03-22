defmodule StoryarnWeb.SheetLive.ShowV2 do
  @moduledoc """
  V2 Sheet editor — Phase 1: Header only (banner, avatar, title, color).
  Same backend logic as SheetLive.Show, Vue + shadcn UI.
  """

  use StoryarnWeb, :live_view
  alias StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Live.Shared.TreePanelHandlers

  alias Storyarn.Assets
  alias Storyarn.Billing
  alias Storyarn.Collaboration
  alias Storyarn.Projects
  alias Storyarn.Sheets

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
            blocks={prepare_blocks_for_vue(@blocks, @gallery_data)}
            inherited-groups={prepare_inherited_groups_for_vue(@inherited_groups, @gallery_data)}
            workspace-slug={@workspace.slug}
            project-slug={@project.slug}
            can-edit={@can_edit}
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
         |> assign(:sheets_tree, prepare_tree(Sheets.list_sheets_tree(project.id)))
         |> assign(:is_draft, false)
         |> assign(:source_shortcut, nil)
         |> assign(:pending_delete_id, nil)}

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

        socket
        |> assign(:sheet, sheet)
        |> assign(:blocks, own_blocks)
        |> assign(:inherited_groups, inherited_groups)
        |> assign(:gallery_data, gallery_data)
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
        {:ok, _block} ->
          {:noreply, reload_blocks(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not create block."))}
      end
    end)
  end

  def handle_event("update_block_value", %{"id" => id, "value" => value}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(parse_id(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        case Sheets.update_block_value(block, %{"content" => value}) do
          {:ok, _} -> {:noreply, reload_blocks(socket)}
          {:error, _} -> {:noreply, socket}
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
        case Sheets.delete_block(block) do
          {:ok, _} ->
            {:noreply, reload_blocks(socket)}

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
          {:ok, _} ->
            {:noreply, reload_blocks(socket)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not duplicate block."))}
        end
      else
        {:noreply, socket}
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

      case Sheets.reorder_blocks_with_columns(socket.assigns.sheet.id, sanitized) do
        {:ok, _} ->
          {:noreply, reload_blocks(socket)}

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
        Sheets.update_block(block, %{is_constant: !block.is_constant})
        {:noreply, reload_blocks(socket)}
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
      Sheets.reorder_blocks(socket.assigns.sheet.id, int_ids)
      {:noreply, reload_blocks(socket)}
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

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

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

    socket
    |> assign(:blocks, own_blocks)
    |> assign(:inherited_groups, inherited_groups)
    |> assign(:gallery_data, gallery_data)
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

  defp prepare_inherited_groups_for_vue(groups, gallery_data) do
    Enum.map(groups, fn group ->
      %{
        sourceSheet: %{
          id: group.source_sheet.id,
          name: group.source_sheet.name
        },
        blocks: prepare_blocks_for_vue_raw(group.blocks, gallery_data)
      }
    end)
  end

  defp prepare_blocks_for_vue(blocks, gallery_data) do
    raw =
      blocks
      |> Enum.sort_by(& &1.position)
      |> prepare_blocks_for_vue_raw(gallery_data)

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

  defp prepare_blocks_for_vue_raw(blocks, gallery_data) do
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

      if b.type == "gallery" do
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
      else
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

  defp normalize_column_group_id(nil), do: nil
  defp normalize_column_group_id(""), do: nil
  defp normalize_column_group_id(id) when is_binary(id), do: id
end
