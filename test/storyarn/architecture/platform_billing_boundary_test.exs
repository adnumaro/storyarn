defmodule Storyarn.Architecture.PlatformBillingBoundaryTest do
  use ExUnit.Case, async: true

  @billing_sources Enum.uniq([
                     "lib/storyarn/platform/billing.ex" | Path.wildcard("lib/storyarn/platform/billing/**/*.ex")
                   ])

  test "Platform Billing does not compile against Projects internals" do
    violations =
      @billing_sources
      |> Enum.flat_map(&projects_references/1)
      |> Enum.sort()

    assert violations == [], """
    Platform Billing owns consumer-local projections over the shared tables.
    It must not import Project schemas or business implementations:

    #{Enum.join(violations, "\n")}
    """
  end

  defp projects_references(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path, columns: true)

    {_ast, aliases} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, meta, [:Storyarn, :Projects | _rest] = segments} = node, acc ->
          {node, ["#{path}:#{meta[:line]}: #{Enum.join(segments, ".")}" | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(aliases)
  end
end
