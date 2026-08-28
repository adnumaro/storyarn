defmodule StoryarnWeb.SceneLive.VersionEvents do
  @moduledoc """
  Scene-owned event handlers for the Scene version panel.

  Persistence and restore policy always go through `Storyarn.Scenes`; the
  callback map contains only Scene-page navigation and reload behavior.
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.LiveView, only: [push_event: 3, push_navigate: 2, put_flash: 3]

  alias Phoenix.LiveView.Socket
  alias Storyarn.Scenes
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.SceneLive.VersionHistory

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
      with_version(socket, config, version_number, fn version ->
        delete_version(socket, config, version)
      end)
    end)
  end

  def handle_load_more(socket, _config) do
    history = socket.assigns.history_data

    if history do
      next_page = (history[:page] || 1) + 1

      {:noreply,
       VersionHistory.load_more_history(
         socket,
         entity(socket).id,
         next_page
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_preview_restore(%{"version_number" => version_number} = params, socket, config) do
    case VersionHistory.restore_request_id(params) do
      {:ok, request_id} ->
        with_authorized_restore(
          socket,
          fn authorized_socket ->
            preview_restore(authorized_socket, config, version_number, request_id)
          end
        )

      :error ->
        {:noreply, socket}
    end
  end

  def handle_review_restore(%{"version_number" => version_number} = params, socket, config) do
    case VersionHistory.restore_request_id(params) do
      {:ok, request_id} ->
        with_authorized_restore(
          socket,
          fn authorized_socket ->
            review_restore(authorized_socket, config, version_number, request_id)
          end
        )

      :error ->
        {:noreply, socket}
    end
  end

  def handle_confirm_restore(%{"version_number" => version_number} = params, socket, config) do
    case VersionHistory.restore_request_id(params) do
      {:ok, request_id} ->
        with_authorized_restore(
          socket,
          fn authorized_socket ->
            confirm_restore(authorized_socket, config, version_number, request_id)
          end
        )

      :error ->
        {:noreply, socket}
    end
  end

  def handle_compare(%{"version_number" => version_number}, socket, config) do
    case VersionHistory.parse_version_number(version_number) do
      {:ok, number} ->
        Scenes.record_version_compared(socket.assigns.current_scope, entity(socket))
        {:noreply, push_navigate(socket, to: config.compare_path.(socket, number))}

      _ ->
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
    case Scenes.ensure_version_restore_enabled() do
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

    case Scenes.create_named_version(
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
           Scenes.get_version(entity(socket).id, number) do
      {:ok, version}
    else
      _ -> :error
    end
  end

  defp missing_version(socket, :flash) do
    {:noreply, put_flash(socket, :error, dgettext("versioning", "Version not found."))}
  end

  defp missing_version(socket, :noop), do: {:noreply, socket}

  defp promote_version(socket, config, version, title, description) do
    case Scenes.update_version(version, %{
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
    case Scenes.delete_version(version) do
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
    case Scenes.prepare_version_restore_conflicts(entity(socket), version) do
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
    with_version(
      socket,
      config,
      version_number,
      fn version -> show_restore_preview(socket, config, version, request_id) end,
      missing: :noop
    )
  end

  defp confirm_restore(socket, config, version_number, request_id) do
    with_version(
      socket,
      config,
      version_number,
      fn version -> restore_version(socket, config, version, request_id) end,
      missing: :noop
    )
  end

  defp restore_version(socket, config, version, request_id) do
    case Scenes.restore_tracked_version(
           socket.assigns.current_scope,
           entity(socket),
           version,
           user_id: socket.assigns.current_scope.user.id
         ) do
      {:ok, _} ->
        payload = VersionHistory.put_restore_request_id(%{}, request_id)

        {:noreply,
         socket
         |> push_event("version_restored", payload)
         |> put_flash(:info, dgettext("versioning", "Version restored."))
         |> push_navigate(to: config.restore_path.(socket))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not restore version."))}
    end
  end

  defp entity(socket), do: Map.fetch!(socket.assigns, :scene)
end
