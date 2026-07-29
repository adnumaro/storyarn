defmodule Storyarn.GlobalSearch.ReferencePatternTest do
  use ExUnit.Case, async: true

  alias Storyarn.GlobalSearch.ReferencePattern

  test "parses the four deterministic pattern families" do
    assert {:ok, {:qualified, "mc.jaime.health"}} = ReferencePattern.parse("mc.jaime.health")
    assert {:ok, {:qualified, "2b.health"}} = ReferencePattern.parse("2b.health")
    assert {:ok, {:qualified, "23410.health"}} = ReferencePattern.parse("23410.health")
    assert {:ok, {:variable, "health"}} = ReferencePattern.parse("sheets.**.health")
    assert {:ok, {:variable_contains, "heal"}} = ReferencePattern.parse("sheets.**.?heal")
    assert {:ok, {:sheet, "mc.jaime"}} = ReferencePattern.parse("mc.jaime.?")
    assert {:ok, {:variable_contains, "heal"}} = ReferencePattern.parse("?heal")
  end

  test "rejects empty, overlong and malformed wildcards" do
    assert {:error, :invalid_request} = ReferencePattern.parse("")
    assert {:error, :invalid_request} = ReferencePattern.parse("?")
    assert {:error, :invalid_request} = ReferencePattern.parse("health")
    assert {:error, :invalid_request} = ReferencePattern.parse("mc.*.health")
    assert {:error, :invalid_request} = ReferencePattern.parse(" mc.health")
    assert {:error, :invalid_request} = ReferencePattern.parse("mc.health ")
    assert {:error, :invalid_request} = ReferencePattern.parse("mc..health")
    assert {:error, :invalid_request} = ReferencePattern.parse(~s(mc."health"))
    assert {:error, :invalid_request} = ReferencePattern.parse("?heal.more")
    assert {:error, :invalid_request} = ReferencePattern.parse("sheets.**.?heal.more")
    assert {:error, :invalid_request} = ReferencePattern.parse(String.duplicate("a", 101))
  end
end
