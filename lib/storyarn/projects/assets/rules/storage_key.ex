defmodule Storyarn.Projects.Assets.StorageKey do
  @moduledoc "Pure validation for canonical Project asset-storage keys and prefixes."

  @project_asset_namespaces ["assets"]
  @project_media_namespaces ["assets", "blobs"]

  @spec canonical?(term()) :: boolean()
  def canonical?(key) when is_binary(key) do
    key != "" and
      String.valid?(key) and
      not String.contains?(key, [<<0>>, "\\"]) and
      canonical_segments?(String.split(key, "/", trim: false))
  end

  def canonical?(_key), do: false

  @spec canonical_prefix?(term()) :: boolean()
  def canonical_prefix?(prefix) when is_binary(prefix) do
    String.ends_with?(prefix, "/") and not String.ends_with?(prefix, "//") and
      canonical?(String.trim_trailing(prefix, "/"))
  end

  def canonical_prefix?(_prefix), do: false

  @doc "Returns whether a key belongs to the Project asset namespace accepted by the media route."
  @spec project_asset_route_key?(integer(), term()) :: boolean()
  def project_asset_route_key?(project_id, key) do
    scoped_project_key?(project_id, key, @project_asset_namespaces)
  end

  @doc "Returns whether a key belongs to a browser-deliverable media namespace of a Project."
  @spec project_media_route_key?(integer(), term()) :: boolean()
  def project_media_route_key?(project_id, key) do
    scoped_project_key?(project_id, key, @project_media_namespaces)
  end

  defp scoped_project_key?(project_id, key, namespaces) when is_integer(project_id) and is_binary(key) do
    prefix = "projects/#{project_id}/"

    with true <- canonical?(key),
         true <- String.starts_with?(key, prefix),
         relative_key = String.replace_prefix(key, prefix, ""),
         [namespace | path_segments] <- String.split(relative_key, "/"),
         true <- namespace in namespaces,
         true <- path_segments != [] do
      true
    else
      _invalid_key -> false
    end
  end

  defp scoped_project_key?(_project_id, _key, _namespaces), do: false

  defp canonical_segments?(segments) do
    segments != [] and
      Enum.all?(segments, fn segment ->
        segment != "" and segment not in [".", ".."]
      end)
  end
end
