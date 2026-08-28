defmodule Storyarn.Architecture.ScenesWebFacadeBoundaryTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Versioning.Builders.SceneBuilder
  alias Storyarn.Scenes.Versioning.SceneSnapshot

  @scene_web_sources [
    "lib/storyarn_web/live/scene_sidebar_live.ex"
    | Path.wildcard("lib/storyarn_web/live/scene_live/**/*.ex")
  ]

  @scene_domain_sources [
    "lib/storyarn/scenes.ex"
    | Path.wildcard("lib/storyarn/scenes/**/*.ex")
  ]

  test "Scene Web enters the bounded context only through Storyarn.Scenes" do
    violations =
      @scene_web_sources
      |> Enum.flat_map(&internal_scenes_references/1)
      |> Enum.sort()

    assert violations == [], """
    StoryarnWeb.SceneLive may call only the public Storyarn.Scenes facade.
    Move the operation behind Storyarn.Scenes instead of importing a Scenes internal:

    #{Enum.join(violations, "\n")}
    """
  end

  test "Scenes domain does not depend on StoryarnWeb" do
    violations =
      @scene_domain_sources
      |> Enum.flat_map(&storyarn_web_references/1)
      |> Enum.sort()

    assert violations == [], """
    Storyarn.Scenes cannot depend on its Phoenix or LiveVue adapters:

    #{Enum.join(violations, "\n")}
    """
  end

  test "Scene Web cannot publish generic business facts" do
    violations =
      Enum.filter(@scene_web_sources, fn path -> File.read!(path) =~ "Scenes.emit_event" end)

    refute File.read!("lib/storyarn/scenes.ex") =~ "defdelegate emit_event"

    assert violations == [], """
    Web adapters may call typed Scene commands, but may not choose an event name
    or construct a domain-event payload themselves:

    #{Enum.join(violations, "\n")}
    """
  end

  test "foreign contexts do not publish ordinary Scene writers" do
    forbidden_exports = [
      {Storyarn.Sheets, :update_scene_zone_references, 1},
      {Storyarn.Sheets, :delete_map_zone_references, 1},
      {Storyarn.Sheets, :update_scene_pin_references, 1},
      {Storyarn.Sheets, :delete_map_pin_references, 1},
      {SceneBuilder, :restore_snapshot, 2},
      {SceneBuilder, :restore_snapshot, 3},
      {SceneSnapshot, :build_capture_snapshot, 1},
      {SceneSnapshot, :instantiate_snapshot, 2},
      {SceneSnapshot, :instantiate_snapshot, 3}
    ]

    # The global Shortcuts module is deleted outright — stronger than any
    # per-function refutation.
    assert Code.ensure_loaded(Storyarn.Shortcuts) == {:error, :nofile},
           "Storyarn.Shortcuts must stay deleted; per-tool shortcut policy owns generation"

    Enum.each(forbidden_exports, fn {module, function, arity} ->
      Code.ensure_loaded!(module)

      refute function_exported?(module, function, arity),
             "#{inspect(module)}.#{function}/#{arity} reintroduces a Scene writer outside Storyarn.Scenes"
    end)

    refute File.exists?("lib/storyarn/shared/soft_delete.ex")
  end

  test "Scene storage integrations remain behind Scene-owned adapters" do
    adapter_sources =
      Path.wildcard("lib/storyarn/scenes/{assets,versioning}/adapters/storage/**/*.ex")

    non_adapter_sources = Enum.reject(@scene_domain_sources, &String.contains?(&1, "/adapters/"))

    policy = File.read!("config/architecture_boundaries.exs")

    refute File.exists?("lib/storyarn/scenes/project_assets.ex")
    refute File.exists?("lib/storyarn/scenes/asset_commands.ex")

    direct_storage_references =
      Enum.filter(non_adapter_sources, fn path ->
        Regex.match?(
          ~r/\bStoryarn\.Projects\.Assets\.(?:Storage|StorageHash|StorageKeyLock)\b|\bStoryarn\.Platform\.ObjectStorage\b/,
          File.read!(path)
        )
      end)

    assert direct_storage_references == [],
           "Scene workflows must reach shared storage only through Scene-owned adapters: " <>
             inspect(direct_storage_references)

    allowed_storage_contracts = MapSet.new(["Storyarn.Platform.ObjectStorage"])

    adapter_references =
      adapter_sources
      |> Enum.flat_map(fn path ->
        ~r/Storyarn\.(?:Projects\.Assets\.(?:Storage|StorageHash|StorageKeyLock)[A-Za-z.]*|Platform\.ObjectStorage(?:\.[A-Za-z.]+)?)/
        |> Regex.scan(File.read!(path))
        |> List.flatten()
      end)
      |> MapSet.new()

    assert adapter_references == allowed_storage_contracts,
           "Scene storage adapters may use only the public Platform ObjectStorage facade, got: " <>
             inspect(adapter_references)

    assert File.exists?("lib/storyarn/scenes/assets/adapters/storage/objects.ex")
    assert File.exists?("lib/storyarn/scenes/versioning/adapters/storage/snapshot_storage.ex")
    refute Enum.any?(adapter_sources, &(File.read!(&1) =~ "Storyarn.Projects.Assets.BlobStore"))
    refute policy =~ "lib/storyarn/scenes/project_assets.ex"
  end

  defp internal_scenes_references(path) do
    source = File.read!(path)
    ast = Code.string_to_quoted!(source, file: path, columns: true)
    local_aliases = scenes_facade_aliases(ast)

    ast
    |> module_aliases()
    |> Enum.filter(&internal_scenes_alias?(&1.segments, local_aliases))
    |> Enum.map(&"#{path}:#{&1.line}: #{Enum.join(&1.segments, ".")}")
    |> Kernel.++(grouped_alias_violations(path, source))
    |> Enum.uniq()
  end

  defp scenes_facade_aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, MapSet.new([:Scenes]), fn
        {:alias, _meta, [{:__aliases__, _, [:Storyarn, :Scenes]}, opts]} = node, aliases
        when is_list(opts) ->
          alias_name =
            case Keyword.get(opts, :as) do
              {:__aliases__, _, [name]} -> name
              _ -> :Scenes
            end

          {node, MapSet.put(aliases, alias_name)}

        node, aliases ->
          {node, aliases}
      end)

    aliases
  end

  defp module_aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, meta, segments} = node, aliases ->
          {node, [%{segments: segments, line: meta[:line]} | aliases]}

        node, aliases ->
          {node, aliases}
      end)

    aliases
  end

  defp internal_scenes_alias?([:Storyarn, :Scenes, _internal | _rest], _local_aliases), do: true

  defp internal_scenes_alias?([local_alias, _internal | _rest], local_aliases),
    do: MapSet.member?(local_aliases, local_alias)

  defp internal_scenes_alias?(_segments, _local_aliases), do: false

  defp grouped_alias_violations(path, source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      if Regex.match?(~r/\bStoryarn\.Scenes\.\{/, line) do
        ["#{path}:#{line_number}: #{String.trim(line)}"]
      else
        []
      end
    end)
  end

  defp storyarn_web_references(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path, columns: true)

    ast
    |> module_aliases()
    |> Enum.filter(&match?([:StoryarnWeb | _rest], &1.segments))
    |> Enum.map(&"#{path}:#{&1.line}: #{Enum.join(&1.segments, ".")}")
    |> Enum.uniq()
  end
end
