defmodule Storyarn.Architecture.CommercialBoundaryTest do
  use ExUnit.Case, async: true

  @commercial_sources ["lib/storyarn/commercial.ex" | Path.wildcard("lib/storyarn/commercial/**/*.ex")]
  @obsolete_namespaces Enum.map(
                         ~w(Commercial Billing Entitlements ProjectStorageReservations),
                         &Enum.join(["Storyarn", "Platform", &1], ".")
                       )

  test "Commercial owns its read models without compiling against consumer internals" do
    violations =
      @commercial_sources
      |> Enum.flat_map(&consumer_internal_references/1)
      |> Enum.sort()

    assert violations == [], """
    Commercial owns consumer-local projections over the shared tables. It must
    not import Projects, Workspaces, Sheets, Flows, Scenes or Accounts internals:

    #{Enum.join(violations, "\n")}
    """
  end

  test "the obsolete Platform commercial namespaces cannot return" do
    refute File.dir?("lib/storyarn/platform/commercial")

    violations =
      (Path.wildcard("lib/**/*.ex") ++
         Path.wildcard("test/**/*.exs") ++
         Path.wildcard("config/**/*.exs"))
      |> Enum.flat_map(fn path ->
        source = File.read!(path)

        for namespace <- @obsolete_namespaces,
            source =~ namespace,
            do: "#{path}: #{namespace}"
      end)
      |> Enum.sort()

    assert violations == [],
           "callers must use Storyarn.Commercial; obsolete namespace references: #{inspect(violations)}"
  end

  defp consumer_internal_references(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path, columns: true)

    {_ast, aliases} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, meta, [:Storyarn, context, _internal | _rest] = segments} = node, acc
        when context in [:Accounts, :Workspaces, :Projects, :Sheets, :Flows, :Scenes] ->
          {node, ["#{path}:#{meta[:line]}: #{Enum.join(segments, ".")}" | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(aliases)
  end
end
