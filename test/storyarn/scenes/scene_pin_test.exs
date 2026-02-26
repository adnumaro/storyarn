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
  # Action type & action_data validation
  # =============================================================================

  describe "action_type validation" do
    test "valid action types" do
      for type <- ~w(none instruction display) do
        action_data =
          case type do
            "instruction" -> %{"assignments" => []}
            "display" -> %{"variable_ref" => "mc.jaime.health"}
            _ -> %{}
          end

        cs =
          ScenePin.create_changeset(%ScenePin{}, %{
            position_x: 50.0,
            position_y: 50.0,
            action_type: type,
            action_data: action_data
          })

        assert cs.valid?, "Expected action_type '#{type}' to be valid"
      end
    end

    test "instruction requires assignments list in action_data" do
      cs =
        ScenePin.create_changeset(%ScenePin{}, %{
          position_x: 50.0,
          position_y: 50.0,
          action_type: "instruction",
          action_data: %{"wrong_key" => "value"}
        })

      refute cs.valid?
      assert errors_on(cs)[:action_data]
    end

    test "instruction with valid assignments list" do
      cs =
        ScenePin.create_changeset(%ScenePin{}, %{
          position_x: 50.0,
          position_y: 50.0,
          action_type: "instruction",
          action_data: %{"assignments" => [%{"id" => "a1", "operator" => "set"}]}
        })

      assert cs.valid?
    end

    test "display requires variable_ref string in action_data" do
      cs =
        ScenePin.create_changeset(%ScenePin{}, %{
          position_x: 50.0,
          position_y: 50.0,
          action_type: "display",
          action_data: %{"wrong_key" => "value"}
        })

      refute cs.valid?
      assert errors_on(cs)[:action_data]
    end

    test "display with valid variable_ref" do
      cs =
        ScenePin.create_changeset(%ScenePin{}, %{
          position_x: 50.0,
          position_y: 50.0,
          action_type: "display",
          action_data: %{"variable_ref" => "mc.jaime.health"}
        })

      assert cs.valid?
    end

    test "none action_type allows any action_data" do
      cs =
        ScenePin.create_changeset(%ScenePin{}, %{
          position_x: 50.0,
          position_y: 50.0,
          action_type: "none",
          action_data: %{"random" => "data"}
        })

      assert cs.valid?
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
  # Target pair validation
  # =============================================================================

  describe "target_pair validation" do
    test "valid with both target_type and target_id" do
      cs =
        ScenePin.create_changeset(%ScenePin{}, %{
          position_x: 50.0,
          position_y: 50.0,
          target_type: "sheet",
          target_id: 1
        })

      assert cs.valid?
    end

    test "invalid with target_id but no target_type" do
      cs =
        ScenePin.create_changeset(%ScenePin{}, %{
          position_x: 50.0,
          position_y: 50.0,
          target_id: 1
        })

      refute cs.valid?
      assert errors_on(cs)[:target_type]
    end

    test "invalid with target_type but no target_id" do
      cs =
        ScenePin.create_changeset(%ScenePin{}, %{
          position_x: 50.0,
          position_y: 50.0,
          target_type: "flow"
        })

      refute cs.valid?
      assert errors_on(cs)[:target_id]
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
