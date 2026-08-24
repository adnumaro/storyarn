defmodule Storyarn.Architecture.WorkspacesWebFacadeBoundaryTest do
  use ExUnit.Case, async: true

  @workspace_web_sources Path.wildcard("lib/storyarn_web/live/workspace_live/**/*.ex") ++
                           Path.wildcard("lib/storyarn_web/live/settings_live/workspace_*.ex")

  @workspace_domain_sources [
    "lib/storyarn/workspaces.ex"
    | Path.wildcard("lib/storyarn/workspaces/**/*.ex")
  ]

  @retired_shared_consumers [
    "lib/storyarn/shared/invitation_operations.ex",
    "lib/storyarn/shared/invitation_schema.ex",
    "lib/storyarn/shared/invitation_notifier.ex",
    "lib/storyarn/shared/membership_operations.ex"
  ]

  test "Workspace Web enters the bounded context only through Storyarn.Workspaces" do
    violations =
      @workspace_web_sources
      |> Enum.flat_map(&internal_workspaces_references/1)
      |> Enum.sort()

    assert violations == [], """
    StoryarnWeb workspace pages may call only the public Storyarn.Workspaces facade.
    Move the operation behind Storyarn.Workspaces instead of importing a Workspaces internal:

    #{Enum.join(violations, "\n")}
    """
  end

  test "Workspaces domain does not depend on StoryarnWeb" do
    violations =
      @workspace_domain_sources
      |> Enum.flat_map(&storyarn_web_references/1)
      |> Enum.sort()

    assert violations == [], """
    Storyarn.Workspaces cannot depend on its Phoenix or LiveVue adapters:

    #{Enum.join(violations, "\n")}
    """
  end

  test "Workspace Web cannot publish generic business facts" do
    violations =
      Enum.filter(@workspace_web_sources, fn path ->
        File.read!(path) =~ "Workspaces.Events"
      end)

    refute File.read!("lib/storyarn/workspaces.ex") =~ "defdelegate emit_event"

    assert violations == [], """
    Web adapters may call typed Workspace commands, but may not choose an event name
    or construct a domain-event payload themselves:

    #{Enum.join(violations, "\n")}
    """
  end

  test "the shared invitation machinery serves only the Projects arm" do
    violations =
      @retired_shared_consumers
      |> Enum.flat_map(&workspaces_code_references/1)
      |> Enum.sort()

    assert violations == [], """
    The workspace arm of the shared invitation/membership machinery moved into
    Storyarn.Workspaces during the ENG-92 migration and must not regrow here:

    #{Enum.join(violations, "\n")}
    """
  end

  defp internal_workspaces_references(path) do
    source = File.read!(path)
    ast = Code.string_to_quoted!(source, file: path, columns: true)
    local_aliases = workspaces_facade_aliases(ast)

    ast
    |> module_aliases()
    |> Enum.filter(&internal_workspaces_alias?(&1.segments, local_aliases))
    |> Enum.map(&"#{path}:#{&1.line}: #{Enum.join(&1.segments, ".")}")
    |> Kernel.++(grouped_alias_violations(path, source))
    |> Enum.uniq()
  end

  defp workspaces_facade_aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, MapSet.new([:Workspaces]), fn
        {:alias, _meta, [{:__aliases__, _, [:Storyarn, :Workspaces]}, opts]} = node, aliases
        when is_list(opts) ->
          alias_name =
            case Keyword.get(opts, :as) do
              {:__aliases__, _, [name]} -> name
              _ -> :Workspaces
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

  defp internal_workspaces_alias?([:Storyarn, :Workspaces, _internal | _rest], _local_aliases), do: true

  defp internal_workspaces_alias?([local_alias, _internal | _rest], local_aliases),
    do: MapSet.member?(local_aliases, local_alias)

  defp internal_workspaces_alias?(_segments, _local_aliases), do: false

  defp grouped_alias_violations(path, source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      if Regex.match?(~r/\bStoryarn\.Workspaces\.\{/, line) do
        ["#{path}:#{line_number}: #{String.trim(line)}"]
      else
        []
      end
    end)
  end

  defp workspaces_code_references(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path, columns: true)

    ast
    |> module_aliases()
    |> Enum.filter(&match?([:Storyarn, :Workspaces | _rest], &1.segments))
    |> Enum.map(&"#{path}:#{&1.line}: #{Enum.join(&1.segments, ".")}")
    |> Enum.uniq()
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
