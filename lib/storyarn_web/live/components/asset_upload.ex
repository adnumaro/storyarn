defmodule StoryarnWeb.Components.AssetUpload do
  @moduledoc """
  LiveComponent for uploading assets.

  Provides a drag-and-drop interface with progress indication and preview.
  Uses LiveView's built-in file upload support.

  ## Usage

      <.live_component
        module={StoryarnWeb.Components.AssetUpload}
        id="asset-upload"
        project={@project}
        current_user={@current_user}
        on_upload={fn asset -> send(self(), {:asset_uploaded, asset}) end}
      />

  ## Options

    * `project` - Required. The project to upload to.
    * `current_user` - Required. The user uploading the file.
    * `on_upload` - Required. Callback function called with the created asset.
    * `accept` - Optional. List of accepted MIME types. Defaults to images.
    * `max_entries` - Optional. Maximum number of files. Defaults to 1.
    * `max_file_size` - Optional. Max file size in bytes. Defaults to 10MB.
  """
  use StoryarnWeb, :live_component

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.ImageProcessor
  alias Storyarn.Assets.Storage

  @default_accept ~w(image/jpeg image/png image/gif image/webp)
  @default_max_size 10 * 1024 * 1024

  @impl true
  def render(assigns) do
    ~H"""
    <div class="asset-upload">
      <form
        id={"#{@id}-form"}
        phx-submit="save"
        phx-change="validate"
        phx-target={@myself}
      >
        <div
          class={[
            "border-2 border-dashed rounded-lg p-6 text-center transition-colors",
            "hover:border-primary hover:bg-primary/5",
            @uploads.asset.entries != [] && "border-primary bg-primary/5"
          ]}
          phx-drop-target={@uploads.asset.ref}
        >
          <.live_file_input upload={@uploads.asset} class="hidden" />

          <div :if={@uploads.asset.entries == []}>
            <.icon name="hero-cloud-arrow-up" class="size-12 mx-auto text-base-content/30 mb-2" />
            <p class="text-base-content/70 mb-2">
              {gettext("Drag and drop files here, or")}
            </p>
            <label for={@uploads.asset.ref} class="btn btn-primary btn-sm cursor-pointer">
              {gettext("Browse Files")}
            </label>
            <p class="text-xs text-base-content/50 mt-2">
              {gettext("Max file size: %{size}MB", size: div(@max_file_size, 1024 * 1024))}
            </p>
          </div>

          <div :if={@uploads.asset.entries != []} class="space-y-3">
            <.upload_entry
              :for={entry <- @uploads.asset.entries}
              entry={entry}
              uploads={@uploads}
              myself={@myself}
            />
          </div>
        </div>

        <div :if={@uploads.asset.entries != []} class="mt-4 flex justify-end gap-2">
          <button
            type="button"
            class="btn btn-ghost btn-sm"
            phx-click="cancel_all"
            phx-target={@myself}
          >
            {gettext("Cancel")}
          </button>
          <button
            type="submit"
            class="btn btn-primary btn-sm"
            disabled={not upload_valid?(@uploads.asset)}
          >
            {gettext("Upload")}
          </button>
        </div>
      </form>

      <div :if={@uploaded_assets != []} class="mt-4">
        <h4 class="text-sm font-medium mb-2">{gettext("Uploaded")}</h4>
        <div class="grid grid-cols-4 gap-2">
          <div
            :for={asset <- @uploaded_assets}
            class="relative aspect-square bg-base-200 rounded overflow-hidden"
          >
            <img
              :if={Asset.image?(asset)}
              src={asset.url}
              alt={asset.filename}
              class="w-full h-full object-cover"
            />
            <div :if={not Asset.image?(asset)} class="flex items-center justify-center h-full">
              <.icon name="hero-document" class="size-8 text-base-content/50" />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :uploads, :map, required: true
  attr :myself, :any, required: true

  defp upload_entry(assigns) do
    ~H"""
    <div class="flex items-center gap-3 p-2 bg-base-200 rounded">
      <div class="relative w-16 h-16 flex-shrink-0 bg-base-300 rounded overflow-hidden">
        <.live_img_preview :if={image?(@entry)} entry={@entry} class="w-full h-full object-cover" />
        <div :if={not image?(@entry)} class="flex items-center justify-center h-full">
          <.icon name="hero-document" class="size-6 text-base-content/50" />
        </div>
      </div>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-medium truncate">{@entry.client_name}</p>
        <p class="text-xs text-base-content/50">
          {format_size(@entry.client_size)}
        </p>
        <div class="mt-1">
          <progress class="progress progress-primary w-full h-1" value={@entry.progress} max="100" />
        </div>
        <p
          :for={err <- Phoenix.Component.upload_errors(@uploads, @entry)}
          class="text-xs text-error mt-1"
        >
          {error_to_string(err)}
        </p>
      </div>
      <button
        type="button"
        class="btn btn-ghost btn-xs"
        phx-click="cancel_upload"
        phx-value-ref={@entry.ref}
        phx-target={@myself}
      >
        <.icon name="hero-x-mark" class="size-4" />
      </button>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok, assign(socket, uploaded_assets: [])}
  end

  @impl true
  def update(assigns, socket) do
    accept = Map.get(assigns, :accept, @default_accept)
    max_entries = Map.get(assigns, :max_entries, 1)
    max_file_size = Map.get(assigns, :max_file_size, @default_max_size)

    socket =
      socket
      |> assign(assigns)
      |> assign(:max_file_size, max_file_size)
      |> allow_upload(:asset,
        accept: accept,
        max_entries: max_entries,
        max_file_size: max_file_size,
        auto_upload: false
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :asset, ref)}
  end

  def handle_event("cancel_all", _params, socket) do
    socket =
      Enum.reduce(socket.assigns.uploads.asset.entries, socket, fn entry, acc ->
        cancel_upload(acc, :asset, entry.ref)
      end)

    {:noreply, socket}
  end

  def handle_event("save", _params, socket) do
    project = socket.assigns.project
    user = socket.assigns.current_user
    on_upload = socket.assigns.on_upload

    uploaded_assets =
      consume_uploaded_entries(socket, :asset, fn %{path: path}, entry ->
        process_upload(path, entry, project, user, on_upload)
      end)

    uploaded_assets = Enum.filter(uploaded_assets, & &1)

    socket =
      socket
      |> update(:uploaded_assets, &(&1 ++ uploaded_assets))

    if uploaded_assets != [] do
      {:noreply, put_flash(socket, :info, gettext("Files uploaded successfully."))}
    else
      {:noreply, put_flash(socket, :error, gettext("Failed to upload files."))}
    end
  end

  defp process_upload(path, entry, project, user, on_upload) do
    key = Assets.generate_key(project, entry.client_name)
    content = File.read!(path)

    with {:ok, url} <- Storage.upload(key, content, entry.client_type),
         {:ok, asset} <- create_asset_record(path, entry, project, user, key, url) do
      if on_upload, do: on_upload.(asset)
      {:ok, asset}
    else
      {:error, _reason} ->
        {:postpone, nil}
    end
  end

  defp create_asset_record(path, entry, project, user, key, url) do
    metadata = process_image_metadata(path, entry.client_type)

    attrs = %{
      filename: entry.client_name,
      content_type: entry.client_type,
      size: entry.client_size,
      key: key,
      url: url,
      metadata: metadata
    }

    case Assets.create_asset(project, user, attrs) do
      {:ok, asset} ->
        {:ok, asset}

      {:error, changeset} ->
        Storage.delete(key)
        {:error, changeset}
    end
  end

  defp process_image_metadata(path, content_type) do
    if String.starts_with?(content_type, "image/") and ImageProcessor.imagemagick_available?() do
      case ImageProcessor.get_dimensions(path) do
        {:ok, %{width: w, height: h}} ->
          %{"width" => w, "height" => h}

        {:error, _} ->
          %{}
      end
    else
      %{}
    end
  end

  defp image?(entry) do
    String.starts_with?(entry.client_type, "image/")
  end

  defp upload_valid?(upload) do
    upload.entries != [] and Enum.all?(upload.entries, & &1.valid?)
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  defp error_to_string(:too_large), do: gettext("File is too large")
  defp error_to_string(:too_many_files), do: gettext("Too many files")
  defp error_to_string(:not_accepted), do: gettext("File type not accepted")
  defp error_to_string(err), do: inspect(err)
end
