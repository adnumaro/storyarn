defmodule Storyarn.Sheets.TableColumnTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Sheets.TableColumn

  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  setup do
    project = project_fixture()
    sheet = sheet_fixture(project)
    block = table_block_fixture(sheet)
    %{block: block}
  end

  describe "types/0" do
    test "returns expected column types" do
      types = TableColumn.types()
      assert "number" in types
      assert "text" in types
      assert "boolean" in types
      assert "select" in types
      assert "multi_select" in types
      assert "date" in types
      assert "reference" in types
      refute "rich_text" in types
    end
  end

  describe "create_changeset/2" do
    test "valid attrs produce valid changeset", %{block: block} do
      changeset =
        %TableColumn{block_id: block.id}
        |> TableColumn.create_changeset(%{name: "Health", type: "number"})

      assert changeset.valid?
    end

    test "generates slug from name", %{block: block} do
      changeset =
        %TableColumn{block_id: block.id}
        |> TableColumn.create_changeset(%{name: "Hit Points", type: "number"})

      assert Ecto.Changeset.get_change(changeset, :slug) == "hit_points"
    end

    test "generates slug with unicode transliteration", %{block: block} do
      changeset =
        %TableColumn{block_id: block.id}
        |> TableColumn.create_changeset(%{name: "Héro Santé", type: "text"})

      slug = Ecto.Changeset.get_change(changeset, :slug)
      assert is_binary(slug)
      refute String.contains?(slug, "é")
    end

    test "requires name", %{block: block} do
      changeset =
        %TableColumn{block_id: block.id}
        |> TableColumn.create_changeset(%{type: "number"})

      assert "can't be blank" in errors_on(changeset).name
    end

    test "defaults type to number when not provided", %{block: block} do
      changeset =
        %TableColumn{block_id: block.id}
        |> TableColumn.create_changeset(%{name: "Test"})

      assert changeset.valid?
      # The default type from schema is "number"
      assert Ecto.Changeset.get_field(changeset, :type) == "number"
    end

    test "validates type inclusion", %{block: block} do
      changeset =
        %TableColumn{block_id: block.id}
        |> TableColumn.create_changeset(%{name: "Test", type: "rich_text"})

      assert "is invalid" in errors_on(changeset).type
    end

    test "accepts all valid types", %{block: block} do
      for type <- TableColumn.types() do
        changeset =
          %TableColumn{block_id: block.id}
          |> TableColumn.create_changeset(%{name: "Col #{type}", type: type})

        assert changeset.valid?, "type #{type} should be valid"
      end
    end

    test "accepts optional fields", %{block: block} do
      changeset =
        %TableColumn{block_id: block.id}
        |> TableColumn.create_changeset(%{
          name: "Status",
          type: "select",
          is_constant: true,
          required: true,
          position: 3,
          config: %{"options" => ["active", "inactive"]}
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :is_constant) == true
      assert Ecto.Changeset.get_change(changeset, :required) == true
      assert Ecto.Changeset.get_change(changeset, :position) == 3
    end
  end

  describe "update_changeset/2" do
    test "allows name update", %{block: block} do
      column = table_column_fixture(block, %{name: "Health", type: "number"})

      changeset = TableColumn.update_changeset(column, %{name: "Hit Points"})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :name) == "Hit Points"
    end

    test "allows type update", %{block: block} do
      column = table_column_fixture(block, %{name: "Value", type: "number"})

      changeset = TableColumn.update_changeset(column, %{type: "text"})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :type) == "text"
    end

    test "validates type on update", %{block: block} do
      column = table_column_fixture(block, %{name: "Value", type: "number"})

      changeset = TableColumn.update_changeset(column, %{type: "invalid"})
      assert "is invalid" in errors_on(changeset).type
    end

    test "does not allow position update", %{block: block} do
      column = table_column_fixture(block, %{name: "Value", type: "number", position: 0})

      changeset = TableColumn.update_changeset(column, %{position: 5})
      refute Ecto.Changeset.get_change(changeset, :position)
    end

    test "allows config update", %{block: block} do
      column = table_column_fixture(block, %{name: "Status", type: "select"})

      changeset =
        TableColumn.update_changeset(column, %{
          config: %{"options" => ["a", "b"]}
        })

      assert changeset.valid?
    end

    test "allows is_constant update", %{block: block} do
      column = table_column_fixture(block, %{name: "Label", type: "text"})

      changeset = TableColumn.update_changeset(column, %{is_constant: true})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :is_constant) == true
    end

    test "preserves existing slug if already set", %{block: block} do
      column = table_column_fixture(block, %{name: "Health", type: "number"})

      changeset = TableColumn.update_changeset(column, %{name: "Hit Points"})
      # slug should not regenerate because the existing column already has a slug
      refute Ecto.Changeset.get_change(changeset, :slug)
    end
  end

  describe "position_changeset/2" do
    test "updates position only", %{block: block} do
      column = table_column_fixture(block, %{name: "Value", type: "number", position: 0})

      changeset = TableColumn.position_changeset(column, %{position: 3})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :position) == 3
    end

    test "does not accept other fields", %{block: block} do
      column = table_column_fixture(block, %{name: "Value", type: "number"})

      changeset = TableColumn.position_changeset(column, %{name: "New Name", position: 2})
      refute Ecto.Changeset.get_change(changeset, :name)
      assert Ecto.Changeset.get_change(changeset, :position) == 2
    end
  end
end
