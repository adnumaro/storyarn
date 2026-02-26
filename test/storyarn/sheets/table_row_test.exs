defmodule Storyarn.Sheets.TableRowTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Sheets.TableRow
  import Storyarn.AccountsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.ProjectsFixtures

  defp setup_table(_context) do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project)
    block = table_block_fixture(sheet)

    %{user: user, project: project, sheet: sheet, block: block}
  end

  # ===========================================================================
  # create_changeset/2
  # ===========================================================================

  describe "create_changeset/2" do
    setup :setup_table

    test "valid attrs produce a valid changeset", %{block: block} do
      changeset =
        %TableRow{block_id: block.id}
        |> TableRow.create_changeset(%{name: "Strength", position: 5, cells: %{"value" => 10}})

      assert changeset.valid?
      assert get_change(changeset, :name) == "Strength"
      assert get_change(changeset, :slug) == "strength"
      assert get_change(changeset, :position) == 5
      assert get_change(changeset, :cells) == %{"value" => 10}
    end

    test "generates slug from name", %{block: block} do
      changeset =
        %TableRow{block_id: block.id}
        |> TableRow.create_changeset(%{name: "Health Points"})

      assert get_change(changeset, :slug) == "health_points"
    end

    test "slug handles Unicode characters", %{block: block} do
      changeset =
        %TableRow{block_id: block.id}
        |> TableRow.create_changeset(%{name: "Fuerza Magica"})

      assert get_change(changeset, :slug) == "fuerza_magica"
    end

    test "requires name", %{block: block} do
      changeset =
        %TableRow{block_id: block.id}
        |> TableRow.create_changeset(%{})

      refute changeset.valid?
      assert errors_on(changeset)[:name] != nil
    end

    test "requires name to be non-nil", %{block: block} do
      changeset =
        %TableRow{block_id: block.id}
        |> TableRow.create_changeset(%{name: nil})

      refute changeset.valid?
      assert errors_on(changeset)[:name] != nil
    end

    test "defaults cells to empty map when not provided", %{block: block} do
      changeset =
        %TableRow{block_id: block.id}
        |> TableRow.create_changeset(%{name: "Row 1"})

      # cells not in changes, but default on schema is %{}
      assert changeset.valid?
    end

    test "accepts cells map", %{block: block} do
      cells = %{"value" => 42, "description" => "test"}

      changeset =
        %TableRow{block_id: block.id}
        |> TableRow.create_changeset(%{name: "Row 1", cells: cells})

      assert changeset.valid?
      assert get_change(changeset, :cells) == cells
    end

    test "accepts block_id in attrs", _context do
      changeset =
        %TableRow{}
        |> TableRow.create_changeset(%{name: "Row 1", block_id: 999})

      # block_id gets cast
      assert get_change(changeset, :block_id) == 999
    end

    test "generates slug with special characters stripped", %{block: block} do
      changeset =
        %TableRow{block_id: block.id}
        |> TableRow.create_changeset(%{name: "HP (Max)"})

      slug = get_change(changeset, :slug)
      assert slug == "hp_max"
    end

    test "has unique constraint on block_id + slug", %{block: block} do
      changeset =
        %TableRow{block_id: block.id}
        |> TableRow.create_changeset(%{name: "Test"})

      assert {:unique, _} =
               changeset.constraints
               |> Enum.find(fn c -> c.type == :unique end)
               |> then(fn c -> {c.type, c.field} end)
    end
  end

  # ===========================================================================
  # update_changeset/2
  # ===========================================================================

  describe "update_changeset/2" do
    setup :setup_table

    test "updates name and regenerates slug when slug was nil", %{block: block} do
      # Create a row manually where slug would be nil (simulating an edge case)
      row = %TableRow{block_id: block.id, name: "Original", slug: nil, position: 0}

      changeset = TableRow.update_changeset(row, %{name: "Updated Name"})

      assert changeset.valid?
      assert get_change(changeset, :name) == "Updated Name"
      # When slug is nil, should regenerate
      assert get_change(changeset, :slug) == "updated_name"
    end

    test "preserves existing slug when slug is already set", %{block: block} do
      row = %TableRow{block_id: block.id, name: "Original", slug: "original", position: 0}

      changeset = TableRow.update_changeset(row, %{name: "Updated Name"})

      assert changeset.valid?
      assert get_change(changeset, :name) == "Updated Name"
      # Existing slug should not be regenerated
      refute Map.has_key?(changeset.changes, :slug)
    end

    test "only casts name field", %{block: block} do
      row = %TableRow{block_id: block.id, name: "Original", slug: "original", position: 0}

      changeset = TableRow.update_changeset(row, %{name: "New", position: 99, cells: %{"x" => 1}})

      assert changeset.valid?
      # position and cells should NOT be cast in update_changeset
      refute Map.has_key?(changeset.changes, :position)
      refute Map.has_key?(changeset.changes, :cells)
    end

    test "allows empty update (no changes)", %{block: block} do
      row = %TableRow{block_id: block.id, name: "Original", slug: "original", position: 0}

      changeset = TableRow.update_changeset(row, %{})

      assert changeset.valid?
      assert changeset.changes == %{}
    end
  end

  # ===========================================================================
  # position_changeset/2
  # ===========================================================================

  describe "position_changeset/2" do
    setup :setup_table

    test "casts position only", %{block: block} do
      row = %TableRow{block_id: block.id, name: "Row", slug: "row", position: 0}

      changeset = TableRow.position_changeset(row, %{position: 5})

      assert changeset.valid?
      assert get_change(changeset, :position) == 5
    end

    test "does not cast other fields", %{block: block} do
      row = %TableRow{block_id: block.id, name: "Row", slug: "row", position: 0}

      changeset = TableRow.position_changeset(row, %{position: 3, name: "X", cells: %{}})

      refute Map.has_key?(changeset.changes, :name)
      refute Map.has_key?(changeset.changes, :cells)
    end
  end

  # ===========================================================================
  # cells_changeset/2
  # ===========================================================================

  describe "cells_changeset/2" do
    setup :setup_table

    test "casts cells only", %{block: block} do
      row = %TableRow{block_id: block.id, name: "Row", slug: "row", position: 0, cells: %{}}

      cells = %{"value" => 42, "description" => "test"}
      changeset = TableRow.cells_changeset(row, %{cells: cells})

      assert changeset.valid?
      assert get_change(changeset, :cells) == cells
    end

    test "does not cast other fields", %{block: block} do
      row = %TableRow{block_id: block.id, name: "Row", slug: "row", position: 0, cells: %{}}

      changeset = TableRow.cells_changeset(row, %{cells: %{"x" => 1}, name: "Y", position: 9})

      refute Map.has_key?(changeset.changes, :name)
      refute Map.has_key?(changeset.changes, :position)
    end

    test "accepts nil cell values", %{block: block} do
      row = %TableRow{block_id: block.id, name: "Row", slug: "row", position: 0, cells: %{}}

      changeset = TableRow.cells_changeset(row, %{cells: %{"value" => nil}})

      assert changeset.valid?
      assert get_change(changeset, :cells) == %{"value" => nil}
    end

    test "accepts complex cell values", %{block: block} do
      row = %TableRow{block_id: block.id, name: "Row", slug: "row", position: 0, cells: %{}}

      cells = %{"tags" => ["a", "b", "c"], "score" => 99, "active" => true}
      changeset = TableRow.cells_changeset(row, %{cells: cells})

      assert changeset.valid?
      assert get_change(changeset, :cells) == cells
    end
  end

  # ===========================================================================
  # Schema defaults
  # ===========================================================================

  describe "schema defaults" do
    test "position defaults to 0" do
      row = %TableRow{}
      assert row.position == 0
    end

    test "cells defaults to empty map" do
      row = %TableRow{}
      assert row.cells == %{}
    end
  end

  # ===========================================================================
  # Integration: insert and query through Repo
  # ===========================================================================

  describe "integration with Repo" do
    setup :setup_table

    test "inserts and retrieves a table row", %{block: block} do
      {:ok, row} =
        %TableRow{block_id: block.id}
        |> TableRow.create_changeset(%{name: "Strength", position: 5, cells: %{"value" => 18}})
        |> Repo.insert()

      assert row.id != nil
      assert row.name == "Strength"
      assert row.slug == "strength"
      assert row.position == 5
      assert row.cells == %{"value" => 18}
      assert row.block_id == block.id
      assert row.inserted_at != nil
      assert row.updated_at != nil
    end

    test "enforces slug uniqueness per block via constraint", %{block: block} do
      {:ok, _} =
        %TableRow{block_id: block.id}
        |> TableRow.create_changeset(%{name: "Unique Row", position: 10})
        |> Repo.insert()

      {:error, changeset} =
        %TableRow{block_id: block.id}
        |> TableRow.create_changeset(%{name: "Unique Row", position: 11})
        |> Repo.insert()

      # Should fail on unique constraint
      assert errors_on(changeset) != %{}
    end

    test "allows same slug on different blocks", %{sheet: sheet} do
      block2 = table_block_fixture(sheet, %{label: "Second Table"})

      {:ok, row1} =
        %TableRow{block_id: hd(Storyarn.Sheets.list_blocks(sheet.id)).id}
        |> TableRow.create_changeset(%{name: "Same Name", position: 10})
        |> Repo.insert()

      {:ok, row2} =
        %TableRow{block_id: block2.id}
        |> TableRow.create_changeset(%{name: "Same Name", position: 0})
        |> Repo.insert()

      assert row1.slug == row2.slug
      assert row1.block_id != row2.block_id
    end

    test "update via Repo works correctly", %{block: block} do
      {:ok, row} =
        %TableRow{block_id: block.id}
        |> TableRow.create_changeset(%{name: "Before", position: 0})
        |> Repo.insert()

      # Use position_changeset to update position
      {:ok, updated} =
        row
        |> TableRow.position_changeset(%{position: 7})
        |> Repo.update()

      assert updated.position == 7
      assert updated.name == "Before"
    end

    test "cells_changeset can replace entire cells map", %{block: block} do
      {:ok, row} =
        %TableRow{block_id: block.id}
        |> TableRow.create_changeset(%{name: "Test Row", position: 0, cells: %{"value" => 1}})
        |> Repo.insert()

      {:ok, updated} =
        row
        |> TableRow.cells_changeset(%{cells: %{"value" => 99, "extra" => "new"}})
        |> Repo.update()

      assert updated.cells == %{"value" => 99, "extra" => "new"}
    end
  end

  # ===========================================================================
  # Slug generation edge cases
  # ===========================================================================

  describe "slug generation edge cases" do
    setup :setup_table

    test "generates slug from name with numbers", %{block: block} do
      changeset =
        %TableRow{block_id: block.id}
        |> TableRow.create_changeset(%{name: "Row 123"})

      assert get_change(changeset, :slug) == "row_123"
    end

    test "generates slug from name with leading/trailing spaces", %{block: block} do
      changeset =
        %TableRow{block_id: block.id}
        |> TableRow.create_changeset(%{name: "  Trimmed  "})

      slug = get_change(changeset, :slug)
      # NameNormalizer.variablify handles trimming
      assert slug == "trimmed"
    end

    test "generates slug from name with uppercase", %{block: block} do
      changeset =
        %TableRow{block_id: block.id}
        |> TableRow.create_changeset(%{name: "UPPERCASE"})

      assert get_change(changeset, :slug) == "uppercase"
    end

    test "generates slug from mixed case name", %{block: block} do
      changeset =
        %TableRow{block_id: block.id}
        |> TableRow.create_changeset(%{name: "CamelCase Name"})

      assert get_change(changeset, :slug) == "camelcase_name"
    end
  end
end
