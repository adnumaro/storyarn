defmodule Storyarn.Scenes.ChangesetHelpersTest do
  use ExUnit.Case, async: true

  import Ecto.Changeset
  alias Storyarn.Scenes.ChangesetHelpers

  # A minimal schema module for testing changeset helpers
  defmodule TestSchema do
    use Ecto.Schema

    embedded_schema do
      field :target_type, :string
      field :target_id, :integer
      field :color, :string
    end
  end

  defp changeset(attrs) do
    %TestSchema{}
    |> cast(attrs, [:target_type, :target_id, :color])
  end

  # =============================================================================
  # validate_target_pair/2
  # =============================================================================

  describe "validate_target_pair/2" do
    @valid_types ~w(sheet flow scene url)

    test "valid when both target_type and target_id are nil" do
      cs = changeset(%{}) |> ChangesetHelpers.validate_target_pair(@valid_types)
      assert cs.valid?
    end

    test "valid when both target_type and target_id are set with valid type" do
      cs =
        changeset(%{target_type: "sheet", target_id: 1})
        |> ChangesetHelpers.validate_target_pair(@valid_types)

      assert cs.valid?
    end

    test "invalid when target_id is set but target_type is nil" do
      cs =
        changeset(%{target_id: 1})
        |> ChangesetHelpers.validate_target_pair(@valid_types)

      refute cs.valid?
      assert errors_on(cs)[:target_type] == ["is required when target_id is set"]
    end

    test "invalid when target_type is set but target_id is nil" do
      cs =
        changeset(%{target_type: "sheet"})
        |> ChangesetHelpers.validate_target_pair(@valid_types)

      refute cs.valid?
      assert errors_on(cs)[:target_id] == ["is required when target_type is set"]
    end

    test "invalid when target_type is not in valid types" do
      cs =
        changeset(%{target_type: "invalid", target_id: 1})
        |> ChangesetHelpers.validate_target_pair(@valid_types)

      refute cs.valid?
      assert errors_on(cs)[:target_type] != nil
    end

    test "all valid types pass validation" do
      for type <- @valid_types do
        cs =
          changeset(%{target_type: type, target_id: 1})
          |> ChangesetHelpers.validate_target_pair(@valid_types)

        assert cs.valid?, "Expected #{type} to be valid"
      end
    end
  end

  # =============================================================================
  # validate_color/2
  # =============================================================================

  describe "validate_color/2" do
    test "valid 3-char hex color" do
      cs = changeset(%{color: "#FFF"}) |> ChangesetHelpers.validate_color(:color)
      assert cs.valid?
    end

    test "valid 6-char hex color" do
      cs = changeset(%{color: "#FF00AA"}) |> ChangesetHelpers.validate_color(:color)
      assert cs.valid?
    end

    test "valid 8-char hex color with alpha" do
      cs = changeset(%{color: "#FF00AA80"}) |> ChangesetHelpers.validate_color(:color)
      assert cs.valid?
    end

    test "valid lowercase hex color" do
      cs = changeset(%{color: "#aabbcc"}) |> ChangesetHelpers.validate_color(:color)
      assert cs.valid?
    end

    test "invalid - missing hash prefix" do
      cs = changeset(%{color: "FF0000"}) |> ChangesetHelpers.validate_color(:color)
      refute cs.valid?
    end

    test "invalid - wrong length (2 chars)" do
      cs = changeset(%{color: "#FF"}) |> ChangesetHelpers.validate_color(:color)
      refute cs.valid?
    end

    test "invalid - wrong length (4 chars)" do
      cs = changeset(%{color: "#FFFF"}) |> ChangesetHelpers.validate_color(:color)
      refute cs.valid?
    end

    test "invalid - non-hex characters" do
      cs = changeset(%{color: "#GGHHII"}) |> ChangesetHelpers.validate_color(:color)
      refute cs.valid?
    end

    test "valid when color is nil (not set)" do
      cs = changeset(%{}) |> ChangesetHelpers.validate_color(:color)
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
