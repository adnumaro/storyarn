defmodule StoryarnWeb.Helpers.VersionEventHelpers do
  @moduledoc """
  Shared event handlers for entity version panels.
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.LiveView, only: [push_event: 3, push_navigate: 2, put_flash: 3]

  alias Storyarn.Analytics
  alias Storyarn.Versioning
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Helpers.VersionHistoryHelpers

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

  def handle_load_more(socket, config) do
    history = socket.assigns.history_data

    if history do
      next_page = (history[:page] || 1) + 1

      {:noreply,
       VersionHistoryHelpers.load_more_history(socket, config.entity_type, entity(socket, config).id, next_page)}
    else
      {:noreply, socket}
    end
  end

  def handle_preview_restore(%{"version_number" => version_number}, socket, config) do
    with_version(socket, config, version_number, fn version ->
      VersionHistoryHelpers.detect_and_show_restore_preview(
        socket,
        config.entity_type,
        entity(socket, config),
        version
      )
    end)
  end

  def handle_save_and_restore(%{"version_number" => version_number}, socket, config) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_version(
        socket,
        config,
        version_number,
        fn version ->
          save_and_show_restore(socket, config, version)
        end,
        missing: :noop
      )
    end)
  end

  def handle_discard_and_restore(%{"version_number" => version_number}, socket, config) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_version(
        socket,
        config,
        version_number,
        fn version ->
          VersionHistoryHelpers.show_conflict_preview(socket, config.entity_type, entity(socket, config), version, true)
        end,
        missing: :noop
      )
    end)
  end

  def handle_confirm_restore(%{"version_number" => version_number} = params, socket, config) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_version(
        socket,
        config,
        version_number,
        fn version ->
          restore_version(socket, config, version, params)
        end,
        missing: :noop
      )
    end)
  end

  def handle_compare(%{"version_number" => version_number}, socket, config) do
    case VersionHistoryHelpers.parse_version_number(version_number) do
      {:ok, number} ->
        track_version_event(socket, config, "version compared")
        {:noreply, push_navigate(socket, to: config.compare_path.(socket, number))}

      _ ->
        {:noreply, socket}
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp create_named_version(socket, _config, nil, _description) do
    {:noreply, put_flash(socket, :error, dgettext("versioning", "Title is required."))}
  end

  defp create_named_version(socket, config, title, description) do
    %{project: project, current_scope: current_scope} = socket.assigns

    case Versioning.create_version(config.entity_type, entity(socket, config), project.id, current_scope.user.id,
           title: title,
           description: description
         ) do
      {:ok, _version} ->
        track_version_event(socket, config, "version created")

        {:noreply,
         socket
         |> config.reload_history.()
         |> put_flash(:info, dgettext("versioning", "Version created."))}

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

  defp get_version(socket, config, version_number) do
    with {:ok, number} <- VersionHistoryHelpers.parse_version_number(version_number),
         version when not is_nil(version) <-
           Versioning.get_version(config.entity_type, entity(socket, config).id, number) do
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
    case Versioning.update_version(version, %{title: title, description: description}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> config.reload_history.()
         |> put_flash(:info, dgettext("versioning", "Version named successfully."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not name version."))}
    end
  end

  defp delete_version(socket, config, version) do
    case Versioning.delete_version(version) do
      {:ok, _} ->
        {:noreply,
         socket
         |> config.reload_history.()
         |> put_flash(:info, dgettext("versioning", "Version deleted."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not delete version."))}
    end
  end

  defp save_and_show_restore(socket, config, version) do
    %{project: project, current_scope: current_scope} = socket.assigns

    Versioning.create_version(config.entity_type, entity(socket, config), project.id, current_scope.user.id,
      title: dgettext("versioning", "Before restore to v%{n}", n: version.version_number)
    )

    VersionHistoryHelpers.show_conflict_preview(socket, config.entity_type, entity(socket, config), version, true)
  end

  defp restore_version(socket, config, version, params) do
    skip = params["skip_pre_snapshot"] in [true, "true"]

    case Versioning.restore_version(config.entity_type, entity(socket, config), version, skip_pre_snapshot: skip) do
      {:ok, _} ->
        track_version_event(socket, config, "version restored", %{skip_pre_snapshot: skip})

        {:noreply,
         socket
         |> push_event("version_restored", %{})
         |> put_flash(:info, dgettext("versioning", "Version restored."))
         |> push_navigate(to: config.restore_path.(socket))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not restore version."))}
    end
  end

  defp entity(socket, config), do: Map.fetch!(socket.assigns, config.entity_key)

  defp track_version_event(socket, config, event_name, extra \\ %{}) do
    Analytics.track(
      socket.assigns.current_scope,
      event_name,
      Map.merge(
        %{
          entity_type: config.entity_type,
          project_id: socket.assigns.project.id
        },
        extra
      )
    )
  end
end
