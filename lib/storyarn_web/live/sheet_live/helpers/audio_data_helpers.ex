defmodule StoryarnWeb.SheetLive.Helpers.AudioDataHelpers do
  @moduledoc false

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Storyarn.Assets
  alias Storyarn.Billing
  alias Storyarn.Collaboration
  alias Storyarn.Flows

  def load_audio_data(socket) do
    %{sheet: sheet, project: project} = socket.assigns
    nodes = Flows.list_dialogue_nodes_by_speaker(project.id, sheet.id)

    voice_lines =
      Enum.map(nodes, fn node ->
        audio_asset = resolve_audio_asset(project.id, node.data["audio_asset_id"])

        %{
          nodeId: node.id,
          flowId: node.flow.id,
          flowName: node.flow.name,
          flowShortcut: node.flow.shortcut,
          text: truncate_html_text(node.data["text"], 80),
          audioAsset: serialize_audio_asset(audio_asset)
        }
      end)

    grouped_lines =
      voice_lines
      |> Enum.group_by(fn vl -> {vl.flowId, vl.flowName, vl.flowShortcut} end)
      |> Enum.sort_by(fn {{_, name, _}, _} -> name end)
      |> Enum.map(fn {{flow_id, flow_name, flow_shortcut}, lines} ->
        %{
          flow: %{id: flow_id, name: flow_name, shortcut: flow_shortcut},
          lines: lines
        }
      end)

    audio_assets =
      project.id
      |> Assets.list_assets(content_type: "audio/")
      |> Enum.map(&serialize_audio_asset/1)

    assign(socket, :audio_data, %{
      grouped_lines: grouped_lines,
      audio_assets: audio_assets
    })
  end

  def update_node_audio(socket, node_id_str, audio_asset_id) do
    {node_id, ""} = Integer.parse(to_string(node_id_str))
    project_id = socket.assigns.project.id

    nodes = Flows.list_dialogue_nodes_by_speaker(project_id, socket.assigns.sheet.id)
    line = Enum.find(nodes, &(&1.id == node_id))

    if line do
      node = Flows.get_node!(line.flow.id, node_id)
      updated_data = Map.put(node.data, "audio_asset_id", audio_asset_id)

      case Flows.update_node_data(node, updated_data) do
        {:ok, _updated_node, _meta} ->
          {:noreply, load_audio_data(socket)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not update audio."))}
      end
    else
      {:noreply, socket}
    end
  end

  def process_audio_upload(socket, node_id, filename, content_type, binary_data) do
    project = socket.assigns.project
    user = socket.assigns.current_scope.user

    with :ok <- validate_audio_content_type(content_type),
         :ok <- Billing.can_upload_asset_for_project?(project, byte_size(binary_data)),
         {:ok, asset} <- upload_audio_asset(binary_data, filename, content_type, project, user) do
      Collaboration.broadcast_change({:assets, project.id}, :asset_created, %{})
      update_node_audio(socket, node_id, asset.id)
    else
      {:error, :unsupported_file_type} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Unsupported file type."))}

      {:error, :limit_reached, _details} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("sheets", "Storage limit reached. Upgrade your plan.")
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not upload audio file."))}
    end
  end

  defp resolve_audio_asset(_project_id, nil), do: nil
  defp resolve_audio_asset(_project_id, ""), do: nil

  defp resolve_audio_asset(project_id, asset_id) do
    Assets.get_asset(project_id, asset_id)
  end

  defp validate_audio_content_type(content_type) do
    if Assets.allowed_content_type?(content_type),
      do: :ok,
      else: {:error, :unsupported_file_type}
  end

  defp upload_audio_asset(binary_data, filename, content_type, project, user) do
    Assets.upload_binary_and_create_asset(
      binary_data,
      %{filename: filename, content_type: content_type},
      project,
      user
    )
  end

  defp serialize_audio_asset(nil), do: nil

  defp serialize_audio_asset(asset) do
    %{
      id: asset.id,
      filename: asset.filename,
      url: asset.url,
      contentType: asset.content_type
    }
  end

  defp truncate_html_text(nil, _max), do: ""
  defp truncate_html_text("", _max), do: ""

  defp truncate_html_text(html, max) do
    text =
      html
      |> Floki.parse_document!()
      |> Floki.text()
      |> String.trim()

    if String.length(text) > max do
      String.slice(text, 0, max) <> "..."
    else
      text
    end
  end
end
