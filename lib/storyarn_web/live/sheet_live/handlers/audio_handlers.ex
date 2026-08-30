defmodule StoryarnWeb.SheetLive.Handlers.AudioHandlers do
  @moduledoc """
  Handles audio tab events for the V2 sheet editor.
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.LiveView, only: [put_flash: 3]

  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.SheetLive.Helpers.AudioDataHelpers

  def handle_select(%{"node-id" => node_id, "audio_asset_id" => asset_id_str}, socket, _helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case parse_positive_id(asset_id_str) do
        {:ok, asset_id} -> AudioDataHelpers.update_node_audio(socket, node_id, asset_id)
        :error -> AudioDataHelpers.invalid_audio_selection(socket)
      end
    end)
  end

  def handle_select(_params, socket, _helpers) do
    Authorize.with_authorization(socket, :edit_content, &AudioDataHelpers.invalid_audio_selection/1)
  end

  def handle_remove(%{"node-id" => node_id}, socket, _helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      AudioDataHelpers.update_node_audio(socket, node_id, nil)
    end)
  end

  def handle_remove(_params, socket, _helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      AudioDataHelpers.update_node_audio(socket, nil, nil)
    end)
  end

  def handle_upload(params, socket, _helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with %{
             "filename" => filename,
             "content_type" => content_type,
             "data" => data,
             "node_id" => node_id
           }
           when is_binary(filename) and is_binary(content_type) and is_binary(data) <- params,
           [_header, base64_data] <- String.split(data, ",", parts: 2),
           {:ok, binary_data} <- Base.decode64(base64_data) do
        AudioDataHelpers.process_audio_upload(
          socket,
          node_id,
          filename,
          content_type,
          binary_data
        )
      else
        _ ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Invalid file data."))}
      end
    end)
  end

  defp parse_positive_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_positive_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _invalid -> :error
    end
  end

  defp parse_positive_id(_value), do: :error
end
