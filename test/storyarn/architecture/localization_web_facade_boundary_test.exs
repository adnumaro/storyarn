defmodule Storyarn.Architecture.LocalizationWebFacadeBoundaryTest do
  use ExUnit.Case, async: true

  @web_sources Path.wildcard("lib/storyarn_web/**/*.ex")
  @localization_domain_sources [
    "lib/storyarn/localization.ex"
    | Path.wildcard("lib/storyarn/localization/**/*.ex")
  ]
  @presentation_adapter_exceptions ["lib/storyarn_web/live_vue_encoders.ex"]

  test "StoryarnWeb enters Localization only through Storyarn.Localization" do
    violations =
      @web_sources
      |> Enum.reject(&(&1 in @presentation_adapter_exceptions))
      |> Enum.flat_map(&internal_localization_references/1)
      |> Enum.sort()

    assert violations == [], """
    StoryarnWeb may call only the public Storyarn.Localization facade.
    Move the operation behind the facade instead of importing a Localization internal:

    #{Enum.join(violations, "\n")}
    """
  end

  test "Localization domain does not depend on StoryarnWeb" do
    violations =
      @localization_domain_sources
      |> Enum.flat_map(&storyarn_web_references/1)
      |> Enum.sort()

    assert violations == [], """
    Storyarn.Localization cannot depend on its Phoenix or LiveVue adapters:

    #{Enum.join(violations, "\n")}
    """
  end

  defp internal_localization_references(path) do
    source = File.read!(path)
    ast = Code.string_to_quoted!(source, file: path, columns: true)
    local_aliases = localization_facade_aliases(ast)

    ast
    |> module_aliases()
    |> Enum.filter(&internal_localization_alias?(&1.segments, local_aliases))
    |> Enum.map(&"#{path}:#{&1.line}: #{Enum.join(&1.segments, ".")}")
    |> Kernel.++(grouped_alias_violations(path, source))
    |> Enum.uniq()
  end

  defp localization_facade_aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, MapSet.new([:Localization]), fn
        {:alias, _meta, [{:__aliases__, _, [:Storyarn, :Localization]}, opts]} = node, aliases
        when is_list(opts) ->
          alias_name =
            case Keyword.get(opts, :as) do
              {:__aliases__, _, [name]} -> name
              _other -> :Localization
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

  defp internal_localization_alias?([:Storyarn, :Localization, _internal | _rest], _aliases), do: true

  defp internal_localization_alias?([local_alias, _internal | _rest], aliases), do: MapSet.member?(aliases, local_alias)

  defp internal_localization_alias?(_segments, _aliases), do: false

  defp grouped_alias_violations(path, source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      if Regex.match?(~r/\bStoryarn\.Localization\.\{/, line) do
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
