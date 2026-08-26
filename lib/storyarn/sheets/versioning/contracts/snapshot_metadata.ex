defmodule Storyarn.Sheets.Versioning.SnapshotMetadata do
  @moduledoc false

  @storage_metadata_keys ~w(
    blob_key key project_id storage_key thumbnail_key thumbnail_path url web_url
  )
  @unsafe_project_storage_snake_key ~r/(?:\A|_)(?:blob|storage|thumbnail|presigned|signed|web|object|current_object)_(?:key|keys|path|paths|url|urls)\z/i
  @unsafe_project_storage_compound_key ~r/(?:blob|storage|thumbnail|presigned|signed|web|object|currentobject)(?:key|keys|path|paths|url|urls)\z/i
  @unsafe_project_ownership_key ~r/\Aproject_?(?:id|ids)\z/i
  @unsafe_project_generic_storage_key ~r/\A(?:key|keys|url|urls)\z/i

  def scrub_persisted_asset_metadata(metadata), do: scrub(metadata)

  defp scrub(metadata) when is_map(metadata) do
    Enum.reduce(metadata, %{}, fn {key, value}, portable ->
      if persisted_storage_metadata_key?(key),
        do: portable,
        else: Map.put(portable, key, scrub(value))
    end)
  end

  defp scrub(metadata) when is_list(metadata), do: Enum.map(metadata, &scrub/1)
  defp scrub(metadata), do: metadata

  defp persisted_storage_metadata_key?(key) when is_binary(key) do
    key in @storage_metadata_keys or
      (String.valid?(key) and
         (Regex.match?(@unsafe_project_storage_snake_key, key) or
            Regex.match?(@unsafe_project_storage_compound_key, key) or
            Regex.match?(@unsafe_project_ownership_key, key) or
            Regex.match?(@unsafe_project_generic_storage_key, key)))
  end

  defp persisted_storage_metadata_key?(key) when is_atom(key),
    do: key |> Atom.to_string() |> persisted_storage_metadata_key?()

  defp persisted_storage_metadata_key?(_key), do: false
end
