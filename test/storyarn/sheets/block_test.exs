defmodule Storyarn.Sheets.BlockTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.Block

  # =============================================================================
  # types/0 and scopes/0
  # =============================================================================

  describe "types/0" do
    test "returns all block types" do
      types = Block.types()
      assert is_list(types)
      assert "text" in types
      assert "rich_text" in types
      assert "number" in types
      assert "select" in types
      assert "multi_select" in types
      assert "divider" in types
      assert "date" in types
      assert "boolean" in types
      assert "reference" in types
      assert "table" in types
    end
  end

  describe "scopes/0" do
    test "returns self and children" do
      assert Block.scopes() == ~w(self children)
    end
  end

  # =============================================================================
  # default_config/1
  # =============================================================================

  describe "default_config/1" do
    test "returns config for text type" do
      config = Block.default_config("text")
      assert config["label"] == "Label"
      assert Map.has_key?(config, "placeholder")
    end

    test "returns config for number type" do
      config = Block.default_config("number")
      assert config["label"] == "Label"
      assert Map.has_key?(config, "min")
      assert Map.has_key?(config, "max")
    end

    test "returns config for select type" do
      config = Block.default_config("select")
      assert config["options"] == []
    end

    test "returns config for multi_select type" do
      config = Block.default_config("multi_select")
      assert config["options"] == []
    end

    test "returns empty map for divider" do
      assert Block.default_config("divider") == %{}
    end

    test "returns config for boolean type" do
      config = Block.default_config("boolean")
      assert config["mode"] == "two_state"
    end

    test "returns config for reference type" do
      config = Block.default_config("reference")
      assert config["allowed_types"] == ["sheet", "flow"]
    end

    test "returns config for table type" do
      config = Block.default_config("table")
      assert config["collapsed"] == false
    end

    test "returns empty map for unknown type" do
      assert Block.default_config("unknown") == %{}
    end
  end

  # =============================================================================
  # default_value/1
  # =============================================================================

  describe "default_value/1" do
    test "returns default value for each type" do
      for type <- ~w(text rich_text) do
        assert Block.default_value(type) == %{"content" => ""},
               "Expected default value for #{type}"
      end

      assert Block.default_value("number") == %{"content" => nil}
      assert Block.default_value("select") == %{"content" => nil}
      assert Block.default_value("multi_select") == %{"content" => []}
      assert Block.default_value("divider") == %{}
      assert Block.default_value("boolean") == %{"content" => nil}
      assert Block.default_value("date") == %{"content" => nil}
      assert Block.default_value("reference") == %{"target_type" => nil, "target_id" => nil}
      assert Block.default_value("table") == %{}
    end

    test "returns empty map for unknown type" do
      assert Block.default_value("unknown") == %{}
    end
  end

  # =============================================================================
  # can_be_variable?/1
  # =============================================================================

  describe "can_be_variable?/1" do
    test "returns true for variable-capable types" do
      for type <- ~w(text rich_text number select multi_select boolean date table) do
        assert Block.can_be_variable?(type), "Expected #{type} to be variable-capable"
      end
    end

    test "returns false for non-variable types" do
      refute Block.can_be_variable?("divider")
      refute Block.can_be_variable?("reference")
    end
  end

  # =============================================================================
  # variable?/1
  # =============================================================================

  describe "variable?/1" do
    test "returns true for non-constant variable-capable block" do
      block = %Block{type: "text", is_constant: false}
      assert Block.variable?(block)
    end

    test "returns false for constant block" do
      block = %Block{type: "text", is_constant: true}
      refute Block.variable?(block)
    end

    test "returns false for divider" do
      block = %Block{type: "divider", is_constant: false}
      refute Block.variable?(block)
    end

    test "returns false for reference" do
      block = %Block{type: "reference", is_constant: false}
      refute Block.variable?(block)
    end
  end

  # =============================================================================
  # inherited?/1
  # =============================================================================

  describe "inherited?/1" do
    test "returns false when no inherited_from_block_id" do
      block = %Block{inherited_from_block_id: nil}
      refute Block.inherited?(block)
    end

    test "returns false when detached" do
      block = %Block{inherited_from_block_id: 1, detached: true}
      refute Block.inherited?(block)
    end

    test "returns true when inherited and not detached" do
      block = %Block{inherited_from_block_id: 1, detached: false}
      assert Block.inherited?(block)
    end
  end

  # =============================================================================
  # deleted?/1
  # =============================================================================

  describe "deleted?/1" do
    test "returns true when deleted_at is set" do
      block = %Block{deleted_at: DateTime.utc_now()}
      assert Block.deleted?(block)
    end

    test "returns false when deleted_at is nil" do
      block = %Block{deleted_at: nil}
      refute Block.deleted?(block)
    end
  end

  # =============================================================================
  # create_changeset/2
  # =============================================================================

  describe "create_changeset/2" do
    test "valid with minimal attrs" do
      cs =
        Block.create_changeset(%Block{}, %{
          type: "text",
          config: %{"label" => "Name"}
        })

      assert cs.valid?
    end

    test "invalid without type" do
      cs = Block.create_changeset(%Block{}, %{config: %{"label" => "Name"}})
      refute cs.valid?
      assert errors_on(cs)[:type]
    end

    test "invalid with unknown type" do
      cs =
        Block.create_changeset(%Block{}, %{
          type: "unknown",
          config: %{"label" => "Name"}
        })

      refute cs.valid?
      assert errors_on(cs)[:type]
    end

    test "divider does not require label" do
      cs = Block.create_changeset(%Block{}, %{type: "divider"})
      assert cs.valid?
    end

    test "non-divider requires label in config" do
      cs = Block.create_changeset(%Block{}, %{type: "text", config: %{}})
      refute cs.valid?
      assert errors_on(cs)[:config]
    end

    test "validates scope inclusion" do
      cs =
        Block.create_changeset(%Block{}, %{
          type: "text",
          config: %{"label" => "Name"},
          scope: "invalid"
        })

      refute cs.valid?
      assert errors_on(cs)[:scope]
    end

    test "validates column_index range 0..2" do
      cs =
        Block.create_changeset(%Block{}, %{
          type: "text",
          config: %{"label" => "Name"},
          column_index: 3
        })

      refute cs.valid?
      assert errors_on(cs)[:column_index]
    end

    test "auto-generates variable_name from label for variable types" do
      cs =
        Block.create_changeset(%Block{}, %{
          type: "text",
          config: %{"label" => "Health Points"}
        })

      assert Ecto.Changeset.get_change(cs, :variable_name) == "health_points"
    end

    test "sets variable_name to nil for non-variable types" do
      cs =
        Block.create_changeset(%Block{}, %{
          type: "divider"
        })

      assert Ecto.Changeset.get_change(cs, :variable_name) == nil
    end

    test "does not overwrite existing variable_name" do
      cs =
        Block.create_changeset(%Block{}, %{
          type: "text",
          config: %{"label" => "Health Points"},
          variable_name: "custom_var"
        })

      assert Ecto.Changeset.get_field(cs, :variable_name) == "custom_var"
    end
  end

  # =============================================================================
  # select options validation
  # =============================================================================

  describe "select options validation" do
    test "select with list options is valid" do
      cs =
        Block.create_changeset(%Block{}, %{
          type: "select",
          config: %{
            "label" => "Color",
            "options" => [%{"key" => "red", "value" => "Red"}]
          }
        })

      assert cs.valid?
    end

    test "select with non-list options is invalid" do
      cs =
        Block.create_changeset(%Block{}, %{
          type: "select",
          config: %{
            "label" => "Color",
            "options" => "not a list"
          }
        })

      refute cs.valid?
      assert errors_on(cs)[:config]
    end

    test "multi_select with non-list options is invalid" do
      cs =
        Block.create_changeset(%Block{}, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => "not a list"
          }
        })

      refute cs.valid?
      assert errors_on(cs)[:config]
    end
  end

  # =============================================================================
  # value_changeset/2
  # =============================================================================

  describe "value_changeset/2" do
    test "updates value" do
      cs = Block.value_changeset(%Block{type: "text"}, %{value: %{"content" => "hello"}})
      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :value) == %{"content" => "hello"}
    end
  end

  # =============================================================================
  # config_changeset/2
  # =============================================================================

  describe "config_changeset/2" do
    test "updates config" do
      cs =
        Block.config_changeset(%Block{type: "text"}, %{
          config: %{"label" => "New Label"}
        })

      assert cs.valid?
    end
  end

  # =============================================================================
  # variable_changeset/2
  # =============================================================================

  describe "variable_changeset/2" do
    test "updates is_constant and variable_name" do
      cs =
        Block.variable_changeset(%Block{type: "text"}, %{
          is_constant: true,
          variable_name: "custom_var"
        })

      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :is_constant) == true
      assert Ecto.Changeset.get_change(cs, :variable_name) == "custom_var"
    end
  end

  # =============================================================================
  # position_changeset/2
  # =============================================================================

  describe "position_changeset/2" do
    test "updates position" do
      cs = Block.position_changeset(%Block{type: "text"}, %{position: 5})
      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :position) == 5
    end
  end

  # =============================================================================
  # delete_changeset/1 and restore_changeset/1
  # =============================================================================

  describe "delete_changeset/1" do
    test "sets deleted_at" do
      cs = Block.delete_changeset(%Block{type: "text"})
      assert Ecto.Changeset.get_change(cs, :deleted_at) != nil
    end
  end

  describe "restore_changeset/1" do
    test "sets deleted_at to nil" do
      cs = Block.restore_changeset(%Block{type: "text", deleted_at: DateTime.utc_now()})
      assert Ecto.Changeset.get_change(cs, :deleted_at) == nil
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
