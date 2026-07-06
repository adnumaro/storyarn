defmodule Storyarn.ProjectTemplates.Artifact do
  @moduledoc false

  alias Storyarn.Assets

  def build_asset_manifest(project_id) do
    assets =
      project_id
      |> Assets.list_assets_for_export()
      |> Enum.map(fn asset ->
        %{
          "id" => asset.id,
          "filename" => asset.filename,
          "content_type" => asset.content_type,
          "size" => asset.size,
          "key" => asset.key,
          "url" => asset.url,
          "blob_hash" => asset.blob_hash,
          "metadata" => asset.metadata || %{}
        }
      end)

    %{
      "format_version" => 1,
      "assets" => assets,
      "asset_count" => length(assets)
    }
  end

  def checksum(data) do
    data
    |> canonicalize_checksum_data()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonicalize_checksum_data(data) when is_map(data) do
    entries =
      data
      |> Enum.map(fn {key, value} -> {to_string(key), canonicalize_checksum_data(value)} end)
      |> Enum.sort_by(fn {key, _value} -> key end)

    {:map, entries}
  end

  defp canonicalize_checksum_data(data) when is_list(data) do
    {:list, Enum.map(data, &canonicalize_checksum_data/1)}
  end

  defp canonicalize_checksum_data(data), do: data
end
