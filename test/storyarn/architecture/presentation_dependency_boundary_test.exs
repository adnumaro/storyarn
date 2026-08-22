defmodule Storyarn.Architecture.PresentationDependencyBoundaryTest do
  use ExUnit.Case, async: true

  @domain_sources Path.wildcard("lib/storyarn/**/*.ex")

  test "domain code does not depend on LiveVue" do
    violations =
      @domain_sources
      |> Enum.flat_map(&live_vue_references/1)
      |> Enum.sort()

    assert violations == [], """
    Storyarn domain code cannot depend on the LiveVue presentation layer.
    Keep encoders and other LiveVue adapters under StoryarnWeb:

    #{Enum.join(violations, "\n")}
    """
  end

  defp live_vue_references(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path, columns: true)

    {_ast, references} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, meta, [:LiveVue | _rest] = segments} = node, references ->
          reference = "#{path}:#{meta[:line]}: #{Enum.join(segments, ".")}"
          {node, [reference | references]}

        node, references ->
          {node, references}
      end)

    Enum.uniq(references)
  end
end
