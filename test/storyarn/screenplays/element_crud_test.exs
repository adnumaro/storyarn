defmodule Storyarn.Screenplays.ElementCrudTest do
  use Storyarn.DataCase

  alias Storyarn.Screenplays.ElementCrud

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScreenplaysFixtures

  defp setup_screenplay(_context) do
    user = user_fixture()
    project = project_fixture(user)
    screenplay = screenplay_fixture(project)
    %{project: project, screenplay: screenplay}
  end

  describe "list_elements/1" do
    setup :setup_screenplay

    test "returns elements ordered by position", %{screenplay: screenplay} do
      e1 = element_fixture(screenplay, %{type: "scene_heading", content: "INT. TAVERN", position: 0})
      e2 = element_fixture(screenplay, %{type: "action", content: "A door opens.", position: 1})
      e3 = element_fixture(screenplay, %{type: "character", content: "JAIME", position: 2})

      result = ElementCrud.list_elements(screenplay.id)

      assert length(result) == 3
      assert Enum.map(result, & &1.id) == [e1.id, e2.id, e3.id]
    end

    test "returns empty list for screenplay with no elements", %{screenplay: screenplay} do
      assert ElementCrud.list_elements(screenplay.id) == []
    end
  end

  describe "create_element/2" do
    setup :setup_screenplay

    test "appends at end with correct position", %{screenplay: screenplay} do
      {:ok, e1} = ElementCrud.create_element(screenplay, %{type: "scene_heading", content: "INT."})
      {:ok, e2} = ElementCrud.create_element(screenplay, %{type: "action", content: "Text"})

      assert e1.position == 0
      assert e2.position == 1
    end

    test "fails with invalid type", %{screenplay: screenplay} do
      {:error, changeset} = ElementCrud.create_element(screenplay, %{type: "bogus"})
      assert "is invalid" in errors_on(changeset).type
    end
  end

  describe "insert_element_at/3" do
    setup :setup_screenplay

    test "inserts at beginning (position 0)", %{screenplay: screenplay} do
      element_fixture(screenplay, %{type: "action", content: "Existing", position: 0})

      {:ok, new} =
        ElementCrud.insert_element_at(screenplay, 0, %{type: "scene_heading", content: "INT."})

      result = ElementCrud.list_elements(screenplay.id)

      assert length(result) == 2
      assert hd(result).id == new.id
      assert hd(result).position == 0
      assert List.last(result).position == 1
    end

    test "inserts in the middle, shifts subsequent", %{screenplay: screenplay} do
      element_fixture(screenplay, %{type: "scene_heading", position: 0})
      element_fixture(screenplay, %{type: "character", position: 1})
      element_fixture(screenplay, %{type: "dialogue", position: 2})

      {:ok, inserted} =
        ElementCrud.insert_element_at(screenplay, 1, %{type: "action", content: "New"})

      result = ElementCrud.list_elements(screenplay.id)
      positions = Enum.map(result, & &1.position)

      assert length(result) == 4
      assert positions == [0, 1, 2, 3]
      assert Enum.at(result, 1).id == inserted.id
    end

    test "inserts at end", %{screenplay: screenplay} do
      element_fixture(screenplay, %{type: "action", position: 0})
      element_fixture(screenplay, %{type: "action", position: 1})

      {:ok, inserted} =
        ElementCrud.insert_element_at(screenplay, 2, %{type: "transition", content: "CUT TO:"})

      result = ElementCrud.list_elements(screenplay.id)

      assert length(result) == 3
      assert List.last(result).id == inserted.id
      assert List.last(result).position == 2
    end
  end

  describe "update_element/2" do
    setup :setup_screenplay

    test "updates content and data", %{screenplay: screenplay} do
      element = element_fixture(screenplay, %{type: "action", content: "Old"})

      {:ok, updated} =
        ElementCrud.update_element(element, %{content: "New", data: %{"key" => "val"}})

      assert updated.content == "New"
      assert updated.data == %{"key" => "val"}
    end

    test "can change element type", %{screenplay: screenplay} do
      element = element_fixture(screenplay, %{type: "action", content: "JAIME"})

      {:ok, updated} = ElementCrud.update_element(element, %{type: "character"})
      assert updated.type == "character"
    end
  end

  describe "delete_element/1" do
    setup :setup_screenplay

    test "removes element and compacts positions", %{screenplay: screenplay} do
      e1 = element_fixture(screenplay, %{type: "scene_heading", position: 0})
      e2 = element_fixture(screenplay, %{type: "action", position: 1})
      e3 = element_fixture(screenplay, %{type: "character", position: 2})

      {:ok, _} = ElementCrud.delete_element(e2)

      result = ElementCrud.list_elements(screenplay.id)
      assert length(result) == 2
      assert Enum.map(result, & &1.id) == [e1.id, e3.id]
      assert Enum.map(result, & &1.position) == [0, 1]
    end

    test "deleting last element works", %{screenplay: screenplay} do
      e1 = element_fixture(screenplay, %{type: "action", position: 0})

      {:ok, _} = ElementCrud.delete_element(e1)

      assert ElementCrud.list_elements(screenplay.id) == []
    end
  end

  describe "reorder_elements/2" do
    setup :setup_screenplay

    test "reorders elements by ID list", %{screenplay: screenplay} do
      e1 = element_fixture(screenplay, %{type: "scene_heading", position: 0})
      e2 = element_fixture(screenplay, %{type: "action", position: 1})
      e3 = element_fixture(screenplay, %{type: "character", position: 2})

      # Reverse the order
      {:ok, result} = ElementCrud.reorder_elements(screenplay.id, [e3.id, e2.id, e1.id])

      assert Enum.map(result, & &1.id) == [e3.id, e2.id, e1.id]
      assert Enum.map(result, & &1.position) == [0, 1, 2]
    end
  end

  describe "split_element/3" do
    setup :setup_screenplay

    test "splits content at middle", %{screenplay: screenplay} do
      element = element_fixture(screenplay, %{type: "action", content: "Hello World", position: 0})

      {:ok, {before_el, new_el, after_el}} =
        ElementCrud.split_element(element, 5, "character")

      assert before_el.content == "Hello"
      assert before_el.type == "action"
      assert before_el.position == 0

      assert new_el.content == ""
      assert new_el.type == "character"
      assert new_el.position == 1

      assert after_el.content == " World"
      assert after_el.type == "action"
      assert after_el.position == 2
    end

    test "splits at beginning (before text is empty)", %{screenplay: screenplay} do
      element = element_fixture(screenplay, %{type: "action", content: "Full text", position: 0})

      {:ok, {before_el, new_el, after_el}} =
        ElementCrud.split_element(element, 0, "scene_heading")

      assert before_el.content == ""
      assert new_el.type == "scene_heading"
      assert new_el.position == 1
      assert after_el.content == "Full text"
    end

    test "splits at end (after text is empty)", %{screenplay: screenplay} do
      element = element_fixture(screenplay, %{type: "action", content: "Full text", position: 0})

      {:ok, {before_el, new_el, after_el}} =
        ElementCrud.split_element(element, 9, "transition")

      assert before_el.content == "Full text"
      assert new_el.type == "transition"
      assert after_el.content == ""
    end

    test "shifts subsequent element positions by +2", %{screenplay: screenplay} do
      element_fixture(screenplay, %{type: "scene_heading", content: "INT.", position: 0})
      split_me = element_fixture(screenplay, %{type: "action", content: "AB", position: 1})
      element_fixture(screenplay, %{type: "character", content: "JAIME", position: 2})
      element_fixture(screenplay, %{type: "dialogue", content: "Hello", position: 3})

      {:ok, _} = ElementCrud.split_element(split_me, 1, "note")

      result = ElementCrud.list_elements(screenplay.id)
      positions = Enum.map(result, & &1.position)

      # Original 4 elements + 2 new from split = 6 total
      assert length(result) == 6
      assert positions == [0, 1, 2, 3, 4, 5]
    end
  end
end
