defmodule StoryarnWeb.Components.AudioPicker do
  @moduledoc """
  LiveComponent for selecting, uploading, and previewing audio assets.

  Loads audio assets for a project and provides:
  - Dropdown to select from existing audio assets
  - Upload button for new audio files (base64 via JS hook)
  - Audio preview player when asset is selected
  - Remove button to unlink audio (does not delete the asset)

  ## Usage

      <.live_component
        module={StoryarnWeb.Components.AudioPicker}
        id="audio-picker"
        project={@project}
        current_user={@current_user}
        selected_asset_id={@node.data["audio_asset_id"]}
        can_edit={@can_edit}
      />

  ## Events

  Sends to parent LiveView via `send/2`:
  - `{:audio_picker, :selected, asset_id}` — when audio is selected or uploaded
  - `{:audio_picker, :selected, nil}` — when audio is removed/unlinked
  - `{:audio_picker, :error, message}` — when upload fails
  """

  use StoryarnWeb, :live_component

  alias Storyarn.Assets
  alias Storyarn.Assets.Storage

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <form :if={@can_edit} phx-change="select_audio" phx-target={@myself}>
        <select name="audio_asset_id" class="select select-sm select-bordered w-full">
          <option value="">{gettext("No audio")}</option>
          <option
            :for={asset <- @audio_assets}
            value={asset.id}
            selected={to_string(asset.id) == to_string(@selected_asset_id)}
          >
            {asset.filename}
          </option>
        </select>
      </form>

      <div :if={@can_edit} class="mt-2">
        <label class={[
          "btn btn-ghost btn-xs gap-1",
          @uploading && "btn-disabled"
        ]}>
          <span :if={@uploading} class="loading loading-spinner loading-xs"></span>
          <.icon :if={!@uploading} name="upload" class="size-3" />
          {if @uploading, do: gettext("Uploading..."), else: gettext("Upload audio")}
          <input
            type="file"
            accept="audio/*"
            class="hidden"
            phx-hook="AudioUpload"
            phx-target={@myself}
            id={"#{@id}-audio-input"}
            data-target={@myself}
            disabled={@uploading}
          />
        </label>
      </div>

      <div
        :if={@selected_asset}
        class="mt-3 p-3 bg-base-100 rounded-lg border border-base-300"
      >
        <p
          class="text-xs text-base-content/60 mb-2 truncate"
          title={@selected_asset.filename}
        >
          {gettext("Preview:")} {@selected_asset.filename}
        </p>
        <audio controls class="w-full h-8">
          <source src={@selected_asset.url} type={@selected_asset.content_type} />
          {gettext("Your browser does not support audio playback.")}
        </audio>
        <button
          :if={@can_edit}
          type="button"
          phx-click="remove_audio"
          phx-target={@myself}
          class="btn btn-ghost btn-xs text-error mt-2"
        >
          <.icon name="x" class="size-3" />
          {gettext("Remove")}
        </button>
      </div>

      <p :if={!@selected_asset && @can_edit && !@uploading} class="text-xs text-base-content/60 mt-2">
        {gettext("Attach voice-over or ambient audio.")}
      </p>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok, assign(socket, audio_assets: [], selected_asset: nil, uploading: false)}
  end

  @impl true
  def update(assigns, socket) do
    old_project_id =
      case socket.assigns do
        %{project: %{id: id}} -> id
        _ -> nil
      end

    socket = assign(socket, assigns)
    new_project_id = socket.assigns.project.id

    audio_assets =
      if old_project_id != new_project_id do
        Assets.list_assets(new_project_id, content_type: "audio/")
      else
        socket.assigns.audio_assets
      end

    selected_asset =
      find_selected_asset(audio_assets, socket.assigns[:selected_asset_id])

    {:ok, assign(socket, audio_assets: audio_assets, selected_asset: selected_asset)}
  end

  # ===========================================================================
  # Event Handlers
  # ===========================================================================

  @impl true
  def handle_event("select_audio", %{"audio_asset_id" => ""}, socket) do
    send(self(), {:audio_picker, :selected, nil})
    {:noreply, assign(socket, selected_asset: nil, selected_asset_id: nil)}
  end

  def handle_event("select_audio", %{"audio_asset_id" => id_str}, socket) do
    asset_id = String.to_integer(id_str)
    selected = find_selected_asset(socket.assigns.audio_assets, asset_id)
    send(self(), {:audio_picker, :selected, asset_id})
    {:noreply, assign(socket, selected_asset: selected, selected_asset_id: asset_id)}
  end

  def handle_event("remove_audio", _params, socket) do
    send(self(), {:audio_picker, :selected, nil})
    {:noreply, assign(socket, selected_asset: nil, selected_asset_id: nil)}
  end

  def handle_event("upload_started", _params, socket) do
    {:noreply, assign(socket, :uploading, true)}
  end

  def handle_event("upload_validation_error", %{"message" => message}, socket) do
    send(self(), {:audio_picker, :error, message})
    {:noreply, assign(socket, :uploading, false)}
  end

  def handle_event(
        "upload_audio",
        %{"filename" => filename, "content_type" => content_type, "data" => data},
        socket
      ) do
    [_header, base64_data] = String.split(data, ",", parts: 2)

    case Base.decode64(base64_data) do
      {:ok, binary_data} ->
        process_upload(socket, filename, content_type, binary_data)

      :error ->
        send(self(), {:audio_picker, :error, gettext("Invalid file data.")})
        {:noreply, assign(socket, :uploading, false)}
    end
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp process_upload(socket, filename, content_type, binary_data) do
    alias Storyarn.Assets.Asset

    if Asset.allowed_content_type?(content_type) do
      project = socket.assigns.project
      user = socket.assigns.current_user
      safe_filename = Assets.sanitize_filename(filename)
      key = Assets.generate_key(project, safe_filename)

      asset_attrs = %{
        filename: safe_filename,
        content_type: content_type,
        size: byte_size(binary_data),
        key: key
      }

      with {:ok, url} <- Storage.upload(key, binary_data, content_type),
           {:ok, asset} <- Assets.create_asset(project, user, Map.put(asset_attrs, :url, url)) do
        audio_assets = [asset | socket.assigns.audio_assets]

        send(self(), {:audio_picker, :selected, asset.id})

        {:noreply,
         assign(socket,
           audio_assets: audio_assets,
           selected_asset: asset,
           selected_asset_id: asset.id,
           uploading: false
         )}
      else
        {:error, _reason} ->
          send(self(), {:audio_picker, :error, gettext("Could not upload audio file.")})
          {:noreply, assign(socket, :uploading, false)}
      end
    else
      send(self(), {:audio_picker, :error, gettext("Unsupported file type.")})
      {:noreply, assign(socket, :uploading, false)}
    end
  end

  defp find_selected_asset(_assets, nil), do: nil

  defp find_selected_asset(assets, id) do
    Enum.find(assets, &(to_string(&1.id) == to_string(id)))
  end

end
