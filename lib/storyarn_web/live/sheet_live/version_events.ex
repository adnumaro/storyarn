defmodule StoryarnWeb.SheetLive.VersionEvents do
  @moduledoc """
  Sheet-owned event handlers for the Sheet version panel.

  Persistence and restore policy always go through `Storyarn.Sheets`; the
  callback map contains only Sheet-page reload and broadcast behavior.
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, push_navigate: 2, put_flash: 3]

  alias Phoenix.LiveView.Socket
  alias Storyarn.Sheets
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.SheetLive.VersionHistory

  def handle_compare(%{"version_number" => version_number}, socket, config) do
    case VersionHistory.parse_version_number(version_number) do
      {:ok, number} ->
        Sheets.record_version_compared(socket.assigns.current_scope, entity(socket))
        {:noreply, push_navigate(socket, to: config.compare_path.(socket, number))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_create(%{"title" => title, "description" => description}, socket, config) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      create_named_version(socket, config, blank_to_nil(title), blank_to_nil(description))
    end)
  end

  def handle_promote(params, socket, config) do
    %{"version_number" => version_number, "title" => title, "description" => description} = params

    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_version(socket, config, version_number, fn version ->
        promote_version(socket, config, version, blank_to_nil(title), blank_to_nil(description))
      end)
    end)
  end

  def handle_delete(%{"version_number" => version_number}, socket, config) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_version(socket, config, version_number, fn version -> delete_version(socket, config, version) end)
    end)
  end

  def handle_load_more(_params, socket, _config) do
    history = socket.assigns.history_data

    if history && history.has_more do
      next_page = history.page + 1
      {:noreply, VersionHistory.load_more_history(socket, next_page)}
    else
      {:noreply, socket}
    end
  end

  def handle_preview_restore(%{"version_number" => version_number} = params, socket, config) do
    case VersionHistory.restore_request_id(params) do
      {:ok, request_id} ->
        with_authorized_restore(socket, fn authorized_socket ->
          preview_restore(authorized_socket, config, version_number, request_id)
        end)

      :error ->
        {:noreply, socket}
    end
  end

  def handle_review_restore(%{"version_number" => version_number} = params, socket, config) do
    case VersionHistory.restore_request_id(params) do
      {:ok, request_id} ->
        with_authorized_restore(socket, fn authorized_socket ->
          review_restore(authorized_socket, config, version_number, request_id)
        end)

      :error ->
        {:noreply, socket}
    end
  end

  def handle_confirm_restore(%{"version_number" => version_number} = params, socket, config) do
    case VersionHistory.restore_request_id(params) do
      {:ok, request_id} ->
        with_authorized_restore(socket, fn authorized_socket ->
          confirm_restore(authorized_socket, config, version_number, request_id)
        end)

      :error ->
        {:noreply, socket}
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  @doc """
  Runs an entity-version restore callback only when restore is enabled and the
  current project member can edit content.
  """
  @spec with_authorized_restore(Socket.t(), (Socket.t() -> {:noreply, Socket.t()})) ::
          {:noreply, Socket.t()}
  def with_authorized_restore(socket, fun) do
    case Sheets.ensure_version_restore_enabled() do
      :ok ->
        Authorize.with_authorization(socket, :edit_content, fun)

      {:error, :restore_temporarily_disabled} ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not restore version."))}
    end
  end

  defp create_named_version(socket, _config, nil, _description) do
    {:noreply, put_flash(socket, :error, dgettext("versioning", "Title is required."))}
  end

  defp create_named_version(socket, config, title, description) do
    current_scope = socket.assigns.current_scope

    case Sheets.create_named_version(
           current_scope,
           entity(socket),
           title: title,
           description: description
         ) do
      {:ok, _version} ->
        {:noreply,
         socket
         |> config.reload_history.()
         |> put_flash(:info, dgettext("versioning", "Version created."))}

      {:error, :title_required} ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Title is required."))}

      {:error, :limit_reached, _metadata} ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not create version."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not create version."))}
    end
  end

  defp with_version(socket, config, version_number, fun, opts \\ []) do
    case get_version(socket, config, version_number) do
      {:ok, version} -> fun.(version)
      :error -> missing_version(socket, Keyword.get(opts, :missing, :flash))
    end
  end

  defp get_version(socket, _config, version_number) do
    with {:ok, number} <- VersionHistory.parse_version_number(version_number),
         version when not is_nil(version) <-
           Sheets.get_version(entity(socket).id, number) do
      {:ok, version}
    else
      _ -> :error
    end
  end

  defp missing_version(socket, :flash) do
    {:noreply, put_flash(socket, :error, dgettext("versioning", "Version not found."))}
  end

  defp promote_version(socket, config, version, title, description) do
    case Sheets.update_version(version, %{
           title: title,
           description: description
         }) do
      {:ok, _} ->
        {:noreply,
         socket
         |> config.reload_history.()
         |> put_flash(:info, dgettext("versioning", "Version named successfully."))}

      {:error, :limit_reached, _metadata} ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not name version."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not name version."))}
    end
  end

  defp delete_version(socket, config, version) do
    case Sheets.delete_version(version) do
      {:ok, _} ->
        {:noreply,
         socket
         |> config.reload_history.()
         |> put_flash(:info, dgettext("versioning", "Version deleted."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not delete version."))}
    end
  end

  defp show_restore_preview(socket, _config, version, request_id) do
    # Capture and verify the safety version at final confirmation. Creating it
    # while this modal opens would leave a race window for collaborator edits.
    case Sheets.prepare_version_restore_conflicts(entity(socket), version) do
      {:ok, report} -> VersionHistory.show_conflict_preview(socket, version, report, request_id)
      {:error, :target_snapshot_unreadable} -> VersionHistory.snapshot_load_error(socket)
    end
  end

  defp preview_restore(socket, config, version_number, request_id) do
    with_version(socket, config, version_number, fn version ->
      VersionHistory.detect_and_show_restore_preview(
        socket,
        entity(socket),
        version,
        request_id
      )
    end)
  end

  defp review_restore(socket, config, version_number, request_id) do
    with_version(socket, config, version_number, fn version ->
      show_restore_preview(socket, config, version, request_id)
    end)
  end

  defp confirm_restore(socket, config, version_number, request_id) do
    with_version(socket, config, version_number, fn version ->
      restore_version(socket, config, version, request_id)
    end)
  end

  defp restore_version(socket, config, version, request_id) do
    case Sheets.restore_tracked_version(
           socket.assigns.current_scope,
           entity(socket),
           version,
           user_id: socket.assigns.current_scope.user.id
         ) do
      {:ok, _updated_entity} ->
        on_version_restored(socket, config, version, request_id)

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

      {:error, :sheet_changed_since_pre_restore_snapshot} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext(
             "versioning",
             "The sheet changed while restore was being prepared. Review the latest changes and try again."
           )
         )}

      {:error, reason}
      when reason in [
             :pre_restore_version_not_durable,
             :pre_restore_version_identity_mismatch,
             :invalid_pre_restore_version_identity
           ] ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext(
             "versioning",
             "The safety backup is no longer available. Restore was aborted. Please try again."
           )
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not restore version."))}
    end
  end

  defp on_version_restored(socket, config, version, request_id) do
    updated_sheet = Sheets.get_sheet_full!(socket.assigns.project.id, socket.assigns.sheet.id)

    payload =
      VersionHistory.put_restore_request_id(
        %{name: updated_sheet.name, shortcut: updated_sheet.shortcut},
        request_id
      )

    {:noreply,
     socket
     |> assign(:sheet, updated_sheet)
     |> config.reload_blocks.()
     |> config.clear_undo.()
     |> config.reload_history.()
     |> push_event("version_restored", payload)
     |> config.broadcast.(:sheet_restored)
     |> put_flash(
       :info,
       dgettext("versioning", "Restored to version %{number}", number: version.version_number)
     )}
  end

  defp entity(socket), do: Map.fetch!(socket.assigns, :sheet)
end
