defmodule Storyarn.Exports.ExpressionTranspiler.InstructionTest do
  use ExUnit.Case, async: true

  alias Storyarn.Exports.ExpressionTranspiler

  # =============================================================================
  # Test Data
  # =============================================================================

  defp assignment(operator, value \\ "10", opts \\ []) do
    %{
      "id" => "assign_1",
      "sheet" => Keyword.get(opts, :sheet, "mc.jaime"),
      "variable" => Keyword.get(opts, :variable, "health"),
      "operator" => operator,
      "value" => value,
      "value_type" => Keyword.get(opts, :value_type, "literal"),
      "value_sheet" => Keyword.get(opts, :value_sheet)
    }
  end

  defp var_ref_assignment do
    %{
      "id" => "assign_1",
      "sheet" => "mc.jaime",
      "variable" => "health",
      "operator" => "set",
      "value" => "max_health",
      "value_type" => "variable_ref",
      "value_sheet" => "stats.base"
    }
  end

  # =============================================================================
  # Set operator (all engines) — exact assertions
  # =============================================================================

  describe "set operator" do
    @set_expected %{
      ink: "~ mc_jaime_health = 10",
      yarn: "<<set $mc_jaime_health to 10>>",
      unity: ~s(Variable["mc.jaime.health"] = 10),
      godot: "mc_jaime_health = 10",
      unreal: "mc.jaime.health = 10",
      articy: "mc.jaime.health = 10"
    }

    for {engine, expected} <- @set_expected do
      test "#{engine} emits exact expression" do
        {:ok, result, _} =
          ExpressionTranspiler.transpile_instruction([assignment("set")], unquote(engine))

        assert result == unquote(expected)
      end
    end
  end

  # =============================================================================
  # Arithmetic operators — all engines
  # =============================================================================

  describe "add operator" do
    @add_expected %{
      ink: "~ mc_jaime_health += 10",
      yarn: "<<set $mc_jaime_health to $mc_jaime_health + 10>>",
      unity: ~s(Variable["mc.jaime.health"] = Variable["mc.jaime.health"] + 10),
      godot: "mc_jaime_health += 10",
      unreal: "mc.jaime.health += 10",
      articy: "mc.jaime.health += 10"
    }

    for {engine, expected} <- @add_expected do
      test "#{engine} emits exact expression" do
        {:ok, result, _} =
          ExpressionTranspiler.transpile_instruction([assignment("add")], unquote(engine))

        assert result == unquote(expected)
      end
    end
  end

  describe "subtract operator" do
    @subtract_expected %{
      ink: "~ mc_jaime_health -= 10",
      yarn: "<<set $mc_jaime_health to $mc_jaime_health - 10>>",
      unity: ~s(Variable["mc.jaime.health"] = Variable["mc.jaime.health"] - 10),
      godot: "mc_jaime_health -= 10",
      unreal: "mc.jaime.health -= 10",
      articy: "mc.jaime.health -= 10"
    }

    for {engine, expected} <- @subtract_expected do
      test "#{engine} emits exact expression" do
        {:ok, result, _} =
          ExpressionTranspiler.transpile_instruction([assignment("subtract")], unquote(engine))

        assert result == unquote(expected)
      end
    end
  end

  # =============================================================================
  # Boolean operators — all engines
  # =============================================================================

  describe "set_true operator" do
    @set_true_expected %{
      ink: "~ mc_jaime_health = true",
      yarn: "<<set $mc_jaime_health to true>>",
      unity: ~s(Variable["mc.jaime.health"] = true),
      godot: "mc_jaime_health = true",
      unreal: "mc.jaime.health = true",
      articy: "mc.jaime.health = true"
    }

    for {engine, expected} <- @set_true_expected do
      test "#{engine} emits exact expression" do
        {:ok, result, _} =
          ExpressionTranspiler.transpile_instruction(
            [assignment("set_true", nil)],
            unquote(engine)
          )

        assert result == unquote(expected)
      end
    end
  end

  describe "set_false operator" do
    @set_false_expected %{
      ink: "~ mc_jaime_health = false",
      yarn: "<<set $mc_jaime_health to false>>",
      unity: ~s(Variable["mc.jaime.health"] = false),
      godot: "mc_jaime_health = false",
      unreal: "mc.jaime.health = false",
      articy: "mc.jaime.health = false"
    }

    for {engine, expected} <- @set_false_expected do
      test "#{engine} emits exact expression" do
        {:ok, result, _} =
          ExpressionTranspiler.transpile_instruction(
            [assignment("set_false", nil)],
            unquote(engine)
          )

        assert result == unquote(expected)
      end
    end
  end

  describe "toggle operator" do
    @toggle_expected %{
      ink: "~ mc_jaime_health = not mc_jaime_health",
      yarn: "<<set $mc_jaime_health to !$mc_jaime_health>>",
      unity: ~s(Variable["mc.jaime.health"] = not Variable["mc.jaime.health"]),
      godot: "mc_jaime_health = !mc_jaime_health",
      unreal: "mc.jaime.health = !mc.jaime.health",
      articy: "mc.jaime.health = !mc.jaime.health"
    }

    for {engine, expected} <- @toggle_expected do
      test "#{engine} emits exact expression" do
        {:ok, result, _} =
          ExpressionTranspiler.transpile_instruction(
            [assignment("toggle", nil)],
            unquote(engine)
          )

        assert result == unquote(expected)
      end
    end
  end

  # =============================================================================
  # Clear operator — all engines
  # =============================================================================

  describe "clear operator" do
    @clear_expected %{
      ink: ~s(~ mc_jaime_health = ""),
      yarn: ~s(<<set $mc_jaime_health to "">>),
      unity: ~s(Variable["mc.jaime.health"] = ""),
      godot: ~s(mc_jaime_health = ""),
      unreal: ~s(mc.jaime.health = ""),
      articy: ~s(mc.jaime.health = "")
    }

    for {engine, expected} <- @clear_expected do
      test "#{engine} emits exact expression" do
        {:ok, result, _} =
          ExpressionTranspiler.transpile_instruction(
            [assignment("clear", nil)],
            unquote(engine)
          )

        assert result == unquote(expected)
      end
    end
  end

  # =============================================================================
  # set_if_unset operator — all engines
  # =============================================================================

  describe "set_if_unset operator" do
    test "ink emits unconditional assignment" do
      {:ok, result, _} =
        ExpressionTranspiler.transpile_instruction([assignment("set_if_unset")], :ink)

      assert result == "~ mc_jaime_health = 10"
    end

    test "yarn emits unconditional set" do
      {:ok, result, _} =
        ExpressionTranspiler.transpile_instruction([assignment("set_if_unset")], :yarn)

      assert result == "<<set $mc_jaime_health to 10>>"
    end

    test "unity emits Lua if/then/end" do
      {:ok, result, _} =
        ExpressionTranspiler.transpile_instruction([assignment("set_if_unset")], :unity)

      assert result ==
               ~s(if Variable["mc.jaime.health"] == nil then Variable["mc.jaime.health"] = 10 end)
    end

    test "godot emits if null block" do
      {:ok, result, _} =
        ExpressionTranspiler.transpile_instruction([assignment("set_if_unset")], :godot)

      assert result == "if mc_jaime_health == null: mc_jaime_health = 10"
    end

    test "unreal emits if None block" do
      {:ok, result, _} =
        ExpressionTranspiler.transpile_instruction([assignment("set_if_unset")], :unreal)

      assert result == "if mc.jaime.health == None: mc.jaime.health = 10"
    end

    test "articy emits if (null) block" do
      {:ok, result, _} =
        ExpressionTranspiler.transpile_instruction([assignment("set_if_unset")], :articy)

      assert result == "if (mc.jaime.health == null) mc.jaime.health = 10"
    end
  end

  # =============================================================================
  # Variable-to-variable assignments — all engines
  # =============================================================================

  describe "variable-to-variable assignment" do
    @var_ref_expected %{
      ink: "~ mc_jaime_health = stats_base_max_health",
      yarn: "<<set $mc_jaime_health to $stats_base_max_health>>",
      unity: ~s(Variable["mc.jaime.health"] = Variable["stats.base.max_health"]),
      godot: "mc_jaime_health = stats_base_max_health",
      unreal: "mc.jaime.health = stats.base.max_health",
      articy: "mc.jaime.health = stats.base.max_health"
    }

    for {engine, expected} <- @var_ref_expected do
      test "#{engine} references both variables correctly" do
        {:ok, result, _} =
          ExpressionTranspiler.transpile_instruction([var_ref_assignment()], unquote(engine))

        assert result == unquote(expected)
      end
    end
  end

  # =============================================================================
  # Multiple assignments
  # =============================================================================

  describe "multiple assignments" do
    test "joins with newlines" do
      assignments = [
        assignment("set", "100"),
        assignment("set_true", nil, variable: "alive")
      ]

      {:ok, result, _} = ExpressionTranspiler.transpile_instruction(assignments, :ink)
      lines = String.split(result, "\n")
      assert length(lines) == 2
      assert Enum.at(lines, 0) == "~ mc_jaime_health = 100"
      assert Enum.at(lines, 1) == "~ mc_jaime_alive = true"
    end
  end

  # =============================================================================
  # Edge cases
  # =============================================================================

  describe "edge cases" do
    test "empty assignments returns empty string" do
      for engine <- [:ink, :yarn, :unity, :godot, :unreal, :articy] do
        {:ok, result, _} = ExpressionTranspiler.transpile_instruction([], engine)
        assert result == ""
      end
    end

    test "nil assignments returns empty string" do
      for engine <- [:ink, :yarn, :unity, :godot, :unreal, :articy] do
        {:ok, result, _} = ExpressionTranspiler.transpile_instruction(nil, engine)
        assert result == ""
      end
    end

    test "incomplete assignment (missing sheet) is skipped" do
      a = %{assignment("set") | "sheet" => nil}
      {:ok, result, _} = ExpressionTranspiler.transpile_instruction([a], :ink)
      assert result == ""
    end

    test "incomplete assignment (empty variable) is skipped" do
      a = %{assignment("set") | "variable" => ""}
      {:ok, result, _} = ExpressionTranspiler.transpile_instruction([a], :ink)
      assert result == ""
    end

    test "unknown engine returns error" do
      result = ExpressionTranspiler.transpile_instruction([assignment("set")], :unknown)
      assert {:error, {:unknown_engine, :unknown}} = result
    end

    test "string value gets quoted" do
      a = assignment("set", "warrior", variable: "class")
      {:ok, result, _} = ExpressionTranspiler.transpile_instruction([a], :godot)
      assert result == ~s(mc_jaime_class = "warrior")
    end

    test "assignment with no value key defaults to 0" do
      a = %{"sheet" => "mc.jaime", "variable" => "health", "operator" => "set"}
      {:ok, result, _} = ExpressionTranspiler.transpile_instruction([a], :godot)
      assert result == "mc_jaime_health = 0"
    end
  end
end
