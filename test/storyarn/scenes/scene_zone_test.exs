defmodule Storyarn.Scenes.SceneZoneTest do
  use ExUnit.Case, async: true

  import Ecto.Changeset, only: [get_change: 2]
  alias Storyarn.Scenes.SceneZone

  defp valid_attrs do
    %{
      name: "Test Zone",
      vertices: [
        %{"x" => 10.0, "y" => 10.0},
        %{"x" => 90.0, "y" => 10.0},
        %{"x" => 50.0, "y" => 90.0}
      ]
    }
  end

  # =============================================================================
  # Shortcut validation
  # =============================================================================

  describe "shortcut validation" do
    test "valid shortcut" do
      cs = SceneZone.create_changeset(%SceneZone{}, Map.put(valid_attrs(), :shortcut, "market"))
      assert cs.valid?
    end

    test "invalid shortcut format" do
      cs =
        SceneZone.create_changeset(%SceneZone{}, Map.put(valid_attrs(), :shortcut, "INVALID!"))

      refute cs.valid?
      assert errors_on(cs)[:shortcut]
    end

    test "nil shortcut is valid" do
      cs = SceneZone.create_changeset(%SceneZone{}, Map.put(valid_attrs(), :shortcut, nil))
      assert cs.valid?
    end
  end

  # =============================================================================
  # Hidden field
  # =============================================================================

  describe "hidden field" do
    test "defaults to false" do
      cs = SceneZone.create_changeset(%SceneZone{}, valid_attrs())
      assert cs.valid?
      refute get_change(cs, :hidden)
    end

    test "can be set to true" do
      cs = SceneZone.create_changeset(%SceneZone{}, Map.put(valid_attrs(), :hidden, true))
      assert cs.valid?
      assert get_change(cs, :hidden) == true
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
