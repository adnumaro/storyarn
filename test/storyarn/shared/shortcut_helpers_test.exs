defmodule Storyarn.Shared.ShortcutHelpersTest do
  use ExUnit.Case, async: true

  alias Storyarn.Shared.ShortcutHelpers

  # ===========================================================================
  # Helper to create fake entity structs
  # ===========================================================================

  defp entity(attrs \\ %{}) do
    defaults = %{
      id: 1,
      name: "Test Entity",
      shortcut: "test-entity",
      project_id: 42
    }

    Map.merge(defaults, attrs)
  end

  defp generator_fn(name, _project_id, _exclude_id) do
    name |> String.downcase() |> String.replace(" ", "-")
  end

  # ===========================================================================
  # maybe_generate_shortcut/4
  # ===========================================================================

  describe "maybe_generate_shortcut/4" do
    test "generates shortcut from name when no shortcut provided" do
      attrs = %{"name" => "My Flow"}

      result = ShortcutHelpers.maybe_generate_shortcut(attrs, 1, nil, &generator_fn/3)

      assert result["shortcut"] == "my-flow"
    end

    test "does not overwrite existing shortcut" do
      attrs = %{"name" => "My Flow", "shortcut" => "custom-shortcut"}

      result = ShortcutHelpers.maybe_generate_shortcut(attrs, 1, nil, &generator_fn/3)

      assert result["shortcut"] == "custom-shortcut"
    end

    test "does not generate shortcut when name is nil" do
      attrs = %{"name" => nil}

      result = ShortcutHelpers.maybe_generate_shortcut(attrs, 1, nil, &generator_fn/3)

      refute Map.has_key?(result, "shortcut")
    end

    test "does not generate shortcut when name is empty" do
      attrs = %{"name" => ""}

      result = ShortcutHelpers.maybe_generate_shortcut(attrs, 1, nil, &generator_fn/3)

      refute Map.has_key?(result, "shortcut")
    end

    test "does not generate shortcut when no name in attrs" do
      attrs = %{"description" => "something"}

      result = ShortcutHelpers.maybe_generate_shortcut(attrs, 1, nil, &generator_fn/3)

      refute Map.has_key?(result, "shortcut")
    end

    test "passes project_id and exclude_id to generator function" do
      captured = :ets.new(:captured, [:set, :public])

      custom_gen = fn name, project_id, exclude_id ->
        :ets.insert(captured, {:args, name, project_id, exclude_id})
        "generated"
      end

      attrs = %{"name" => "Test"}
      ShortcutHelpers.maybe_generate_shortcut(attrs, 99, 5, custom_gen)

      [{:args, name, pid, eid}] = :ets.lookup(captured, :args)
      assert name == "Test"
      assert pid == 99
      assert eid == 5

      :ets.delete(captured)
    end
  end

  # ===========================================================================
  # name_changing?/2
  # ===========================================================================

  describe "name_changing?/2" do
    test "returns true when name is different" do
      assert ShortcutHelpers.name_changing?(%{"name" => "New Name"}, entity())
    end

    test "returns false when name is the same" do
      refute ShortcutHelpers.name_changing?(%{"name" => "Test Entity"}, entity())
    end

    test "returns false when name is nil" do
      refute ShortcutHelpers.name_changing?(%{"name" => nil}, entity())
    end

    test "returns false when name is empty string" do
      refute ShortcutHelpers.name_changing?(%{"name" => ""}, entity())
    end

    test "returns false when no name in attrs" do
      refute ShortcutHelpers.name_changing?(%{"description" => "test"}, entity())
    end
  end

  # ===========================================================================
  # missing_shortcut?/1
  # ===========================================================================

  describe "missing_shortcut?/1" do
    test "returns true when shortcut is nil" do
      assert ShortcutHelpers.missing_shortcut?(entity(%{shortcut: nil}))
    end

    test "returns true when shortcut is empty string" do
      assert ShortcutHelpers.missing_shortcut?(entity(%{shortcut: ""}))
    end

    test "returns false when shortcut exists" do
      refute ShortcutHelpers.missing_shortcut?(entity(%{shortcut: "my-shortcut"}))
    end
  end

  # ===========================================================================
  # generate_shortcut_from_name/3
  # ===========================================================================

  describe "generate_shortcut_from_name/3" do
    test "generates shortcut from entity name" do
      e = entity(%{name: "My Entity", project_id: 1, id: 5})

      result = ShortcutHelpers.generate_shortcut_from_name(e, %{}, &generator_fn/3)

      assert result["shortcut"] == "my-entity"
    end

    test "does nothing when entity name is nil" do
      e = entity(%{name: nil})
      attrs = %{"something" => "else"}

      result = ShortcutHelpers.generate_shortcut_from_name(e, attrs, &generator_fn/3)

      assert result == attrs
    end

    test "does nothing when entity name is empty" do
      e = entity(%{name: ""})
      attrs = %{"something" => "else"}

      result = ShortcutHelpers.generate_shortcut_from_name(e, attrs, &generator_fn/3)

      assert result == attrs
    end
  end

  # ===========================================================================
  # maybe_assign_position/4
  # ===========================================================================

  describe "maybe_assign_position/4" do
    test "assigns position when not present" do
      attrs = %{"name" => "test"}
      position_fn = fn _project_id, _parent_id -> 5 end

      result = ShortcutHelpers.maybe_assign_position(attrs, 1, nil, position_fn)

      assert result["position"] == 5
    end

    test "does not overwrite existing position" do
      attrs = %{"name" => "test", "position" => 3}
      position_fn = fn _project_id, _parent_id -> 5 end

      result = ShortcutHelpers.maybe_assign_position(attrs, 1, nil, position_fn)

      assert result["position"] == 3
    end

    test "passes project_id and parent_id to position function" do
      captured = :ets.new(:captured, [:set, :public])

      position_fn = fn project_id, parent_id ->
        :ets.insert(captured, {:args, project_id, parent_id})
        0
      end

      ShortcutHelpers.maybe_assign_position(%{}, 42, 7, position_fn)

      [{:args, pid, parent}] = :ets.lookup(captured, :args)
      assert pid == 42
      assert parent == 7

      :ets.delete(captured)
    end
  end

  # ===========================================================================
  # maybe_generate_shortcut_on_update/4
  # ===========================================================================

  describe "maybe_generate_shortcut_on_update/4" do
    test "returns attrs unchanged when shortcut is explicitly provided" do
      e = entity()
      attrs = %{"shortcut" => "custom", "name" => "New Name"}

      result = ShortcutHelpers.maybe_generate_shortcut_on_update(e, attrs, &generator_fn/3)

      assert result["shortcut"] == "custom"
    end

    test "regenerates shortcut when name changes" do
      e = entity(%{name: "Old Name", shortcut: "old-name"})
      attrs = %{"name" => "New Name"}

      result = ShortcutHelpers.maybe_generate_shortcut_on_update(e, attrs, &generator_fn/3)

      assert result["shortcut"] == "new-name"
    end

    test "generates shortcut from entity name when shortcut is missing" do
      e = entity(%{name: "My Entity", shortcut: nil})
      attrs = %{"description" => "updated"}

      result = ShortcutHelpers.maybe_generate_shortcut_on_update(e, attrs, &generator_fn/3)

      assert result["shortcut"] == "my-entity"
    end

    test "returns attrs unchanged when name not changing and shortcut exists" do
      e = entity(%{name: "Same Name", shortcut: "same-name"})
      attrs = %{"description" => "updated"}

      result = ShortcutHelpers.maybe_generate_shortcut_on_update(e, attrs, &generator_fn/3)

      # Should not add a shortcut key
      refute Map.has_key?(result, "shortcut")
    end

    test "handles atom keys by stringifying them" do
      e = entity(%{name: "Old Name", shortcut: "old-name"})
      attrs = %{name: "New Name"}

      result = ShortcutHelpers.maybe_generate_shortcut_on_update(e, attrs, &generator_fn/3)

      assert result["shortcut"] == "new-name"
    end

    test "with check_backlinks_fn preserves shortcut when referenced" do
      e = entity(%{name: "Old Name", shortcut: "old-name"})
      attrs = %{"name" => "New Name"}
      check_fn = fn _entity -> true end

      result =
        ShortcutHelpers.maybe_generate_shortcut_on_update(e, attrs, &generator_fn/3,
          check_backlinks_fn: check_fn
        )

      # When referenced, the shortcut should be preserved
      assert result["shortcut"] == "old-name"
    end

    test "with check_backlinks_fn regenerates when not referenced" do
      e = entity(%{name: "Old Name", shortcut: "old-name"})
      attrs = %{"name" => "New Name"}
      check_fn = fn _entity -> false end

      result =
        ShortcutHelpers.maybe_generate_shortcut_on_update(e, attrs, &generator_fn/3,
          check_backlinks_fn: check_fn
        )

      assert result["shortcut"] == "new-name"
    end
  end
end
