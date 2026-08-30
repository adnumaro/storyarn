defmodule StoryarnWeb.SheetLive.Helpers.AudioDataHelpers do
  @moduledoc false

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Storyarn.Platform.Collaboration
  alias Storyarn.Sheets
  alias StoryarnWeb.PrivateMedia

  def load_audio_data(socket) do
    %{sheet: sheet, project: project} = socket.assigns
    nodes = Sheets.list_dialogue_audio_lines(project.id, sheet.id)

    audio_assets = Sheets.list_assets(project.id, content_type: "audio/")
    audio_assets_by_id = Map.new(audio_assets, &{&1.id, &1})

    voice_lines =
      Enum.map(nodes, fn node ->
        audio_asset = resolve_audio_asset(audio_assets_by_id, node.data["audio_asset_id"])

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

    serialized_audio_assets = Enum.map(audio_assets, &serialize_audio_asset/1)

    assign(socket, :audio_data, %{
      grouped_lines: grouped_lines,
      audio_assets: serialized_audio_assets
    })
  end

  def update_node_audio(socket, node_id_str, audio_asset_id) do
    case assign_node_audio(socket, node_id_str, audio_asset_id) do
      {:ok, _receipt} ->
        {:noreply, load_audio_data(socket)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> load_audio_data()
         |> put_flash(
           :error,
           dgettext("sheets", "This dialogue line is no longer available. Refresh and try again.")
         )}

      {:error, {:invalid_project_reference, :audio_asset_id, _value}} ->
        invalid_audio_selection(socket)

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not update audio."))}
    end
  end

  def invalid_audio_selection(socket) do
    {:noreply,
     socket
     |> load_audio_data()
     |> put_flash(:error, dgettext("sheets", "The selected audio is no longer available."))}
  end

  def process_audio_upload(socket, node_id, filename, content_type, binary_data) do
    project = socket.assigns.project
    user = socket.assigns.current_scope.user

    with :ok <- validate_audio_content_type(content_type),
         {:ok, asset} <- upload_audio_asset(binary_data, filename, content_type, project, user) do
      Collaboration.broadcast_change({:assets, project.id}, :asset_created, %{})

      case assign_node_audio(socket, node_id, asset.id) do
        {:ok, _receipt} ->
          {:noreply, load_audio_data(socket)}

        {:error, _reason} ->
          {:noreply,
           socket
           |> load_audio_data()
           |> put_flash(
             :error,
             dgettext(
               "sheets",
               "Audio uploaded, but it could not be attached to the dialogue. It remains available in your assets."
             )
           )}
      end
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

  defp resolve_audio_asset(_assets_by_id, nil), do: nil
  defp resolve_audio_asset(_assets_by_id, ""), do: nil

  defp resolve_audio_asset(assets_by_id, asset_id) when is_integer(asset_id), do: Map.get(assets_by_id, asset_id)

  defp resolve_audio_asset(assets_by_id, asset_id) do
    case Integer.parse(to_string(asset_id)) do
      {parsed_id, ""} -> Map.get(assets_by_id, parsed_id)
      _ -> nil
    end
  end

  defp validate_audio_content_type(content_type) do
    if is_binary(content_type) and String.starts_with?(content_type, "audio/") and
         Sheets.allowed_asset_content_type?(content_type),
       do: :ok,
       else: {:error, :unsupported_file_type}
  end

  defp assign_node_audio(socket, node_id, audio_asset_id) do
    with {:ok, normalized_node_id} <- parse_positive_id(node_id) do
      Sheets.update_dialogue_audio(
        socket.assigns.project.id,
        socket.assigns.sheet.id,
        normalized_node_id,
        audio_asset_id
      )
    end
  end

  defp parse_positive_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_positive_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _invalid -> {:error, :not_found}
    end
  end

  defp parse_positive_id(_value), do: {:error, :not_found}

  defp upload_audio_asset(binary_data, filename, content_type, project, user) do
    Sheets.create_binary_asset(
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
      url: PrivateMedia.asset_url(asset),
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
