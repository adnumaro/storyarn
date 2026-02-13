defmodule Storyarn.Screenplays.ElementGroupingTest do
  use Storyarn.DataCase

  alias Storyarn.Screenplays.ElementGrouping

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScreenplaysFixtures

  defp setup_screenplay(_context) do
    user = user_fixture()
    project = project_fixture(user)
    screenplay = screenplay_fixture(project)
    %{screenplay: screenplay}
  end

  defp make_elements(screenplay, type_list) do
    type_list
    |> Enum.with_index()
    |> Enum.map(fn {type, idx} ->
      element_fixture(screenplay, %{type: type, content: "#{type}_#{idx}", position: idx})
    end)
  end

  describe "compute_dialogue_groups/1" do
    setup :setup_screenplay

    test "returns empty list for empty input" do
      assert ElementGrouping.compute_dialogue_groups([]) == []
    end

    test "groups character + dialogue", %{screenplay: sp} do
      elements = make_elements(sp, ["character", "dialogue"])
      result = ElementGrouping.compute_dialogue_groups(elements)

      [{_char, gid1}, {_dial, gid2}] = result
      assert gid1 != nil
      assert gid1 == gid2
    end

    test "groups character + parenthetical + dialogue", %{screenplay: sp} do
      elements = make_elements(sp, ["character", "parenthetical", "dialogue"])
      result = ElementGrouping.compute_dialogue_groups(elements)

      [{_c, g1}, {_p, g2}, {_d, g3}] = result
      assert g1 != nil
      assert g1 == g2
      assert g2 == g3
    end

    test "breaks group on non-dialogue type", %{screenplay: sp} do
      elements = make_elements(sp, ["character", "dialogue", "action", "character", "dialogue"])
      result = ElementGrouping.compute_dialogue_groups(elements)

      [{_c1, g1}, {_d1, g2}, {_act, g3}, {_c2, g4}, {_d2, g5}] = result
      assert g1 == g2
      assert g3 == nil
      assert g4 == g5
      assert g1 != g4
    end

    test "handles multiple consecutive groups", %{screenplay: sp} do
      elements =
        make_elements(sp, [
          "character",
          "dialogue",
          "character",
          "parenthetical",
          "dialogue"
        ])

      result = ElementGrouping.compute_dialogue_groups(elements)

      [{_, g1}, {_, g2}, {_, g3}, {_, g4}, {_, g5}] = result
      assert g1 == g2
      assert g3 == g4
      assert g4 == g5
      assert g1 != g3
    end

    test "returns nil group_id for non-dialogue elements", %{screenplay: sp} do
      elements = make_elements(sp, ["scene_heading", "action", "transition"])
      result = ElementGrouping.compute_dialogue_groups(elements)

      Enum.each(result, fn {_el, gid} ->
        assert gid == nil
      end)
    end

    test "orphan parenthetical gets nil group_id", %{screenplay: sp} do
      elements = make_elements(sp, ["parenthetical"])
      [{_el, gid}] = ElementGrouping.compute_dialogue_groups(elements)
      assert gid == nil
    end

    test "orphan dialogue gets nil group_id", %{screenplay: sp} do
      elements = make_elements(sp, ["dialogue"])
      [{_el, gid}] = ElementGrouping.compute_dialogue_groups(elements)
      assert gid == nil
    end
  end

  describe "group_elements/1" do
    setup :setup_screenplay

    test "returns empty list for empty input" do
      assert ElementGrouping.group_elements([]) == []
    end

    test "returns dialogue_group for character + dialogue", %{screenplay: sp} do
      elements = make_elements(sp, ["character", "dialogue"])
      [group] = ElementGrouping.group_elements(elements)

      assert group.type == :dialogue_group
      assert length(group.elements) == 2
      assert group.group_id != nil
    end

    test "returns individual groups for scene_heading, action, etc.", %{screenplay: sp} do
      elements = make_elements(sp, ["scene_heading", "action", "transition"])
      result = ElementGrouping.group_elements(elements)

      assert length(result) == 3
      assert Enum.at(result, 0).type == :scene_heading
      assert Enum.at(result, 1).type == :action
      assert Enum.at(result, 2).type == :transition

      Enum.each(result, fn g ->
        assert length(g.elements) == 1
        assert g.group_id == nil
      end)
    end

    test "attaches response to preceding dialogue group", %{screenplay: sp} do
      elements = make_elements(sp, ["character", "dialogue", "response"])
      result = ElementGrouping.group_elements(elements)

      assert length(result) == 1
      [group] = result
      assert group.type == :dialogue_group
      assert length(group.elements) == 3
      types = Enum.map(group.elements, & &1.type)
      assert types == ["character", "dialogue", "response"]
    end

    test "marks orphan response as standalone", %{screenplay: sp} do
      elements = make_elements(sp, ["action", "response"])
      result = ElementGrouping.group_elements(elements)

      assert length(result) == 2
      assert Enum.at(result, 0).type == :action
      assert Enum.at(result, 1).type == :response
    end

    test "returns non_mappeable for note/section/page_break/title_page", %{screenplay: sp} do
      elements = make_elements(sp, ["note", "section", "page_break", "title_page"])
      result = ElementGrouping.group_elements(elements)

      assert length(result) == 4

      Enum.each(result, fn g ->
        assert g.type == :non_mappeable
        assert g.group_id == nil
      end)
    end

    test "handles mixed element sequence (realistic screenplay)", %{screenplay: sp} do
      elements =
        make_elements(sp, [
          "scene_heading",
          "action",
          "character",
          "parenthetical",
          "dialogue",
          "response",
          "character",
          "dialogue",
          "transition",
          "note"
        ])

      result = ElementGrouping.group_elements(elements)

      types = Enum.map(result, & &1.type)

      assert types == [
               :scene_heading,
               :action,
               :dialogue_group,
               :dialogue_group,
               :transition,
               :non_mappeable
             ]

      # First dialogue group: character + parenthetical + dialogue + response
      first_dg = Enum.at(result, 2)
      assert length(first_dg.elements) == 4

      assert Enum.map(first_dg.elements, & &1.type) == [
               "character",
               "parenthetical",
               "dialogue",
               "response"
             ]

      # Second dialogue group: character + dialogue
      second_dg = Enum.at(result, 3)
      assert length(second_dg.elements) == 2
      assert Enum.map(second_dg.elements, & &1.type) == ["character", "dialogue"]
    end

    test "groups hub_marker and jump_marker individually", %{screenplay: sp} do
      elements = make_elements(sp, ["hub_marker", "jump_marker"])
      result = ElementGrouping.group_elements(elements)

      assert length(result) == 2
      assert Enum.at(result, 0).type == :hub_marker
      assert Enum.at(result, 1).type == :jump_marker
    end

    test "conditional and instruction are standalone groups", %{screenplay: sp} do
      elements = make_elements(sp, ["conditional", "instruction"])
      result = ElementGrouping.group_elements(elements)

      assert length(result) == 2
      assert Enum.at(result, 0).type == :conditional
      assert Enum.at(result, 1).type == :instruction
    end

    test "dual_dialogue is a standalone group", %{screenplay: sp} do
      elements = make_elements(sp, ["dual_dialogue"])
      result = ElementGrouping.group_elements(elements)

      assert length(result) == 1
      assert Enum.at(result, 0).type == :dual_dialogue
      assert Enum.at(result, 0).group_id == nil
    end

    test "dual_dialogue between dialogue groups does not break grouping", %{screenplay: sp} do
      elements =
        make_elements(sp, [
          "character",
          "dialogue",
          "dual_dialogue",
          "character",
          "dialogue"
        ])

      result = ElementGrouping.group_elements(elements)

      types = Enum.map(result, & &1.type)
      assert types == [:dialogue_group, :dual_dialogue, :dialogue_group]
    end
  end

  describe "compute_continuations/1" do
    setup :setup_screenplay

    test "returns empty MapSet for empty list" do
      assert ElementGrouping.compute_continuations([]) == MapSet.new()
    end

    test "no continuation for single dialogue group", %{screenplay: sp} do
      elements =
        make_elements_with_content(sp, [
          {"character", "JAIME"},
          {"dialogue", "Hello."}
        ])

      assert ElementGrouping.compute_continuations(elements) == MapSet.new()
    end

    test "marks continuation when same speaker in consecutive groups", %{screenplay: sp} do
      elements =
        make_elements_with_content(sp, [
          {"character", "JAIME"},
          {"dialogue", "Hello."},
          {"character", "JAIME"},
          {"dialogue", "How are you?"}
        ])

      continuations = ElementGrouping.compute_continuations(elements)
      second_char = Enum.at(elements, 2)

      assert MapSet.member?(continuations, second_char.id)
      assert MapSet.size(continuations) == 1
    end

    test "no continuation when different speakers", %{screenplay: sp} do
      elements =
        make_elements_with_content(sp, [
          {"character", "JAIME"},
          {"dialogue", "Hello."},
          {"character", "ALICE"},
          {"dialogue", "Hi there."}
        ])

      assert ElementGrouping.compute_continuations(elements) == MapSet.new()
    end

    test "scene heading resets speaker context", %{screenplay: sp} do
      elements =
        make_elements_with_content(sp, [
          {"character", "JAIME"},
          {"dialogue", "Hello."},
          {"scene_heading", "INT. OFFICE - DAY"},
          {"character", "JAIME"},
          {"dialogue", "Different scene."}
        ])

      assert ElementGrouping.compute_continuations(elements) == MapSet.new()
    end

    test "action between same speaker preserves continuation", %{screenplay: sp} do
      elements =
        make_elements_with_content(sp, [
          {"character", "JAIME"},
          {"dialogue", "Hello."},
          {"action", "He pauses."},
          {"character", "JAIME"},
          {"dialogue", "I mean hi."}
        ])

      continuations = ElementGrouping.compute_continuations(elements)
      second_char = Enum.at(elements, 3)

      assert MapSet.member?(continuations, second_char.id)
    end

    test "comparison is case-insensitive", %{screenplay: sp} do
      elements =
        make_elements_with_content(sp, [
          {"character", "JAIME"},
          {"dialogue", "Hello."},
          {"character", "jaime"},
          {"dialogue", "Hi again."}
        ])

      continuations = ElementGrouping.compute_continuations(elements)
      assert MapSet.size(continuations) == 1
    end

    test "strips extensions when comparing names", %{screenplay: sp} do
      elements =
        make_elements_with_content(sp, [
          {"character", "JAIME"},
          {"dialogue", "Hello."},
          {"character", "JAIME (V.O.)"},
          {"dialogue", "Thinking aloud."}
        ])

      continuations = ElementGrouping.compute_continuations(elements)
      second_char = Enum.at(elements, 2)

      assert MapSet.member?(continuations, second_char.id)
    end

    test "dual_dialogue resets speaker context", %{screenplay: sp} do
      elements =
        make_elements_with_content(sp, [
          {"character", "JAIME"},
          {"dialogue", "Hello."},
          {"dual_dialogue", ""},
          {"character", "JAIME"},
          {"dialogue", "After dual."}
        ])

      assert ElementGrouping.compute_continuations(elements) == MapSet.new()
    end

    test "page_break does not reset continuation", %{screenplay: sp} do
      elements =
        make_elements_with_content(sp, [
          {"character", "JAIME"},
          {"dialogue", "First line."},
          {"page_break", ""},
          {"action", "He pauses."},
          {"character", "JAIME"},
          {"dialogue", "Second line."}
        ])

      continuations = ElementGrouping.compute_continuations(elements)
      jaime_2 = Enum.at(elements, 4)
      assert MapSet.member?(continuations, jaime_2.id)
    end

    test "transition resets speaker context", %{screenplay: sp} do
      elements =
        make_elements_with_content(sp, [
          {"character", "JAIME"},
          {"dialogue", "Hello."},
          {"transition", "CUT TO:"},
          {"character", "JAIME"},
          {"dialogue", "Same person, new scene."}
        ])

      assert ElementGrouping.compute_continuations(elements) == MapSet.new()
    end
  end

  # Helper that creates elements with specific content
  defp make_elements_with_content(screenplay, type_content_list) do
    type_content_list
    |> Enum.with_index()
    |> Enum.map(fn {{type, content}, idx} ->
      element_fixture(screenplay, %{type: type, content: content, position: idx})
    end)
  end
end
