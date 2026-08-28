defmodule Storyarn.AI.ExecutionCompatibilityTest do
  use ExUnit.Case, async: true

  alias Storyarn.AI.Execution

  test "keeps the former execution entry points available" do
    assert Code.ensure_loaded?(Execution)
    assert function_exported?(Execution, :preflight, 1)
    assert function_exported?(Execution, :execute, 1)
  end
end
