defmodule Storyarn.Shared.ValidationsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Shared.Validations

  # We need a simple schema to test changeset validations
  defmodule TestSchema do
    @moduledoc false
    use Ecto.Schema

    import Ecto.Changeset

    embedded_schema do
      field :shortcut, :string
      field :email, :string
    end

    def changeset(schema, attrs) do
      cast(schema, attrs, [:shortcut, :email])
    end
  end

  defp changeset_with_shortcut(shortcut) do
    TestSchema.changeset(%TestSchema{}, %{shortcut: shortcut})
  end

  defp changeset_with_email(email) do
    TestSchema.changeset(%TestSchema{}, %{email: email})
  end

  # ===========================================================================
  # shortcut_format/0
  # ===========================================================================

  describe "shortcut_format/0" do
    test "returns a regex" do
      assert %Regex{} = Validations.shortcut_format()
    end
  end

  # ===========================================================================
  # email_format/0
  # ===========================================================================

  describe "email_format/0" do
    test "returns a regex" do
      assert %Regex{} = Validations.email_format()
    end
  end

  # ===========================================================================
  # validate_shortcut/1-2
  # ===========================================================================

  describe "validate_shortcut/1" do
    test "accepts single lowercase character" do
      changeset = "a" |> changeset_with_shortcut() |> Validations.validate_shortcut()
      assert changeset.valid?
    end

    test "accepts single digit" do
      changeset = "5" |> changeset_with_shortcut() |> Validations.validate_shortcut()
      assert changeset.valid?
    end

    test "accepts lowercase alphanumeric" do
      changeset = "abc123" |> changeset_with_shortcut() |> Validations.validate_shortcut()
      assert changeset.valid?
    end

    test "accepts shortcuts with dots" do
      changeset = "mc.jaime" |> changeset_with_shortcut() |> Validations.validate_shortcut()
      assert changeset.valid?
    end

    test "accepts shortcuts with hyphens" do
      changeset = "my-entity" |> changeset_with_shortcut() |> Validations.validate_shortcut()
      assert changeset.valid?
    end

    test "accepts shortcuts with dots and hyphens" do
      changeset = "mc.jaime-2" |> changeset_with_shortcut() |> Validations.validate_shortcut()
      assert changeset.valid?
    end

    test "rejects uppercase characters" do
      changeset = "MyEntity" |> changeset_with_shortcut() |> Validations.validate_shortcut()
      refute changeset.valid?
    end

    test "rejects shortcuts starting with dot" do
      changeset = ".entity" |> changeset_with_shortcut() |> Validations.validate_shortcut()
      refute changeset.valid?
    end

    test "rejects shortcuts starting with hyphen" do
      changeset = "-entity" |> changeset_with_shortcut() |> Validations.validate_shortcut()
      refute changeset.valid?
    end

    test "rejects shortcuts ending with dot" do
      changeset = "entity." |> changeset_with_shortcut() |> Validations.validate_shortcut()
      refute changeset.valid?
    end

    test "rejects shortcuts ending with hyphen" do
      changeset = "entity-" |> changeset_with_shortcut() |> Validations.validate_shortcut()
      refute changeset.valid?
    end

    test "rejects shortcuts with spaces" do
      changeset = "my entity" |> changeset_with_shortcut() |> Validations.validate_shortcut()
      refute changeset.valid?
    end

    test "rejects shortcuts with special characters" do
      changeset = "my!entity" |> changeset_with_shortcut() |> Validations.validate_shortcut()
      refute changeset.valid?
    end

    test "rejects nil shortcut when field is required" do
      # validate_shortcut only applies format/length when value is present.
      # To reject empty/nil, the schema must also use validate_required.
      changeset =
        %TestSchema{}
        |> TestSchema.changeset(%{shortcut: nil})
        |> Ecto.Changeset.validate_required([:shortcut])
        |> Validations.validate_shortcut()

      refute changeset.valid?
    end

    test "rejects shortcut longer than 50 characters" do
      long_shortcut = String.duplicate("a", 51)
      changeset = long_shortcut |> changeset_with_shortcut() |> Validations.validate_shortcut()
      refute changeset.valid?
    end

    test "accepts shortcut of exactly 50 characters" do
      shortcut = String.duplicate("a", 50)
      changeset = shortcut |> changeset_with_shortcut() |> Validations.validate_shortcut()
      assert changeset.valid?
    end
  end

  describe "validate_shortcut/2 with custom message" do
    test "uses custom error message" do
      changeset =
        "INVALID"
        |> changeset_with_shortcut()
        |> Validations.validate_shortcut(message: "custom error")

      refute changeset.valid?
      {message, _} = changeset.errors[:shortcut]
      assert message == "custom error"
    end

    test "uses default message when no custom message provided" do
      changeset = "INVALID" |> changeset_with_shortcut() |> Validations.validate_shortcut()
      refute changeset.valid?
      {message, _} = changeset.errors[:shortcut]
      assert message == "must be lowercase, alphanumeric, with dots or hyphens"
    end
  end

  # ===========================================================================
  # validate_email_format/1
  # ===========================================================================

  describe "validate_email_format/1" do
    test "accepts valid email" do
      changeset = "user@example.com" |> changeset_with_email() |> Validations.validate_email_format()
      assert changeset.valid?
    end

    test "accepts email with subdomain" do
      changeset =
        "user@sub.example.com" |> changeset_with_email() |> Validations.validate_email_format()

      assert changeset.valid?
    end

    test "accepts email with plus addressing" do
      changeset =
        "user+tag@example.com" |> changeset_with_email() |> Validations.validate_email_format()

      assert changeset.valid?
    end

    test "rejects email without @ sign" do
      changeset =
        "userexample.com" |> changeset_with_email() |> Validations.validate_email_format()

      refute changeset.valid?
    end

    test "rejects email with spaces" do
      changeset =
        "user @example.com" |> changeset_with_email() |> Validations.validate_email_format()

      refute changeset.valid?
    end

    test "rejects email with comma" do
      changeset =
        "user,name@example.com" |> changeset_with_email() |> Validations.validate_email_format()

      refute changeset.valid?
    end

    test "rejects email with semicolon" do
      changeset =
        "user;name@example.com" |> changeset_with_email() |> Validations.validate_email_format()

      refute changeset.valid?
    end

    test "rejects email with multiple @ signs" do
      changeset =
        "user@@example.com" |> changeset_with_email() |> Validations.validate_email_format()

      refute changeset.valid?
    end

    test "provides correct error message" do
      changeset = "invalid" |> changeset_with_email() |> Validations.validate_email_format()
      refute changeset.valid?
      {message, _} = changeset.errors[:email]
      assert message == "must have the @ sign and no spaces"
    end
  end
end
