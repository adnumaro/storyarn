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
      tree_props={%{
        sheetsTree: @sheets_tree,
        canEdit: @can_edit,
        workspaceSlug: @workspace.slug,
        projectSlug: @project.slug,
        selectedSheetId: @sheet && @sheet.id
      }}
    >
      <div :if={@sheet} class="max-w-4xl mx-auto">
        <.vue
          v-component="sheets/SheetHeader"
          v-socket={@socket}
          id="sheet-header"
          sheet={prepare_sheet_for_vue(@sheet)}
          can-edit={@can_edit}
          is-draft={@is_draft}
          source-shortcut={@source_shortcut}
        />
        <div class="px-4 py-8 text-muted-foreground text-sm">
          Block editor coming in Phase 2...
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
        assign(socket, :sheet, sheet)
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
        {:ok, _} -> {:noreply, reload_sheet_and_tree(socket)}
        {:error, _} -> {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not remove avatar."))}
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

  # Tree events (create, delete, move)
  def handle_event("create_sheet", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case Sheets.create_sheet(socket.assigns.project, %{name: dgettext("sheets", "Untitled")}) do
        {:ok, new_sheet} ->
          {:noreply,
           push_navigate(socket,
             to: ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/v2/sheets/#{new_sheet.id}"
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
             to: ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/v2/sheets/#{new_sheet.id}"
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
           |> assign(:sheets_tree, prepare_tree(Sheets.list_sheets_tree(socket.assigns.project.id)))}
        else
          _ -> {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not delete sheet."))}
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
         put_flash(socket, :error, dgettext("sheets", "Storage limit reached. Upgrade your plan."))}
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
end
