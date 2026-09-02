defmodule Storyarn.Projects.SheetRecordTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Projects.Persistence.SheetRecord
  alias Storyarn.Projects.SheetImportPersistence

  describe "create_changeset/2" do
    test "accepts the locally pinned valid create corpus" do
      valid_cases = [
        {"minimum name", %{name: "A"}},
        {"maximum name", %{name: String.duplicate("a", 200)}},
        {"single-character shortcut", %{name: "Hero", shortcut: "h"}},
        {"compound shortcut", %{name: "Hero", shortcut: "mc.jaime-2"}},
        {"maximum shortcut", %{name: "Hero", shortcut: String.duplicate("a", 50)}},
        {"three-digit color", %{name: "Hero", color: "#fff"}},
        {"six-digit color", %{name: "Hero", color: "#3B82F6"}},
        {"eight-digit color", %{name: "Hero", color: "#3b82f680"}},
        {"optional fields omitted", %{name: "Hero", shortcut: nil, color: nil}}
      ]

      for {label, attrs} <- valid_cases do
        changeset = SheetRecord.create_changeset(%SheetRecord{}, attrs)

        assert changeset.valid?, "#{label}: #{inspect(errors_on(changeset))}"
      end
    end

    test "casts every optional field used by project materialization" do
      attrs = %{
        name: "Hero",
        shortcut: "hero",
        description: "The protagonist",
        color: "#3b82f6",
        banner_asset_id: 101,
        parent_id: 202,
        position: 3,
        hidden_inherited_block_ids: [303, 404]
      }

      sheet =
        %SheetRecord{}
        |> SheetRecord.create_changeset(attrs)
        |> apply_changes()

      assert Map.take(Map.from_struct(sheet), Map.keys(attrs)) == attrs
    end

    test "rejects the locally pinned invalid create corpus" do
      invalid_cases = [
        {"missing name", %{}, :name},
        {"blank name", %{name: "   "}, :name},
        {"name above maximum", %{name: String.duplicate("a", 201)}, :name},
        {"shortcut above maximum", %{name: "Hero", shortcut: String.duplicate("a", 51)}, :shortcut},
        {"uppercase shortcut", %{name: "Hero", shortcut: "Hero"}, :shortcut},
        {"shortcut starting with punctuation", %{name: "Hero", shortcut: ".hero"}, :shortcut},
        {"shortcut ending with punctuation", %{name: "Hero", shortcut: "hero-"}, :shortcut},
        {"shortcut with unsupported separator", %{name: "Hero", shortcut: "main_hero"}, :shortcut},
        {"too-short color", %{name: "Hero", color: "#ff"}, :color},
        {"unsupported color digits", %{name: "Hero", color: "#ggg"}, :color},
        {"color without hash", %{name: "Hero", color: "3b82f6"}, :color}
      ]

      for {label, attrs, field} <- invalid_cases do
        changeset = SheetRecord.create_changeset(%SheetRecord{}, attrs)
        errors = errors_on(changeset)

        refute changeset.valid?, "#{label}: expected the changeset to be invalid"
        assert Map.has_key?(errors, field), "#{label}: #{inspect(errors)}"
      end
    end

    test "declares the active project shortcut constraint with the canonical error" do
      changeset = SheetRecord.create_changeset(%SheetRecord{}, %{name: "Hero", shortcut: "hero"})

      assert Enum.any?(changeset.constraints, fn constraint ->
               constraint.type == :unique and
                 constraint.field == :shortcut and
                 constraint.constraint == "sheets_project_shortcut_unique" and
                 constraint.error_message == "is already taken in this project"
             end)
    end

    test "declares both foreign-key constraints used by materialization" do
      changeset =
        SheetRecord.create_changeset(%SheetRecord{}, %{
          name: "Hero",
          parent_id: 101,
          banner_asset_id: 202
        })

      assert Enum.any?(changeset.constraints, fn constraint ->
               constraint.type == :foreign_key and
                 constraint.field == :parent_id and
                 constraint.constraint == "sheets_parent_id_fkey"
             end)

      assert Enum.any?(changeset.constraints, fn constraint ->
               constraint.type == :foreign_key and
                 constraint.field == :banner_asset_id and
                 constraint.constraint == "sheets_banner_asset_id_fkey"
             end)
    end

    test "returns a shortcut changeset error when an import collides with an active sheet" do
      project = project_fixture(user_fixture())

      assert {:ok, _sheet} =
               SheetImportPersistence.import_sheet(project.id, %{name: "Hero", shortcut: "hero"})

      assert {:error, changeset} =
               SheetImportPersistence.import_sheet(project.id, %{name: "Other hero", shortcut: "hero"})

      assert errors_on(changeset).shortcut == ["is already taken in this project"]
    end
  end
end
