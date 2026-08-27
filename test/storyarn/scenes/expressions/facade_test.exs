defmodule Storyarn.Scenes.ExpressionsFacadeTest do
  use ExUnit.Case, async: true

  alias Storyarn.Scenes.Condition
  alias Storyarn.Scenes.Expressions
  alias Storyarn.Scenes.Instruction
  alias Storyarn.Scenes.Logic, as: LegacyLogic

  test "keeps the legacy capability boundary as a compatibility delegate" do
    condition = %{"logic" => "all", "blocks" => []}

    assert Enum.sort(LegacyLogic.__info__(:functions)) ==
             Enum.sort(Expressions.__info__(:functions))

    assert LegacyLogic.sanitize_condition(condition) ==
             Expressions.sanitize_condition(condition)
  end

  test "preserves the stable condition and instruction contracts" do
    condition = %{"logic" => "all", "blocks" => []}
    assignments = [%{"id" => "incomplete"}]

    assert Expressions.sanitize_condition(condition) == Condition.sanitize(condition)
    assert Expressions.parse_condition(nil) == Condition.parse(nil)
    assert Expressions.sanitize_instructions(assignments) == Instruction.sanitize(assignments)
    assert Expressions.instruction_operator_label("add") == Instruction.operator_label("add")
  end

  test "exposes variable constraints without changing clamping semantics" do
    constraints = %{"min" => 2, "max" => 5}

    assert Expressions.clamp_variable(1, constraints, "number") == 2
    assert Expressions.clamp_variable(7, constraints, "number") == 5
    assert Expressions.clamp_variable(3, constraints, "number") == 3
  end
end
