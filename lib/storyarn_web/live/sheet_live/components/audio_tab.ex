defmodule StoryarnWeb.SheetLive.Components.AudioTab do
  @moduledoc """
  LiveComponent for the Audio tab in the sheet editor.
  Shows all dialogue nodes where this sheet is the speaker, with audio status.
  Supports deep-linking to flow editor nodes and inline audio attachment.
  """

  use StoryarnWeb, :live_component

  alias Storyarn.Assets
  alias Storyarn.Assets.Storage
  alias Storyarn.Flows

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <h2 class="text-lg font-semibold mb-4 flex items-center gap-2">
        <.icon name="volume-2" class="size-5" />
        {dgettext("sheets", "Voice Lines")}
        <%= if @voice_lines != [] do %>
          <span class="badge badge-sm">{length(@voice_lines)}</span>
        <% end %>
      </h2>

      <%= if @voice_lines == [] do %>
        <.empty_voice_lines_state />
      <% else %>
        <div class="space-y-4">
          <.flow_group
            :for={{flow, lines} <- @grouped_lines}
            flow={flow}
            lines={lines}
            workspace={@workspace}
            project={@project}
            can_edit={@can_edit}
            audio_assets={@audio_assets}
            uploading_node_id={@uploading_node_id}
            myself={@myself}
            component_id={@id}
          />
        </div>
      <% end %>
    </section>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    voice_lines = load_voice_lines(socket.assigns.project, socket.assigns.sheet)

    grouped_lines =
      voice_lines
      |> Enum.group_by(& &1.flow)
      |> Enum.sort_by(fn {flow, _} -> flow.name end)

    audio_assets =
      if socket.assigns[:audio_assets] do
        socket.assigns.audio_assets
      else
        Assets.list_assets(socket.assigns.project.id, content_type: "audio/")
      end

    socket =
      socket
      |> assign(voice_lines: voice_lines, grouped_lines: grouped_lines)
      |> assign(audio_assets: audio_assets)
      |> assign_new(:uploading_node_id, fn -> nil end)

    {:ok, socket}
  end

  # ===========================================================================
  # Event Handlers
  # ===========================================================================

  @impl true
  def handle_event("select_audio", %{"node-id" => node_id, "audio_asset_id" => ""}, socket) do
    with_authorization(socket, fn socket ->
      update_node_audio(socket, node_id, nil)
    end)
  end

  def handle_event(
        "select_audio",
        %{"node-id" => node_id, "audio_asset_id" => asset_id_str},
        socket
      ) do
    with_authorization(socket, fn socket ->
      asset_id = String.to_integer(asset_id_str)
      update_node_audio(socket, node_id, asset_id)
    end)
  end

  def handle_event("remove_audio", %{"node-id" => node_id}, socket) do
    with_authorization(socket, fn socket ->
      update_node_audio(socket, node_id, nil)
    end)
  end

  def handle_event("upload_started", %{"node_id" => node_id}, socket) do
    {:noreply, assign(socket, :uploading_node_id, node_id)}
  end

  def handle_event("upload_started", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("upload_validation_error", %{"message" => message}, socket) do
    send(self(), {:audio_tab, :error, message})
    {:noreply, assign(socket, :uploading_node_id, nil)}
  end

  def handle_event(
        "upload_audio",
        %{
          "filename" => filename,
          "content_type" => content_type,
          "data" => data,
          "node_id" => node_id
        },
        socket
      ) do
    with_authorization(socket, fn socket ->
      [_header, base64_data] = String.split(data, ",", parts: 2)

      case Base.decode64(base64_data) do
        {:ok, binary_data} ->
          process_upload(socket, node_id, filename, content_type, binary_data)

        :error ->
          send(self(), {:audio_tab, :error, dgettext("sheets", "Invalid file data.")})
          {:noreply, assign(socket, :uploading_node_id, nil)}
      end
    end)
  end

  # ===========================================================================
  # Private: Authorization
  # ===========================================================================

  defp with_authorization(socket, fun) do
    if socket.assigns.can_edit do
      fun.(socket)
    else
      {:noreply,
       put_flash(socket, :error, dgettext("sheets", "You don't have permission to edit."))}
    end
  end

  # ===========================================================================
  # Private: Node Audio Updates
  # ===========================================================================

  defp update_node_audio(socket, node_id_str, audio_asset_id) do
    node_id = String.to_integer(node_id_str)
    line = Enum.find(socket.assigns.voice_lines, &(&1.node.id == node_id))

    if line do
      node = Flows.get_node!(line.flow.id, node_id)
      updated_data = Map.put(node.data, "audio_asset_id", audio_asset_id)

      case Flows.update_node_data(node, updated_data) do
        {:ok, _updated_node, _meta} ->
          {:noreply, reload_voice_lines(socket)}

        {:error, _changeset} ->
          send(self(), {:audio_tab, :error, dgettext("sheets", "Could not update audio.")})
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  defp process_upload(socket, node_id, filename, content_type, binary_data) do
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
        socket = assign(socket, audio_assets: audio_assets, uploading_node_id: nil)
        update_node_audio(socket, node_id, asset.id)
      else
        {:error, _reason} ->
          send(self(), {:audio_tab, :error, dgettext("sheets", "Could not upload audio file.")})
          {:noreply, assign(socket, :uploading_node_id, nil)}
      end
    else
      send(self(), {:audio_tab, :error, dgettext("sheets", "Unsupported file type.")})
      {:noreply, assign(socket, :uploading_node_id, nil)}
    end
  end

  defp reload_voice_lines(socket) do
    voice_lines = load_voice_lines(socket.assigns.project, socket.assigns.sheet)

    grouped_lines =
      voice_lines
      |> Enum.group_by(& &1.flow)
      |> Enum.sort_by(fn {flow, _} -> flow.name end)

    assign(socket, voice_lines: voice_lines, grouped_lines: grouped_lines)
  end

  # ===========================================================================
  # Private: Data Loading
  # ===========================================================================

  defp load_voice_lines(project, sheet) do
    nodes = Flows.list_dialogue_nodes_by_speaker(project.id, sheet.id)

    Enum.map(nodes, fn node ->
      audio_asset = resolve_audio_asset(project.id, node.data["audio_asset_id"])

      %{
        node: node,
        flow: node.flow,
        text: node.data["text"] || "",
        audio_asset: audio_asset
      }
    end)
  end

  defp resolve_audio_asset(_project_id, nil), do: nil
  defp resolve_audio_asset(_project_id, ""), do: nil

  defp resolve_audio_asset(project_id, asset_id) do
    Assets.get_asset(project_id, asset_id)
  end

  # ===========================================================================
  # Function Components
  # ===========================================================================

  defp empty_voice_lines_state(assigns) do
    ~H"""
    <div class="bg-base-200/50 rounded-lg p-8 text-center">
      <.icon name="volume-x" class="size-12 mx-auto text-base-content/30 mb-4" />
      <p class="text-base-content/70 mb-2">{dgettext("sheets", "No voice lines")}</p>
      <p class="text-sm text-base-content/50">
        {dgettext("sheets", "Dialogue nodes using this sheet as speaker will appear here.")}
      </p>
    </div>
    """
  end

  attr :flow, :map, required: true
  attr :lines, :list, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :can_edit, :boolean, required: true
  attr :audio_assets, :list, required: true
  attr :uploading_node_id, :any, required: true
  attr :myself, :any, required: true
  attr :component_id, :string, required: true

  defp flow_group(assigns) do
    ~H"""
    <div>
      <.link
        navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows/#{@flow.id}"}
        class="flex items-center gap-2 mb-2 text-sm font-medium text-primary hover:underline"
      >
        <.icon name="git-branch" class="size-4" />
        {@flow.name}
        <%= if @flow.shortcut do %>
          <span class="text-xs text-base-content/50">#{@flow.shortcut}</span>
        <% end %>
      </.link>
      <div class="space-y-2 ml-6">
        <.voice_line_row
          :for={line <- @lines}
          line={line}
          workspace={@workspace}
          project={@project}
          can_edit={@can_edit}
          audio_assets={@audio_assets}
          uploading_node_id={@uploading_node_id}
          myself={@myself}
          component_id={@component_id}
        />
      </div>
    </div>
    """
  end

  attr :line, :map, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :can_edit, :boolean, required: true
  attr :audio_assets, :list, required: true
  attr :uploading_node_id, :any, required: true
  attr :myself, :any, required: true
  attr :component_id, :string, required: true

  defp voice_line_row(assigns) do
    text_preview = truncate_html(assigns.line.text, 80)
    node_id = assigns.line.node.id
    is_uploading = to_string(assigns.uploading_node_id) == to_string(node_id)

    assigns =
      assigns
      |> assign(:text_preview, text_preview)
      |> assign(:node_id, node_id)
      |> assign(:is_uploading, is_uploading)

    ~H"""
    <div class="p-3 bg-base-200/50 rounded-lg">
      <div class="flex items-start justify-between gap-2 mb-2">
        <p :if={@text_preview != ""} class="text-sm text-base-content/80 flex-1">
          {@text_preview}
        </p>
        <p :if={@text_preview == ""} class="text-sm text-base-content/40 italic flex-1">
          {dgettext("sheets", "(empty dialogue)")}
        </p>
        <.link
          navigate={
            ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows/#{@line.flow.id}?node=#{@node_id}"
          }
          class="btn btn-ghost btn-xs shrink-0"
          title={dgettext("sheets", "Open in flow editor")}
        >
          <.icon name="arrow-up-right" class="size-3.5" />
        </.link>
      </div>

      <%= if @line.audio_asset do %>
        <div class="flex items-center gap-2 text-xs text-base-content/60">
          <.icon name="volume-2" class="size-3" />
          <span class="truncate">{@line.audio_asset.filename}</span>
        </div>
        <audio controls class="w-full h-8 mt-1">
          <source src={@line.audio_asset.url} type={@line.audio_asset.content_type} />
        </audio>
        <button
          :if={@can_edit}
          type="button"
          phx-click="remove_audio"
          phx-target={@myself}
          phx-value-node-id={@node_id}
          class="btn btn-ghost btn-xs text-error mt-1"
        >
          <.icon name="x" class="size-3" />
          {dgettext("sheets", "Remove")}
        </button>
      <% else %>
        <%= if @can_edit do %>
          <div class="flex items-center gap-2 mt-1">
            <form phx-change="select_audio" phx-target={@myself} phx-value-node-id={@node_id}>
              <select name="audio_asset_id" class="select select-xs select-bordered">
                <option value="">{dgettext("sheets", "No audio")}</option>
                <option :for={asset <- @audio_assets} value={asset.id}>
                  {asset.filename}
                </option>
              </select>
            </form>
            <label class={[
              "btn btn-ghost btn-xs gap-1",
              @is_uploading && "btn-disabled"
            ]}>
              <span :if={@is_uploading} class="loading loading-spinner loading-xs"></span>
              <.icon :if={!@is_uploading} name="upload" class="size-3" />
              {if @is_uploading,
                do: dgettext("sheets", "Uploading..."),
                else: dgettext("sheets", "Upload")}
              <input
                type="file"
                accept="audio/*"
                class="hidden"
                phx-hook="AudioUpload"
                id={"#{@component_id}-upload-#{@node_id}"}
                data-target={@myself}
                data-node-id={@node_id}
                disabled={@is_uploading}
              />
            </label>
          </div>
        <% else %>
          <div class="flex items-center gap-2 text-xs text-base-content/40">
            <.icon name="volume-x" class="size-3" />
            <span>{dgettext("sheets", "No audio")}</span>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp truncate_html(nil, _max), do: ""
  defp truncate_html("", _max), do: ""

  defp truncate_html(html, max) do
    text =
      html
      |> HtmlSanitizeEx.strip_tags()
      |> String.trim()

    if String.length(text) > max do
      String.slice(text, 0, max) <> "..."
    else
      text
    end
  end
end
