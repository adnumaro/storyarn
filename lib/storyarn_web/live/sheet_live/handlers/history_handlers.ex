defmodule StoryarnWeb.SheetLive.Handlers.HistoryHandlers do
  @moduledoc """
  Handles version history events for the sheet editor.
  """

  use Gettext, backend: Storyarn.Gettext
  use StoryarnWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, push_navigate: 2, put_flash: 3]
  import StoryarnWeb.SheetLive.Helpers.HistoryDataHelpers

  alias Storyarn.Sheets
  alias Storyarn.Versioning
  alias StoryarnWeb.Helpers.Authorize

  def handle_compare(%{"version_number" => version_number}, socket, _helpers) do
    case parse_version_number(version_number) do
      {:ok, number} ->
        %{workspace: workspace, project: project, sheet: sheet} = socket.assigns

        compare_url =
          ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}/compare/#{number}"

        {:noreply, push_navigate(socket, to: compare_url)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_create(%{"title" => title, "description" => description}, socket, _helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      title = if title == "", do: nil, else: title
      description = if description == "", do: nil, else: description

      if title == nil do
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Title is required."))}
      else
        sheet = socket.assigns.sheet
        user_id = socket.assigns.current_scope.user.id
        project_id = socket.assigns.project.id

        case Versioning.create_version("sheet", sheet, project_id, user_id,
               title: title,
               description: description
             ) do
          {:ok, _version} ->
            {:noreply,
             socket
             |> load_history_data()
             |> put_flash(:info, dgettext("versioning", "Version created."))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not create version."))}
        end
      end
    end)
  end

  def handle_promote(params, socket, _helpers) do
    %{"version_number" => version_number, "title" => title, "description" => description} = params

    Authorize.with_authorization(socket, :edit_content, fn socket ->
      title = if title == "", do: nil, else: title
      description = if description == "", do: nil, else: description

      with {:ok, number} <- parse_version_number(version_number),
           version when not is_nil(version) <-
             Versioning.get_version("sheet", socket.assigns.sheet.id, number) do
        case Versioning.update_version(version, %{title: title, description: description}) do
          {:ok, _} ->
            {:noreply,
             socket
             |> load_history_data()
             |> put_flash(:info, dgettext("versioning", "Version named successfully."))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not name version."))}
        end
      else
        _ ->
          {:noreply, put_flash(socket, :error, dgettext("versioning", "Version not found."))}
      end
    end)
  end

  def handle_delete(%{"version_number" => version_number}, socket, _helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with {:ok, number} <- parse_version_number(version_number),
           version when not is_nil(version) <-
             Versioning.get_version("sheet", socket.assigns.sheet.id, number) do
        case Versioning.delete_version(version) do
          {:ok, _} ->
            {:noreply,
             socket
             |> load_history_data()
             |> put_flash(:info, dgettext("versioning", "Version deleted."))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not delete version."))}
        end
      else
        _ ->
          {:noreply, put_flash(socket, :error, dgettext("versioning", "Version not found."))}
      end
    end)
  end

  def handle_load_more(_params, socket, _helpers) do
    history = socket.assigns.history_data

    if history && history.has_more do
      next_page = history.page + 1
      {:noreply, load_more_history(socket, next_page)}
    else
      {:noreply, socket}
    end
  end

  def handle_preview_restore(%{"version_number" => version_number}, socket, _helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with {:ok, number} <- parse_version_number(version_number),
           version when not is_nil(version) <-
             Versioning.get_version("sheet", socket.assigns.sheet.id, number) do
        detect_and_show_restore_preview(socket, version)
      else
        _ ->
          {:noreply, put_flash(socket, :error, dgettext("versioning", "Version not found."))}
      end
    end)
  end

  def handle_save_and_restore(%{"version_number" => version_number}, socket, _helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with {:ok, number} <- parse_version_number(version_number),
           version when not is_nil(version) <-
             Versioning.get_version("sheet", socket.assigns.sheet.id, number) do
        sheet = socket.assigns.sheet
        user_id = socket.assigns.current_scope.user.id
        project_id = socket.assigns.project.id

        case Versioning.create_version("sheet", sheet, project_id, user_id,
               title: dgettext("versioning", "Before restore to v%{number}", number: version.version_number),
               skip_diff: true
             ) do
          {:ok, _} ->
            show_conflict_preview(socket, version, true)

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not save current state."))}
        end
      else
        _ ->
          {:noreply, put_flash(socket, :error, dgettext("versioning", "Version not found."))}
      end
    end)
  end

  def handle_discard_and_restore(%{"version_number" => version_number}, socket, _helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with {:ok, number} <- parse_version_number(version_number),
           version when not is_nil(version) <-
             Versioning.get_version("sheet", socket.assigns.sheet.id, number) do
        show_conflict_preview(socket, version, true)
      else
        _ ->
          {:noreply, put_flash(socket, :error, dgettext("versioning", "Version not found."))}
      end
    end)
  end

  def handle_confirm_restore(%{"version_number" => version_number} = params, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with {:ok, number} <- parse_version_number(version_number),
           version when not is_nil(version) <-
             Versioning.get_version("sheet", socket.assigns.sheet.id, number) do
        skip_pre = params["skip_pre_snapshot"] || false
        user_id = socket.assigns.current_scope.user.id
        sheet = socket.assigns.sheet

        case Versioning.restore_version("sheet", sheet, version,
               user_id: user_id,
               skip_pre_snapshot: skip_pre
             ) do
          {:ok, _updated_entity} ->
            project_id = socket.assigns.project.id
            updated_sheet = Sheets.get_sheet_full!(project_id, sheet.id)

            {:noreply,
             socket
             |> assign(:sheet, updated_sheet)
             |> helpers.reload_blocks.()
             |> helpers.clear_undo.()
             |> load_history_data()
             |> push_event("version_restored", %{
               name: updated_sheet.name,
               shortcut: updated_sheet.shortcut
             })
             |> helpers.broadcast.(:sheet_restored)
             |> put_flash(
               :info,
               dgettext("versioning", "Restored to version %{number}", number: version.version_number)
             )}

          {:error, {:pre_restore_snapshot_failed, _}} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               dgettext(
                 "versioning",
                 "Could not create safety backup before restoring. Restore aborted."
               )
             )}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not restore version."))}
        end
      else
        _ ->
          {:noreply, put_flash(socket, :error, dgettext("versioning", "Version not found."))}
      end
    end)
  end
end
