defmodule Storyarn.GlobalSearch.VariableQueryTest do
  use ExUnit.Case, async: true

  alias Storyarn.GlobalSearch.VariableQuery

  describe "parse/1 autocomplete queries" do
    test "parses a plain reference fragment" do
      assert {:ok,
              %VariableQuery{
                reference: "health",
                operator: nil,
                literal: nil
              }} = VariableQuery.parse("health")
    end

    test "trims a plain reference and accepts qualified reference characters" do
      assert {:ok, %VariableQuery{reference: "mc.jaime.health_points"}} =
               VariableQuery.parse("  mc.jaime.health_points  ")

      assert {:ok, %VariableQuery{reference: "chapter-1.score"}} =
               VariableQuery.parse("chapter-1.score")
    end

    test "accepts a reference whose first character is a digit or underscore" do
      assert {:ok, %VariableQuery{reference: "2b.health"}} =
               VariableQuery.parse("2b.health")

      assert {:ok, %VariableQuery{reference: "_internal"}} =
               VariableQuery.parse("_internal")
    end
  end

  describe "parse/1 predicates" do
    test "recognizes every supported operator without whitespace" do
      operators = [
        {"+=", :add},
        {"-=", :subtract},
        {">=", :greater_than_or_equal},
        {"<=", :less_than_or_equal},
        {"!=", :not_equal},
        {"!~", :not_contains},
        {"=", :equal},
        {"~", :contains},
        {">", :greater_than},
        {"<", :less_than}
      ]

      for {symbol, operator} <- operators do
        assert {:ok,
                %VariableQuery{
                  reference: "health",
                  operator: ^operator,
                  literal: "11"
                }} = VariableQuery.parse("health#{symbol}11")
      end
    end

    test "matches multi-character operators before their one-character prefixes" do
      assert {:ok, %VariableQuery{operator: :greater_than_or_equal, literal: "10"}} =
               VariableQuery.parse("health >= 10")

      assert {:ok, %VariableQuery{operator: :less_than_or_equal, literal: "10"}} =
               VariableQuery.parse("health <= 10")

      assert {:ok, %VariableQuery{operator: :add, literal: "10"}} =
               VariableQuery.parse("health += 10")

      assert {:ok, %VariableQuery{operator: :subtract, literal: "10"}} =
               VariableQuery.parse("health -= 10")

      assert {:ok, %VariableQuery{operator: :not_equal, literal: "10"}} =
               VariableQuery.parse("health != 10")

      assert {:ok, %VariableQuery{operator: :not_contains, literal: "crit"}} =
               VariableQuery.parse("status !~ crit")
    end

    test "contains predicates preserve the search fragment and ignore surrounding whitespace" do
      assert {:ok,
              %VariableQuery{
                reference: "faction",
                operator: :contains,
                literal: "ClAv"
              }} = VariableQuery.parse("  faction   ~   ClAv  ")

      assert {:ok,
              %VariableQuery{
                reference: "hero.biography",
                operator: :not_contains,
                literal: ~s("old conclave")
              }} = VariableQuery.parse(~s( hero.biography !~ "old conclave" ))
    end

    test "trims the reference and literal while preserving literal contents" do
      assert {:ok,
              %VariableQuery{
                reference: "hero.health",
                operator: :equal,
                literal: ~s("critical condition")
              }} = VariableQuery.parse(~s(  hero.health   =   "critical condition"  ))
    end

    test "accepts signed numbers and operator characters after literal content" do
      assert {:ok, %VariableQuery{operator: :equal, literal: "-5"}} =
               VariableQuery.parse("health = -5")

      assert {:ok, %VariableQuery{operator: :equal, literal: "+5"}} =
               VariableQuery.parse("health = +5")

      assert {:ok, %VariableQuery{operator: :equal, literal: ~s("a > b")}} =
               VariableQuery.parse(~s(text = "a > b"))
    end
  end

  describe "parse/1 validation" do
    test "accepts the bounded wire length and rejects longer input" do
      reference = String.duplicate("a", 399)

      assert {:ok, %VariableQuery{reference: ^reference}} =
               VariableQuery.parse(reference)

      assert {:error, :too_long} =
               VariableQuery.parse(reference <> "a")
    end

    test "applies the length cap before trimming" do
      assert {:error, :too_long} =
               VariableQuery.parse(" " <> String.duplicate("a", 398) <> " ")
    end

    test "rejects empty and non-binary queries" do
      assert {:error, :empty} = VariableQuery.parse("")
      assert {:error, :empty} = VariableQuery.parse("   ")
      assert {:error, :invalid_predicate} = VariableQuery.parse(nil)
      assert {:error, :invalid_predicate} = VariableQuery.parse(42)
    end

    test "rejects empty contains fragments" do
      assert {:error, :invalid_predicate} = VariableQuery.parse(~s(faction ~ ""))
      assert {:error, :invalid_predicate} = VariableQuery.parse(~s(faction !~ "   "))
    end

    test "rejects invalid reference fragments" do
      for query <- [
            ".health",
            "-health",
            "health points",
            "health + 1",
            "health ! 1",
            "health/score"
          ] do
        assert {:error, :invalid_reference} = VariableQuery.parse(query)
      end
    end

    test "rejects predicates without a reference or literal" do
      for query <- ["= 11", " >= 11", "health =", "health >=   "] do
        assert {:error, reason} = VariableQuery.parse(query)
        assert reason in [:invalid_reference, :invalid_predicate]
      end
    end

    test "rejects doubled, reversed, and chained operator prefixes" do
      for query <- [
            "health == 11",
            "health => 11",
            "health >< 11",
            "health << 11",
            "health !== 11",
            "health >= <= 11"
          ] do
        assert {:error, :invalid_predicate} = VariableQuery.parse(query)
      end
    end
  end
end
