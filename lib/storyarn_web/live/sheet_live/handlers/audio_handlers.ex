defmodule StoryarnWeb.SheetLive.Handlers.AudioHandlers do
  @moduledoc """
  Handles audio tab events for the V2 sheet editor.
  """

  import Phoenix.LiveView, only: [put_flash: 3]
  use Gettext, backend: Storyarn.Gettext

  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.SheetLive.Helpers.AudioDataHelpers

  def handle_select(%{"node-id" => node_id, "audio_asset_id" => asset_id_str}, socket, _helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case Integer.parse(to_string(asset_id_str)) do
        {asset_id, ""} -> AudioDataHelpers.update_node_audio(socket, node_id, asset_id)
        _ -> {:noreply, socket}
      end
    end)
  end

  def handle_remove(%{"node-id" => node_id}, socket, _helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      AudioDataHelpers.update_node_audio(socket, node_id, nil)
    end)
  end

  def handle_upload(params, socket, _helpers) do
    %{"filename" => filename, "content_type" => content_type, "data" => data, "node_id" => node_id} = params

    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with [_header, base64_data] <- String.split(data, ",", parts: 2),
           {:ok, binary_data} <- Base.decode64(base64_data) do
        AudioDataHelpers.process_audio_upload(socket, node_id, filename, content_type, binary_data)
      else
        _ ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Invalid file data."))}
      end
    end)
  end
end
