defmodule Storyarn.Architecture.SheetsWebFacadeBoundaryTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Versioning
  alias Storyarn.Projects.Versioning.Builders.SheetBuilder
  alias Storyarn.Sheets.Versioning.SheetSnapshot

  @sheet_web_sources [
    "lib/storyarn_web/live/sheets_sidebar_live.ex"
    | Path.wildcard("lib/storyarn_web/live/sheet_live/**/*.ex")
  ]

  @sheet_domain_sources [
    "lib/storyarn/sheets.ex"
    | Path.wildcard("lib/storyarn/sheets/**/*.ex")
  ]

  test "Sheet Web enters the bounded context only through Storyarn.Sheets" do
    violations =
      @sheet_web_sources
      |> Enum.flat_map(&internal_sheets_references/1)
      |> Enum.sort()

    assert violations == [], """
    StoryarnWeb.SheetLive may call only the public Storyarn.Sheets facade.
    Move the operation behind Storyarn.Sheets instead of importing a Sheets internal:

    #{Enum.join(violations, "\n")}
    """
  end

  test "Sheets domain does not depend on StoryarnWeb" do
    violations =
      @sheet_domain_sources
      |> Enum.flat_map(&storyarn_web_references/1)
      |> Enum.sort()

    assert violations == [], """
    Storyarn.Sheets cannot depend on its Phoenix or LiveVue adapters:

    #{Enum.join(violations, "\n")}
    """
  end

  test "Sheet Web cannot publish generic business facts" do
    violations =
      Enum.filter(@sheet_web_sources, fn path -> File.read!(path) =~ "Sheets.emit_event" end)

    refute File.read!("lib/storyarn/sheets.ex") =~ "defdelegate emit_event"

    assert violations == [], """
    Web adapters may call typed Sheet commands, but may not choose an event name
    or construct a domain-event payload themselves:

    #{Enum.join(violations, "\n")}
    """
  end

  test "the legacy shared Versioning facade no longer serves Sheet entities" do
    Code.ensure_loaded!(Versioning)

    for {fun, arity} <- [
          create_version: 5,
          maybe_create_version: 5,
          restore_version: 4,
          list_versions: 3,
          get_version: 3,
          delete_version: 1,
          load_version_snapshot: 1,
          get_builder!: 1
        ] do
      refute function_exported?(Versioning, fun, arity),
             "the shared Versioning facade must not regrow its entity arm (#{fun}/#{arity})"
    end

    # The Sheet snapshot writer is context-owned; the shared portable builder
    # keeps only build/validate/instantiate/diff/scan for project snapshots.
    Code.ensure_loaded!(SheetSnapshot)
    assert function_exported?(SheetSnapshot, :restore_snapshot, 3)

    Code.ensure_loaded!(SheetBuilder)
    refute function_exported?(SheetBuilder, :restore_snapshot, 2)
    refute function_exported?(SheetBuilder, :restore_snapshot, 3)
  end

  test "retired shared utilities stay deleted" do
    for path <- [
          "lib/storyarn/shortcuts.ex",
          "lib/storyarn/shared/soft_delete.ex",
          "lib/storyarn/shared/formula_engine.ex",
          "lib/storyarn/shared/formula_runtime.ex",
          "lib/storyarn/shared/tree_operations.ex",
          "lib/storyarn/shared/hierarchical_schema.ex",
          "lib/storyarn/shared/shortcut_helpers.ex",
          "lib/storyarn_web/helpers/version_event_helpers.ex",
          "lib/storyarn_web/helpers/version_history_helpers.ex",
          "lib/storyarn_web/live/version_viewer_live.ex"
        ] do
      refute File.exists?(path), "#{path} was retired by the bounded-context migration and must stay deleted"
    end
  end

  defp internal_sheets_references(path) do
    source = File.read!(path)
    ast = Code.string_to_quoted!(source, file: path, columns: true)
    local_aliases = sheets_facade_aliases(ast)

    ast
    |> module_aliases()
    |> Enum.filter(&internal_sheets_alias?(&1.segments, local_aliases))
    |> Enum.map(&"#{path}:#{&1.line}: #{Enum.join(&1.segments, ".")}")
    |> Kernel.++(grouped_alias_violations(path, source))
    |> Enum.uniq()
  end

  defp sheets_facade_aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, MapSet.new([:Sheets]), fn
        {:alias, _meta, [{:__aliases__, _, [:Storyarn, :Sheets]}, opts]} = node, aliases
        when is_list(opts) ->
          alias_name =
            case Keyword.get(opts, :as) do
              {:__aliases__, _, [name]} -> name
              _ -> :Sheets
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

  defp internal_sheets_alias?([:Storyarn, :Sheets, _internal | _rest], _local_aliases), do: true

  defp internal_sheets_alias?([local_alias, _internal | _rest], local_aliases),
    do: MapSet.member?(local_aliases, local_alias)

  defp internal_sheets_alias?(_segments, _local_aliases), do: false

  defp grouped_alias_violations(path, source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      if Regex.match?(~r/\bStoryarn\.Sheets\.\{/, line) do
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
