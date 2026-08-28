defmodule Storyarn.Shared.HierarchySearchTest do
  use Storyarn.DataCase, async: true

  import Storyarn.ProjectsFixtures

  alias Storyarn.FlowsFixtures
  alias Storyarn.Platform.Shared.HierarchySearch
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Persistence.FlowRecord, as: Flow
  alias Storyarn.Scenes.Scene
  alias Storyarn.ScenesFixtures
  alias Storyarn.Sheets.Sheet
  alias Storyarn.SheetsFixtures

  describe "search/4" do
    test "uses the same hierarchy contract for sheets, flows, and scenes" do
      project = project_fixture()

      for schema <- [Sheet, Flow, Scene] do
        root = entity_fixture(schema, project, %{name: "Main Characters", shortcut: "main"})
        child = entity_fixture(schema, project, %{name: "Kael", shortcut: "kael", parent_id: root.id})

        result = HierarchySearch.search(schema, project.id, "main.")

        assert result.relation == :children
        assert result.anchor.id == root.id
        assert [%{entity: %{id: child_id}, has_children: false, path: ["main", "kael"]}] = result.items
        assert child_id == child.id
        refute result.truncated
      end
    end

    test "performs a bounded contains search across the complete tree" do
      project = project_fixture()
      root = entity_fixture(Sheet, project, %{name: "Main Characters", shortcut: "main-characters"})

      child =
        entity_fixture(Sheet, project, %{
          name: "Kael the Wanderer",
          shortcut: "kael",
          parent_id: root.id
        })

      _unrelated = entity_fixture(Sheet, project, %{name: "Village", shortcut: "village"})

      assert %{
               relation: :matches,
               anchor: nil,
               truncated: false,
               items: [
                 %{
                   entity: %{id: child_id},
                   has_children: false,
                   path: ["main-characters", "kael"]
                 }
               ]
             } = HierarchySearch.search(Sheet, project.id, "wander")

      assert child_id == child.id
    end

    test "lists only direct children after an exact shortcut and filters them by prefix" do
      project = project_fixture()
      root = entity_fixture(Sheet, project, %{name: "Main Characters", shortcut: "main"})
      kael = entity_fixture(Sheet, project, %{name: "Kael", shortcut: "kael", parent_id: root.id})
      mira = entity_fixture(Sheet, project, %{name: "Mira", shortcut: "mira", parent_id: root.id})

      grandchild =
        entity_fixture(Sheet, project, %{
          name: "Kestrel",
          shortcut: "kestrel",
          parent_id: kael.id
        })

      children = HierarchySearch.search(Sheet, project.id, "main.")

      assert children.relation == :children
      assert children.anchor.id == root.id
      assert Enum.map(children.items, & &1.entity.id) == [kael.id, mira.id]
      assert Enum.find(children.items, &(&1.entity.id == kael.id)).has_children

      prefixed = HierarchySearch.search(Sheet, project.id, "main.k")

      assert prefixed.relation == :children
      assert prefixed.anchor.id == root.id
      assert Enum.map(prefixed.items, & &1.entity.id) == [kael.id]

      nested = HierarchySearch.search(Sheet, project.id, "main.kael.")

      assert nested.relation == :children
      assert nested.anchor.id == kael.id
      assert Enum.map(nested.items, & &1.entity.id) == [grandchild.id]
    end

    test "searches recursively below an anchor with the question-mark modifier" do
      project = project_fixture()
      root = entity_fixture(Sheet, project, %{name: "Main Characters", shortcut: "main"})
      kael = entity_fixture(Sheet, project, %{name: "Kael", shortcut: "kael", parent_id: root.id})

      kestrel =
        entity_fixture(Sheet, project, %{
          name: "Kestrel",
          shortcut: "kestrel",
          parent_id: kael.id
        })

      _outside = entity_fixture(Sheet, project, %{name: "Kestrel Outside", shortcut: "outside-kestrel"})

      result = HierarchySearch.search(Sheet, project.id, "main.?est")

      assert result.relation == :descendants
      assert result.anchor.id == root.id

      assert [
               %{
                 entity: %{id: kestrel_id},
                 has_children: false,
                 path: ["main", "kael", "kestrel"]
               }
             ] = result.items

      assert kestrel_id == kestrel.id
    end

    test "resolves the deepest exact hierarchy path when shortcuts contain dots" do
      project = project_fixture()
      root = entity_fixture(Sheet, project, %{name: "Main", shortcut: "main"})

      nested_anchor =
        entity_fixture(Sheet, project, %{
          name: "Main Characters",
          shortcut: "main.characters",
          parent_id: root.id
        })

      kael =
        entity_fixture(Sheet, project, %{
          name: "Kael",
          shortcut: "kael",
          parent_id: nested_anchor.id
        })

      _wrong_branch =
        entity_fixture(Sheet, project, %{
          name: "Characters Keep",
          shortcut: "characters-keep",
          parent_id: root.id
        })

      result = HierarchySearch.search(Sheet, project.id, "main.main.characters.k")

      assert result.relation == :children
      assert result.anchor.id == nested_anchor.id
      assert Enum.map(result.items, & &1.entity.id) == [kael.id]
      assert hd(result.items).path == ["main", "main.characters", "kael"]
    end

    test "isolates projects and excludes soft-deleted entities and anchors" do
      project = project_fixture()
      other_project = project_fixture()

      root = entity_fixture(Sheet, project, %{name: "Main", shortcut: "main"})
      active = entity_fixture(Sheet, project, %{name: "Kira", shortcut: "kira", parent_id: root.id})
      deleted = entity_fixture(Sheet, project, %{name: "Kael", shortcut: "kael", parent_id: root.id})

      other_root = entity_fixture(Sheet, other_project, %{name: "Main", shortcut: "main"})

      _other_child =
        entity_fixture(Sheet, other_project, %{
          name: "Kora",
          shortcut: "kora",
          parent_id: other_root.id
        })

      Repo.update_all(
        from(sheet in Sheet, where: sheet.id == ^deleted.id),
        set: [deleted_at: TimeHelpers.now()]
      )

      result = HierarchySearch.search(Sheet, project.id, "main.?k")

      assert result.anchor.id == root.id
      assert Enum.map(result.items, & &1.entity.id) == [active.id]

      Repo.update_all(
        from(sheet in Sheet, where: sheet.id == ^root.id),
        set: [deleted_at: TimeHelpers.now()]
      )

      assert %{anchor: nil, items: [], relation: :descendants} =
               HierarchySearch.search(Sheet, project.id, "main.?k")
    end

    test "fetches one extra row for truncation and caps requested limits at fifty" do
      project = project_fixture()

      for index <- 1..51 do
        padded_index = index |> Integer.to_string() |> String.pad_leading(2, "0")

        entity_fixture(Sheet, project, %{
          name: "Match #{padded_index}",
          shortcut: "match-#{padded_index}",
          position: index
        })
      end

      default_page = HierarchySearch.search(Sheet, project.id, "match")
      assert length(default_page.items) == 25
      assert default_page.truncated

      capped_page = HierarchySearch.search(Sheet, project.id, "match", limit: 500)
      assert length(capped_page.items) == 50
      assert capped_page.truncated

      small_page = HierarchySearch.search(Sheet, project.id, "match", limit: 2)
      assert length(small_page.items) == 2
      assert small_page.truncated
    end

    test "treats LIKE wildcard characters as literal user input" do
      project = project_fixture()
      literal = entity_fixture(Sheet, project, %{name: "Progress 100%", shortcut: "progress-100"})
      _other = entity_fixture(Sheet, project, %{name: "Progress 1000", shortcut: "progress-1000"})

      result = HierarchySearch.search(Sheet, project.id, "100%")

      assert Enum.map(result.items, & &1.entity.id) == [literal.id]
    end

    test "returns no hierarchy results when the requested anchor does not exist" do
      project = project_fixture()
      _entity = entity_fixture(Sheet, project, %{name: "Kael", shortcut: "kael"})

      assert %{anchor: nil, items: [], relation: :children, truncated: false} =
               HierarchySearch.search(Sheet, project.id, "missing.k")

      assert %{anchor: nil, items: [], relation: :descendants, truncated: false} =
               HierarchySearch.search(Sheet, project.id, "missing.?k")
    end
  end

  defp entity_fixture(Sheet, project, attrs), do: SheetsFixtures.sheet_fixture(project, attrs)
  defp entity_fixture(Flow, project, attrs), do: FlowsFixtures.flow_fixture(project, attrs)
  defp entity_fixture(Scene, project, attrs), do: ScenesFixtures.scene_fixture(project, attrs)
end
