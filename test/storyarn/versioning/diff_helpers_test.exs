defmodule Storyarn.Versioning.DiffHelpersTest do
  use ExUnit.Case, async: true

  alias Storyarn.Versioning.DiffHelpers

  describe "check_field_change/6" do
    test "appends change when field differs" do
      old = %{"name" => "Old"}
      new = %{"name" => "New"}

      changes = DiffHelpers.check_field_change([], old, new, "name", :property, "Name changed")

      assert [%{category: :property, action: :modified, detail: "Name changed"}] = changes
    end

    test "passes through when field is the same" do
      old = %{"name" => "Same"}
      new = %{"name" => "Same"}

      changes = DiffHelpers.check_field_change([], old, new, "name", :property, "Name changed")

      assert changes == []
    end

    test "appends to existing changes" do
      existing = [%{category: :property, action: :modified, detail: "Prior change"}]
      old = %{"name" => "Old"}
      new = %{"name" => "New"}

      changes =
        DiffHelpers.check_field_change(existing, old, new, "name", :property, "Name changed")

      assert length(changes) == 2
    end
  end

  describe "match_by_keys/3" do
    test "matches items by primary key" do
      old = [%{"id" => 1, "val" => "a"}, %{"id" => 2, "val" => "b"}]
      new = [%{"id" => 2, "val" => "b2"}, %{"id" => 1, "val" => "a2"}]

      {matched, added, removed} = DiffHelpers.match_by_keys(old, new, [& &1["id"]])

      assert length(matched) == 2
      assert added == []
      assert removed == []
    end

    test "identifies added and removed items" do
      old = [%{"id" => 1, "val" => "a"}, %{"id" => 2, "val" => "b"}]
      new = [%{"id" => 2, "val" => "b"}, %{"id" => 3, "val" => "c"}]

      {matched, added, removed} = DiffHelpers.match_by_keys(old, new, [& &1["id"]])

      assert length(matched) == 1
      assert [%{"id" => 3}] = added
      assert [%{"id" => 1}] = removed
    end

    test "uses fallback key when primary returns nil" do
      old = [%{"name" => nil, "pos" => 0, "val" => "x"}]
      new = [%{"name" => nil, "pos" => 0, "val" => "y"}]

      key_fns = [
        fn item -> item["name"] end,
        fn item -> item["pos"] end
      ]

      {matched, added, removed} = DiffHelpers.match_by_keys(old, new, key_fns)

      assert length(matched) == 1
      assert added == []
      assert removed == []
    end

    test "consumes items matched in earlier rounds" do
      old = [%{"name" => "a", "pos" => 0}, %{"name" => nil, "pos" => 1}]
      new = [%{"name" => "a", "pos" => 0}, %{"name" => nil, "pos" => 1}]

      key_fns = [
        fn item -> item["name"] end,
        fn item -> item["pos"] end
      ]

      {matched, added, removed} = DiffHelpers.match_by_keys(old, new, key_fns)

      assert length(matched) == 2
      assert added == []
      assert removed == []
    end
  end

  describe "find_modified/2" do
    test "separates modified from unchanged pairs" do
      pairs = [
        {%{"val" => 1}, %{"val" => 1}},
        {%{"val" => 2}, %{"val" => 3}},
        {%{"val" => 4}, %{"val" => 4}}
      ]

      {modified, unchanged_count} =
        DiffHelpers.find_modified(pairs, fn old, new -> old["val"] != new["val"] end)

      assert length(modified) == 1
      assert unchanged_count == 2
    end

    test "returns empty modified and full count when all identical" do
      pairs = [{%{"v" => 1}, %{"v" => 1}}]

      {modified, unchanged_count} =
        DiffHelpers.find_modified(pairs, fn old, new -> old["v"] != new["v"] end)

      assert modified == []
      assert unchanged_count == 1
    end
  end

  describe "fields_differ?/3" do
    test "returns true when specified field differs" do
      old = %{"a" => 1, "b" => 2}
      new = %{"a" => 1, "b" => 3}

      assert DiffHelpers.fields_differ?(old, new, ["a", "b"])
    end

    test "returns false when all specified fields match" do
      old = %{"a" => 1, "b" => 2, "c" => 3}
      new = %{"a" => 1, "b" => 2, "c" => 99}

      refute DiffHelpers.fields_differ?(old, new, ["a", "b"])
    end
  end
end
