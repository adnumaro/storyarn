defmodule Storyarn.Flows.ExpressionsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Expressions
  alias Storyarn.Flows.Logic, as: LegacyLogic

  test "keeps the legacy function contract while SQL predicates stay consumer-local" do
    assert Enum.sort(LegacyLogic.__info__(:functions)) ==
             Enum.sort(Expressions.__info__(:functions))

    assert {:authoritative_variable_namespace_owner?, 1} in LegacyLogic.__info__(:macros)
    refute {:authoritative_variable_namespace_owner?, 1} in Expressions.__info__(:macros)
  end
end
