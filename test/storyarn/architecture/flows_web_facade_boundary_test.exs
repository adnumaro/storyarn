defmodule Storyarn.Architecture.FlowsWebFacadeBoundaryTest do
  use ExUnit.Case, async: true

  @flow_web_sources [
    "lib/storyarn_web/live/flow_sidebar_live.ex"
    | Path.wildcard("lib/storyarn_web/live/flow_live/**/*.ex")
  ]

  @flow_domain_sources [
    "lib/storyarn/flows.ex"
    | Path.wildcard("lib/storyarn/flows/**/*.ex")
  ]

  test "Flow Web enters the bounded context only through Storyarn.Flows" do
    violations =
      @flow_web_sources
      |> Enum.flat_map(&internal_flows_references/1)
      |> Enum.sort()

    assert violations == [], """
    StoryarnWeb.FlowLive may call only the public Storyarn.Flows facade.
    Move the operation behind Storyarn.Flows instead of importing a Flows internal:

    #{Enum.join(violations, "\n")}
    """
  end

  test "Flows domain does not depend on StoryarnWeb" do
    violations =
      @flow_domain_sources
      |> Enum.flat_map(&storyarn_web_references/1)
      |> Enum.sort()

    assert violations == [], """
    Storyarn.Flows cannot depend on its Phoenix or LiveVue adapters:

    #{Enum.join(violations, "\n")}
    """
  end

  test "Flow Web cannot publish generic business facts" do
    violations =
      Enum.filter(@flow_web_sources, fn path -> File.read!(path) =~ "Flows.emit_event" end)

    refute File.read!("lib/storyarn/flows.ex") =~ "defdelegate emit_event"

    assert violations == [], """
    Web adapters may call typed Flow commands, but may not choose an event name
    or construct a domain-event payload themselves:

    #{Enum.join(violations, "\n")}
    """
  end

  defp internal_flows_references(path) do
    source = File.read!(path)
    ast = Code.string_to_quoted!(source, file: path, columns: true)
    local_aliases = flow_facade_aliases(ast)

    ast
    |> module_aliases()
    |> Enum.filter(&internal_flows_alias?(&1.segments, local_aliases))
    |> Enum.map(&"#{path}:#{&1.line}: #{Enum.join(&1.segments, ".")}")
    |> Kernel.++(grouped_alias_violations(path, source))
    |> Enum.uniq()
  end

  defp flow_facade_aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, MapSet.new([:Flows]), fn
        {:alias, _meta, [{:__aliases__, _, [:Storyarn, :Flows]}, opts]} = node, aliases
        when is_list(opts) ->
          alias_name =
            case Keyword.get(opts, :as) do
              {:__aliases__, _, [name]} -> name
              _ -> :Flows
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

  defp internal_flows_alias?([:Storyarn, :Flows, _internal | _rest], _local_aliases), do: true

  defp internal_flows_alias?([local_alias, _internal | _rest], local_aliases),
    do: MapSet.member?(local_aliases, local_alias)

  defp internal_flows_alias?(_segments, _local_aliases), do: false

  defp grouped_alias_violations(path, source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      if Regex.match?(~r/\bStoryarn\.Flows\.\{/, line) do
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
