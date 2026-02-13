defmodule Storyarn.Screenplays.LinkedPageCrudTest do
  use Storyarn.DataCase

  alias Storyarn.Screenplays.LinkedPageCrud
  alias Storyarn.ScreenplaysFixtures

  setup do
    project = Storyarn.ProjectsFixtures.project_fixture()
    screenplay = ScreenplaysFixtures.screenplay_fixture(project)

    response_element =
      ScreenplaysFixtures.element_fixture(screenplay, %{
        type: "response",
        content: nil,
        data: %{
          "choices" => [
            %{"id" => "c1", "text" => "Go left", "condition" => nil, "instruction" => nil},
            %{"id" => "c2", "text" => "Go right", "condition" => nil, "instruction" => nil}
          ]
        }
      })

    %{project: project, screenplay: screenplay, element: response_element}
  end

  describe "create_linked_page/3" do
    test "creates child screenplay named after choice text", %{screenplay: sp, element: el} do
      assert {:ok, child, updated_el} = LinkedPageCrud.create_linked_page(sp, el, "c1")

      assert child.name == "Go left"
      assert child.parent_id == sp.id

      choices = updated_el.data["choices"]
      c1 = Enum.find(choices, &(&1["id"] == "c1"))
      assert c1["linked_screenplay_id"] == child.id
    end

    test "uses default name when choice text is empty", %{project: project} do
      screenplay = ScreenplaysFixtures.screenplay_fixture(project)

      element =
        ScreenplaysFixtures.element_fixture(screenplay, %{
          type: "response",
          content: nil,
          data: %{
            "choices" => [%{"id" => "c1", "text" => "", "condition" => nil, "instruction" => nil}]
          }
        })

      assert {:ok, child, _el} = LinkedPageCrud.create_linked_page(screenplay, element, "c1")
      assert child.name == "Untitled Branch"
    end

    test "fails when choice_id does not exist", %{screenplay: sp, element: el} do
      assert {:error, :choice_not_found} =
               LinkedPageCrud.create_linked_page(sp, el, "nonexistent")
    end

    test "fails when choice is already linked", %{screenplay: sp, element: el} do
      {:ok, _child, updated_el} = LinkedPageCrud.create_linked_page(sp, el, "c1")
      assert {:error, :already_linked} = LinkedPageCrud.create_linked_page(sp, updated_el, "c1")
    end

    test "does not link other choices", %{screenplay: sp, element: el} do
      {:ok, _child, updated_el} = LinkedPageCrud.create_linked_page(sp, el, "c1")

      c2 = Enum.find(updated_el.data["choices"], &(&1["id"] == "c2"))
      assert is_nil(c2["linked_screenplay_id"])
    end
  end

  describe "link_choice/4" do
    test "links choice to an existing child screenplay", %{
      project: project,
      screenplay: sp,
      element: el
    } do
      child = ScreenplaysFixtures.screenplay_fixture(project, %{parent_id: sp.id})

      assert {:ok, updated_el} = LinkedPageCrud.link_choice(el, "c1", child.id, sp.id)

      c1 = Enum.find(updated_el.data["choices"], &(&1["id"] == "c1"))
      assert c1["linked_screenplay_id"] == child.id
    end

    test "fails when child is not a child of parent", %{
      project: project,
      element: el,
      screenplay: sp
    } do
      other = ScreenplaysFixtures.screenplay_fixture(project)

      assert {:error, :invalid_child} = LinkedPageCrud.link_choice(el, "c1", other.id, sp.id)
    end

    test "fails when choice_id does not exist", %{project: project, screenplay: sp, element: el} do
      child = ScreenplaysFixtures.screenplay_fixture(project, %{parent_id: sp.id})

      assert {:error, :choice_not_found} = LinkedPageCrud.link_choice(el, "nope", child.id, sp.id)
    end

    test "fails when child is already linked to another choice", %{
      project: project,
      screenplay: sp,
      element: el
    } do
      child = ScreenplaysFixtures.screenplay_fixture(project, %{parent_id: sp.id})

      {:ok, updated_el} = LinkedPageCrud.link_choice(el, "c1", child.id, sp.id)

      assert {:error, :already_linked_to_other_choice} =
               LinkedPageCrud.link_choice(updated_el, "c2", child.id, sp.id)
    end
  end

  describe "unlink_choice/2" do
    test "clears linked_screenplay_id", %{screenplay: sp, element: el} do
      {:ok, _child, linked_el} = LinkedPageCrud.create_linked_page(sp, el, "c1")

      assert {:ok, updated_el} = LinkedPageCrud.unlink_choice(linked_el, "c1")

      c1 = Enum.find(updated_el.data["choices"], &(&1["id"] == "c1"))
      assert is_nil(c1["linked_screenplay_id"])
    end

    test "no-op when choice is already unlinked", %{element: el} do
      assert {:ok, ^el} = LinkedPageCrud.unlink_choice(el, "c1")
    end

    test "fails when choice_id does not exist", %{element: el} do
      assert {:error, :choice_not_found} = LinkedPageCrud.unlink_choice(el, "nonexistent")
    end
  end

  describe "linked_screenplay_ids/1" do
    test "returns linked IDs, skipping nil", %{screenplay: sp, element: el} do
      {:ok, child, updated_el} = LinkedPageCrud.create_linked_page(sp, el, "c1")

      ids = LinkedPageCrud.linked_screenplay_ids(updated_el)
      assert ids == [child.id]
    end

    test "returns empty list when no choices are linked", %{element: el} do
      assert LinkedPageCrud.linked_screenplay_ids(el) == []
    end
  end

  describe "list_child_screenplays/1" do
    test "lists children ordered by position", %{project: project, screenplay: sp} do
      child_b =
        ScreenplaysFixtures.screenplay_fixture(project, %{name: "Branch B", parent_id: sp.id})

      child_a =
        ScreenplaysFixtures.screenplay_fixture(project, %{name: "Branch A", parent_id: sp.id})

      children = LinkedPageCrud.list_child_screenplays(sp.id)

      ids = Enum.map(children, & &1.id)
      assert ids == [child_b.id, child_a.id]
    end

    test "excludes deleted children", %{project: project, screenplay: sp} do
      child = ScreenplaysFixtures.screenplay_fixture(project, %{parent_id: sp.id})
      Storyarn.Screenplays.delete_screenplay(child)

      assert LinkedPageCrud.list_child_screenplays(sp.id) == []
    end
  end
end
