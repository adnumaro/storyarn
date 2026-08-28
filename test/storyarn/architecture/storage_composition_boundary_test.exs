defmodule Storyarn.Architecture.StorageCompositionBoundaryTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Workspaces.Banner.Adapters.Storage.Port

  @storage_namespace [:Storyarn, :Projects, :Assets, :Storage]

  test "the ENG-107 composition seam is explicit and cannot gain consumers silently" do
    assert storage_config_references() == %{
             "config/config.exs" => %{
               "Storage" => 2,
               "Storyarn.Projects.Assets.Storage" => 1
             }
           }

    assert Application.fetch_env!(:storyarn, Port) == [adapter: Storage]
  end

  defp storage_config_references do
    "config/**/*.exs"
    |> Path.wildcard()
    |> Enum.reduce(%{}, fn path, references_by_path ->
      matching_references =
        path
        |> File.read!()
        |> Code.string_to_quoted!(file: path)
        |> collect_storage_aliases()
        |> Enum.frequencies()

      if matching_references == %{} do
        references_by_path
      else
        Map.put(references_by_path, path, matching_references)
      end
    end)
  end

  defp collect_storage_aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, _meta, segments} = node, aliases ->
          if storage_alias?(segments) do
            {node, [Enum.join(segments, ".") | aliases]}
          else
            {node, aliases}
          end

        node, aliases ->
          {node, aliases}
      end)

    aliases
  end

  defp storage_alias?(@storage_namespace), do: true
  defp storage_alias?([:Storage | _rest]), do: true
  defp storage_alias?(_segments), do: false
end
