defmodule Storyarn.Flows.NodeConnectionRulesTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.NodeConnectionRules

  describe "output_pins/2" do
    test "defines fixed executable outputs" do
      for type <- ~w(entry hub instruction) do
        assert NodeConnectionRules.output_pins(type, %{}) == ["output"]
      end

      for type <- ~w(exit jump annotation sequence) do
        assert NodeConnectionRules.output_pins(type, %{}) == []
      end
    end

    test "uses response ids for dialogue branches" do
      assert NodeConnectionRules.output_pins("dialogue", %{}) == ["output"]

      assert NodeConnectionRules.output_pins("dialogue", %{
               "responses" => [%{"id" => "accept"}, %{"id" => "decline"}]
             }) == ["accept", "decline"]
    end

    test "uses true and false for boolean conditions" do
      assert NodeConnectionRules.output_pins("condition", %{"switch_mode" => false}) ==
               ["true", "false"]
    end

    test "uses case ids and default for switch conditions" do
      assert NodeConnectionRules.output_pins("condition", %{
               "switch_mode" => true,
               "condition" => %{"blocks" => [%{"id" => "case-a"}, %{"id" => "case-b"}]}
             }) == ["case-a", "case-b", "default"]

      assert NodeConnectionRules.output_pins("condition", %{
               "switch_mode" => true,
               "condition" => %{"blocks" => []}
             }) == ["default"]
    end

    test "normalizes referenced-flow exits for subflows" do
      assert NodeConnectionRules.output_pins("subflow", %{}) == ["output"]

      assert NodeConnectionRules.output_pins("subflow", %{
               "exit_pins" => ["exit_10", %{id: 11}, %{"id" => "12"}]
             }) == ["exit_10", "exit_11", "exit_12"]
    end
  end

  describe "valid_input_pin?/2" do
    test "only executable nodes accept the input pin" do
      for type <- ~w(exit dialogue condition instruction hub jump subflow) do
        assert NodeConnectionRules.valid_input_pin?(type, "input")
        refute NodeConnectionRules.valid_input_pin?(type, "other")
      end

      for type <- ~w(entry annotation sequence) do
        refute NodeConnectionRules.valid_input_pin?(type, "input")
      end
    end
  end
end
