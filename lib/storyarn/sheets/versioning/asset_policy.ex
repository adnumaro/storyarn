defmodule Storyarn.Sheets.Versioning.AssetPolicy do
  @moduledoc false

  @allowed_content_types ~w(
    image/jpeg image/png image/gif image/webp
    audio/mpeg audio/wav audio/ogg audio/webm
    application/pdf
  )

  def allowed_content_type?(content_type), do: content_type in @allowed_content_types

  def sanitize_filename(filename) do
    sanitized =
      filename
      |> String.split(~r/[\/\\]/)
      |> List.last()
      |> String.replace(~r/[^\w\.\-]/, "_")
      |> String.downcase()
      |> String.slice(0, 255)

    case sanitized do
      value when value in ["", ".", ".."] -> "file"
      ".storyarn-copy" -> "_storyarn-copy"
      value -> value
    end
  end
end
