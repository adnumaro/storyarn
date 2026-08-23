defmodule Storyarn.Scenes.Versioning.AssetBlobKeys do
  @moduledoc false

  def blob_key(project_id, hash, ext), do: "projects/#{project_id}/blobs/#{hash}.#{ext}"

  def ext_from_content_type("image/jpeg"), do: "jpg"
  def ext_from_content_type("image/png"), do: "png"
  def ext_from_content_type("image/gif"), do: "gif"
  def ext_from_content_type("image/webp"), do: "webp"
  def ext_from_content_type("image/svg+xml"), do: "svg"
  def ext_from_content_type("audio/mpeg"), do: "mp3"
  def ext_from_content_type("audio/wav"), do: "wav"
  def ext_from_content_type("audio/ogg"), do: "ogg"
  def ext_from_content_type("audio/webm"), do: "webm"
  def ext_from_content_type("application/pdf"), do: "pdf"
  def ext_from_content_type("application/octet-stream"), do: "bin"

  def ext_from_content_type(other) do
    other |> String.split("/") |> List.last() |> String.split("+") |> List.first()
  end
end
