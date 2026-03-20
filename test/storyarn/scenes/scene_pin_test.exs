defmodule Storyarn.Scenes.ScenePinTest do
  use ExUnit.Case, async: true

  import Ecto.Changeset, only: [get_change: 2]
  alias Storyarn.Scenes.ScenePin

  defp valid_attrs do
    %{
      position_x: 50.0,
      position_y: 50.0,
      pin_type: "location",
      size: "md",
      label: "Test Pin"
    }
  end

  # =============================================================================
  # create_changeset/2
  # =============================================================================

  describe "create_changeset/2" do
    test "valid with minimal required attrs" do
      cs = ScenePin.create_changeset(%ScenePin{}, %{position_x: 10.0, position_y: 20.0})
      assert cs.valid?
    end

    test "valid with all attrs" do
      cs = ScenePin.create_changeset(%ScenePin{}, valid_attrs())
      assert cs.valid?
    end

    test "invalid without position_x" do
      cs = ScenePin.create_changeset(%ScenePin{}, %{position_y: 50.0})
      refute cs.valid?
      assert errors_on(cs)[:position_x]
    end

    test "invalid without position_y" do
      cs = ScenePin.create_changeset(%ScenePin{}, %{position_x: 50.0})
      refute cs.valid?
      assert errors_on(cs)[:position_y]
    end

    test "invalid with position_x out of range (negative)" do
      cs = ScenePin.create_changeset(%ScenePin{}, %{position_x: -1.0, position_y: 50.0})
      refute cs.valid?
      assert errors_on(cs)[:position_x]
    end

    test "invalid with position_x out of range (over 100)" do
      cs = ScenePin.create_changeset(%ScenePin{}, %{position_x: 101.0, position_y: 50.0})
      refute cs.valid?
      assert errors_on(cs)[:position_x]
    end

    test "invalid with position_y out of range" do
      cs = ScenePin.create_changeset(%ScenePin{}, %{position_x: 50.0, position_y: -1.0})
      refute cs.valid?
      assert errors_on(cs)[:position_y]
    end

    test "boundary values are valid (0 and 100)" do
      cs = ScenePin.create_changeset(%ScenePin{}, %{position_x: 0.0, position_y: 100.0})
      assert cs.valid?
    end
  end

  # =============================================================================
  # Pin types
  # =============================================================================

  describe "pin_type validation" do
    test "valid pin types" do
      for type <- ~w(location character event custom) do
        cs =
          ScenePin.create_changeset(%ScenePin{}, %{
            position_x: 50.0,
            position_y: 50.0,
            pin_type: type
          })

        assert cs.valid?, "Expected pin_type '#{type}' to be valid"
      end
    end

    test "invalid pin type" do
      cs =
        ScenePin.create_changeset(%ScenePin{}, %{
          position_x: 50.0,
          position_y: 50.0,
          pin_type: "invalid"
        })

      refute cs.valid?
      assert errors_on(cs)[:pin_type]
    end
  end

  # =============================================================================
  # Size validation
  # =============================================================================

  describe "size validation" do
    test "valid sizes" do
      for size <- ~w(sm md lg) do
        cs =
          ScenePin.create_changeset(%ScenePin{}, %{
            position_x: 50.0,
            position_y: 50.0,
            size: size
          })

        assert cs.valid?, "Expected size '#{size}' to be valid"
      end
    end

    test "invalid size" do
      cs =
        ScenePin.create_changeset(%ScenePin{}, %{
          position_x: 50.0,
          position_y: 50.0,
          size: "xl"
        })

      refute cs.valid?
      assert errors_on(cs)[:size]
    end
  end

  # =============================================================================
  # Opacity validation
  # =============================================================================

  describe "opacity validation" do
    test "valid opacity values" do
      for opacity <- [0.0, 0.5, 1.0] do
        cs =
          ScenePin.create_changeset(%ScenePin{}, %{
            position_x: 50.0,
            position_y: 50.0,
            opacity: opacity
          })

        assert cs.valid?, "Expected opacity #{opacity} to be valid"
      end
    end

    test "invalid opacity - too high" do
      cs =
        ScenePin.create_changeset(%ScenePin{}, %{
          position_x: 50.0,
          position_y: 50.0,
          opacity: 1.5
        })

      refute cs.valid?
      assert errors_on(cs)[:opacity]
    end

    test "invalid opacity - negative" do
      cs =
        ScenePin.create_changeset(%ScenePin{}, %{
          position_x: 50.0,
          position_y: 50.0,
          opacity: -0.1
        })

      refute cs.valid?
      assert errors_on(cs)[:opacity]
    end
  end

  # =============================================================================
  # Condition effect validation
  # =============================================================================

  describe "condition_effect validation" do
    test "valid condition effects" do
      for effect <- ~w(hide disable) do
        cs =
          ScenePin.create_changeset(%ScenePin{}, %{
            position_x: 50.0,
            position_y: 50.0,
            condition_effect: effect
          })

        assert cs.valid?, "Expected condition_effect '#{effect}' to be valid"
      end
    end

    test "invalid condition effect" do
      cs =
        ScenePin.create_changeset(%ScenePin{}, %{
          position_x: 50.0,
          position_y: 50.0,
          condition_effect: "remove"
        })

      refute cs.valid?
      assert errors_on(cs)[:condition_effect]
    end
  end

  # =============================================================================
  # Shortcut validation
  # =============================================================================

  describe "shortcut validation" do
    test "valid shortcut" do
      cs =
        ScenePin.create_changeset(%ScenePin{}, %{
          position_x: 50.0,
          position_y: 50.0,
          shortcut: "guard-west"
        })

      assert cs.valid?
    end

    test "invalid shortcut format" do
      cs =
        ScenePin.create_changeset(%ScenePin{}, %{
          position_x: 50.0,
          position_y: 50.0,
          shortcut: "INVALID!"
        })

      refute cs.valid?
      assert errors_on(cs)[:shortcut]
    end

    test "nil shortcut is valid" do
      cs =
        ScenePin.create_changeset(%ScenePin{}, %{
          position_x: 50.0,
          position_y: 50.0,
          shortcut: nil
        })

      assert cs.valid?
    end
  end

  # =============================================================================
  # Hidden field
  # =============================================================================

  describe "hidden field" do
    test "defaults to false" do
      cs = ScenePin.create_changeset(%ScenePin{}, %{position_x: 50.0, position_y: 50.0})
      assert cs.valid?
      # hidden is not in changes (uses schema default)
      refute get_change(cs, :hidden)
    end

    test "can be set to true" do
      cs =
        ScenePin.create_changeset(%ScenePin{}, %{
          position_x: 50.0,
          position_y: 50.0,
          hidden: true
        })

      assert cs.valid?
      assert get_change(cs, :hidden) == true
    end
  end

  # =============================================================================
  # flow_id field
  # =============================================================================

  describe "flow_id field" do
    test "can set flow_id" do
      cs =
        ScenePin.create_changeset(%ScenePin{}, %{
          position_x: 50.0,
          position_y: 50.0,
          flow_id: 42
        })

      assert cs.valid?
      assert get_change(cs, :flow_id) == 42
    end

    test "nil flow_id is valid" do
      cs =
        ScenePin.create_changeset(%ScenePin{}, %{
          position_x: 50.0,
          position_y: 50.0,
          flow_id: nil
        })

      assert cs.valid?
    end
  end

  # =============================================================================
  # Length validations
  # =============================================================================

  describe "length validations" do
    test "label max length 200" do
      cs =
        ScenePin.create_changeset(%ScenePin{}, %{
          position_x: 50.0,
          position_y: 50.0,
          label: String.duplicate("a", 201)
        })

      refute cs.valid?
      assert errors_on(cs)[:label]
    end

    test "tooltip max length 500" do
      cs =
        ScenePin.create_changeset(%ScenePin{}, %{
          position_x: 50.0,
          position_y: 50.0,
          tooltip: String.duplicate("a", 501)
        })

      refute cs.valid?
      assert errors_on(cs)[:tooltip]
    end
  end

  # =============================================================================
  # move_changeset/2
  # =============================================================================

  describe "move_changeset/2" do
    test "valid with position within range" do
      cs = ScenePin.move_changeset(%ScenePin{}, %{position_x: 75.0, position_y: 25.0})
      assert cs.valid?
    end

    test "requires position_x" do
      cs = ScenePin.move_changeset(%ScenePin{}, %{position_y: 25.0})
      refute cs.valid?
      assert errors_on(cs)[:position_x]
    end

    test "requires position_y" do
      cs = ScenePin.move_changeset(%ScenePin{}, %{position_x: 75.0})
      refute cs.valid?
      assert errors_on(cs)[:position_y]
    end

    test "validates position range" do
      cs = ScenePin.move_changeset(%ScenePin{}, %{position_x: 150.0, position_y: 50.0})
      refute cs.valid?
      assert errors_on(cs)[:position_x]
    end
  end

  # =============================================================================
  # update_changeset/2
  # =============================================================================

  describe "update_changeset/2" do
    test "allows updating label" do
      cs =
        ScenePin.update_changeset(%ScenePin{position_x: 50.0, position_y: 50.0}, %{
          label: "New Label"
        })

      assert cs.valid?
      assert get_change(cs, :label) == "New Label"
    end

    test "allows updating color" do
      cs =
        ScenePin.update_changeset(%ScenePin{position_x: 50.0, position_y: 50.0}, %{
          color: "#FF0000"
        })

      assert cs.valid?
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
