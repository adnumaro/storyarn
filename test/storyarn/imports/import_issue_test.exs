defmodule Storyarn.Imports.ImportIssueTest do
  use ExUnit.Case, async: true

  alias Storyarn.Imports.ImportIssue

  test "context always satisfies the map contract" do
    assert %ImportIssue{context: %{variable: "quest_started"}} =
             ImportIssue.new(:warning, :example, context: %{variable: "quest_started"})

    assert %ImportIssue{context: %{}} = ImportIssue.new(:warning, :example, context: nil)
    assert %ImportIssue{context: %{}} = ImportIssue.new(:warning, :example, context: "imported text")
    assert %ImportIssue{context: %{}} = ImportIssue.new(:warning, :example, context: [:not, :a, :map])
  end
end
