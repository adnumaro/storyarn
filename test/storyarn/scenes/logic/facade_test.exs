defmodule Storyarn.Scenes.LogicFacadeTest do
  use ExUnit.Case, async: true

  alias Storyarn.Scenes.Condition
  alias Storyarn.Scenes.Instruction
  alias Storyarn.Scenes.Logic

  test "preserves the stable condition and instruction contracts" do
    condition = %{"logic" => "all", "blocks" => []}
    assignments = [%{"id" => "incomplete"}]

    assert Logic.sanitize_condition(condition) == Condition.sanitize(condition)
    assert Logic.parse_condition(nil) == Condition.parse(nil)
    assert Logic.sanitize_instructions(assignments) == Instruction.sanitize(assignments)
    assert Logic.instruction_operator_label("add") == Instruction.operator_label("add")
  end

  test "exposes variable constraints without changing clamping semantics" do
    constraints = %{"min" => 2, "max" => 5}

    assert Logic.clamp_variable(1, constraints, "number") == 2
    assert Logic.clamp_variable(7, constraints, "number") == 5
    assert Logic.clamp_variable(3, constraints, "number") == 3
  end
end
