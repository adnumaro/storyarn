defmodule StoryarnWeb.SheetLive.Handlers.HistoryHandlers do
  @moduledoc """
  Handles version history events for the sheet editor.
  """

  use Gettext, backend: Storyarn.Gettext
  use StoryarnWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, push_navigate: 2, put_flash: 3]
  import StoryarnWeb.SheetLive.Helpers.HistoryDataHelpers

  alias Storyarn.Analytics
  alias Storyarn.Sheets
  alias Storyarn.Versioning
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Helpers.VersionEventHelpers

  def handle_compare(%{"version_number" => version_number}, socket, _helpers) do
    case parse_version_number(version_number) do
      {:ok, number} ->
        %{workspace: workspace, project: project, sheet: sheet} = socket.assigns
        track_version_event(socket, "version compared")

        compare_url =
          ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}/compare/#{number}"

        {:noreply, push_navigate(socket, to: compare_url)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_create(%{"title" => title, "description" => description}, socket, _helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      create_named_version(socket, blank_to_nil(title), blank_to_nil(description))
    end)
  end

  def handle_promote(params, socket, _helpers) do
    %{"version_number" => version_number, "title" => title, "description" => description} = params

    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_version(socket, version_number, fn version ->
        promote_version(socket, version, blank_to_nil(title), blank_to_nil(description))
      end)
    end)
  end

  def handle_delete(%{"version_number" => version_number}, socket, _helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_version(socket, version_number, fn version -> delete_version(socket, version) end)
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
    VersionEventHelpers.with_authorized_restore(socket, "sheet", fn authorized_socket ->
      with_version(authorized_socket, version_number, fn version ->
        detect_and_show_restore_preview(authorized_socket, version)
      end)
    end)
  end

  def handle_save_and_restore(%{"version_number" => version_number}, socket, _helpers) do
    VersionEventHelpers.with_authorized_restore(socket, "sheet", fn authorized_socket ->
      with_version(authorized_socket, version_number, fn version ->
        save_and_show_restore(authorized_socket, version)
      end)
    end)
  end

  def handle_discard_and_restore(%{"version_number" => version_number}, socket, _helpers) do
    VersionEventHelpers.with_authorized_restore(socket, "sheet", fn authorized_socket ->
      with_version(authorized_socket, version_number, fn version ->
        show_conflict_preview(authorized_socket, version, false)
      end)
    end)
  end

  def handle_confirm_restore(%{"version_number" => version_number} = params, socket, helpers) do
    VersionEventHelpers.with_authorized_restore(socket, "sheet", fn authorized_socket ->
      with_version(authorized_socket, version_number, fn version ->
        restore_version(authorized_socket, version, params, helpers)
      end)
    end)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp create_named_version(socket, nil, _description) do
    {:noreply, put_flash(socket, :error, dgettext("versioning", "Title is required."))}
  end

  defp create_named_version(socket, title, description) do
    %{sheet: sheet, project: project, current_scope: current_scope} = socket.assigns

    case Versioning.create_version("sheet", sheet, project.id, current_scope.user.id,
           title: title,
           description: description
         ) do
      {:ok, _version} ->
        track_version_event(socket, "version created")

        {:noreply,
         socket
         |> load_history_data()
         |> put_flash(:info, dgettext("versioning", "Version created."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not create version."))}
    end
  end

  defp with_version(socket, version_number, fun) do
    case get_version(socket, version_number) do
      {:ok, version} ->
        fun.(version)

      :error ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Version not found."))}
    end
  end

  defp get_version(socket, version_number) do
    with {:ok, number} <- parse_version_number(version_number),
         version when not is_nil(version) <-
           Versioning.get_version("sheet", socket.assigns.sheet.id, number) do
      {:ok, version}
    else
      _ -> :error
    end
  end

  defp promote_version(socket, version, title, description) do
    case Versioning.update_version(version, %{title: title, description: description}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_history_data()
         |> put_flash(:info, dgettext("versioning", "Version named successfully."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not name version."))}
    end
  end

  defp delete_version(socket, version) do
    case Versioning.delete_version(version) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_history_data()
         |> put_flash(:info, dgettext("versioning", "Version deleted."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not delete version."))}
    end
  end

  defp save_and_show_restore(socket, version) do
    # Capture and verify the safety version at final confirmation. Creating it
    # while this modal opens would leave a race window for collaborator edits.
    show_conflict_preview(socket, version, false)
  end

  defp restore_version(socket, version, _params, helpers) do
    sheet = socket.assigns.sheet

    case Versioning.restore_version("sheet", sheet, version, user_id: socket.assigns.current_scope.user.id) do
      {:ok, _updated_entity} ->
        track_version_event(socket, "version restored", %{skip_pre_snapshot: false})

        on_version_restored(socket, version, helpers)

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
  end

  defp on_version_restored(socket, version, helpers) do
    updated_sheet = Sheets.get_sheet_full!(socket.assigns.project.id, socket.assigns.sheet.id)

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
  end

  defp track_version_event(socket, event_name, extra \\ %{}) do
    Analytics.track(
      socket.assigns.current_scope,
      event_name,
      Map.merge(
        %{
          entity_type: "sheet",
          project_id: socket.assigns.project.id
        },
        extra
      )
    )
  end
end
