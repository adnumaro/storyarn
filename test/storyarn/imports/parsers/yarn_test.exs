defmodule Storyarn.Imports.Parsers.YarnTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.Evaluator.ConditionEval
  alias Storyarn.Flows.NodeConnectionRules
  alias Storyarn.Imports
  alias Storyarn.Imports.ImportPlan
  alias Storyarn.Imports.Materializer
  alias Storyarn.Imports.ParserRegistry
  alias Storyarn.Imports.Parsers.Yarn.Layout
  alias Storyarn.Imports.Parsers.Yarn.ReviewDecisions
  alias Storyarn.Imports.PlanStorage
  alias Storyarn.Imports.SourceBundle
  alias Storyarn.Repo
  alias Storyarn.Shared.WordCount
  alias Storyarn.Sheets

  @project """
  title: Start
  tags: opening
  ---
  <<declare $gold = 10>>
  <<declare $met_guide = false>>
  Guide: Welcome. You have {$gold} coins. #line:start_welcome
  -> Ask about the gate #line:ask_gate
      Guide: It opens at dawn.
      <<set $met_guide to true>>
      <<jump Ending>>
  -> Leave <<if $gold >= 5>> #line:leave
      <<set $gold to $gold - 5>>
      <<jump Ending>>
  ===

  title: Ending
  ---
  <<if $met_guide>>
      Guide: Until next time.
  <<else>>
      You leave without an answer.
  <<endif>>
  <<stop>>
  ===
  """

  describe "parse_file/2" do
    test "normalizes Yarn nodes, dialogue, choices, variables and control flow" do
      assert {:ok, %ImportPlan{format: :yarn} = plan} =
               Imports.parse_file("dialogue.yarn", @project)

      assert plan.parser_version == "5"
      assert plan.source_kind == :file
      assert plan.metadata.flow_count == 2
      assert plan.metadata.variable_count == 2

      variable_sheet = Enum.find(plan.data["sheets"], &(&1["shortcut"] == "yarn"))
      assert Enum.map(variable_sheet["blocks"], & &1["variable_name"]) == ["gold", "met_guide"]

      assert Enum.any?(plan.data["sheets"], &(&1["name"] == "Guide"))

      start_flow = Enum.find(plan.data["flows"], &(&1["name"] == "Start"))
      ending_flow = Enum.find(plan.data["flows"], &(&1["name"] == "Ending"))

      dialogue = Enum.find(start_flow["nodes"], &(&1["type"] == "dialogue"))
      assert dialogue["data"]["text"] =~ "{yarn.gold}"
      assert length(dialogue["data"]["responses"]) == 2
      assert Enum.any?(dialogue["data"]["responses"], &is_binary(&1["condition"]))

      assert Enum.any?(start_flow["nodes"], &(&1["type"] == "instruction"))

      assert Enum.any?(start_flow["nodes"], fn node ->
               node["type"] == "exit" and
                 node["data"]["referenced_flow_id"] == ending_flow["id"]
             end)

      assert Enum.any?(ending_flow["nodes"], &(&1["type"] == "condition"))
      assert Enum.any?(ending_flow["nodes"], &(&1["type"] == "exit"))
    end

    test "emits unique graph IDs, existing endpoints and native-valid pins" do
      assert {:ok, plan} = Imports.parse_file("dialogue.yarn", @project)

      Enum.each(plan.data["flows"], &assert_valid_graph/1)
    end

    test "extracts variables according to Yarn syntax context" do
      source = """
      title: Start
      ---
      The price is $usd, while {$dialogue_value} is interpolated.
      -> Pay $usd with {$option_value} <<if $option_condition>>
      <<if $branch_condition == "$condition_literal">>
        Conditional branch
      <<endif>>
      <<set $assignment_target = $assignment_source>>
      <<set $label = "price $assignment_literal">>
      <<custom_command $command_argument>>
      ===
      """

      assert {:ok, plan} = raw_yarn_plan(source)

      variable_sheet = Enum.find(plan.data["sheets"], &(&1["shortcut"] == "yarn"))

      assert variable_sheet["blocks"]
             |> Enum.map(& &1["variable_name"])
             |> Enum.sort() == [
               "assignment_source",
               "assignment_target",
               "branch_condition",
               "dialogue_value",
               "label",
               "option_condition",
               "option_value"
             ]

      refute Enum.any?(variable_sheet["blocks"], fn block ->
               block["variable_name"] in [
                 "usd",
                 "assignment_literal",
                 "command_argument",
                 "condition_literal"
               ]
             end)

      [flow] = plan.data["flows"]
      dialogue = Enum.find(flow["nodes"], &(&1["type"] == "dialogue"))
      assert dialogue["data"]["text"] == "The price is $usd, while {yarn.dialogue_value} is interpolated."

      assert Enum.any?(dialogue["data"]["responses"], fn response ->
               response["text"] == "Pay $usd with $yarn.option_value"
             end)
    end

    test "suggests scoped presentation channels and applies an explicit complete mapping" do
      source = """
      title: Start
      ---
      Capsley: Welcome to the samples.
      <<start_slide>>
      SlideHeader: Agenda
      SlideBullet: Yarn Spinner
      SlideImage: intro-1
      <<end_slide>>
      Capsley: Here is the code.
      <<clear_slide>>
      <<start_slide>>
      SlideHeader: Code
      SlideBullet: Storyarn
      SlideImage: code-1
      <<end_slide>>
      Capsley: That is all.
      Capsely: Thanks for watching.
      ===
      """

      assert {:ok, plan} = Imports.parse_file("welcome.yarn", source)

      assert plan.metadata.variable_count == 0
      assert plan.metadata.sheet_count == 2
      assert plan.metadata.speaker_sheet_count == 2
      assert plan.metadata.presentation_channel_count == 3
      assert plan.metadata.possible_speaker_alias_count == 1

      assert plan.data["sheets"]
             |> Enum.map(& &1["name"])
             |> Enum.sort() == ["Capsely", "Capsley"]

      assert Enum.all?(plan.data["sheets"], &(&1["blocks"] == []))

      refute Enum.any?(plan.data["sheets"], fn sheet ->
               sheet["name"] in ["SlideHeader", "SlideBullet", "SlideImage"]
             end)

      assert Enum.count(plan.issues, &(&1.code == :yarn_presentation_channel_preserved)) == 3
      assert Enum.count(plan.issues, &(&1.code == :possible_yarn_speaker_alias)) == 1

      [provisional_flow] = plan.data["flows"]
      provisional_dialogues = Enum.filter(provisional_flow["nodes"], &(&1["type"] == "dialogue"))
      assert length(provisional_dialogues) == 10

      assert provisional_dialogues
             |> Enum.filter(&(&1["data"]["import_yarn_speaker"] == "SlideImage"))
             |> Enum.map(& &1["data"]["import_yarn_literal_text"])
             |> Enum.sort() == ["SlideImage: code-1", "SlideImage: intro-1"]

      review = plan.data["import_review"]
      assert review["variable_count"] == 0
      assert review["speaker_decision_count"] == 5
      assert review["speaker_decisions_truncated"] == false
      assert review["sheet_speaker_count"] == 2
      assert review["preserved_channel_count"] == 3
      assert review["possible_speaker_alias_count"] == 1
      assert review["possible_speaker_aliases_truncated"] == false
      assert review["requires_acknowledgement"] == true

      assert review["speaker_decisions"]
             |> Enum.filter(&(&1["suggested_action"] == "preserve_literal"))
             |> Enum.map(& &1["speaker"])
             |> Enum.sort() == ["SlideBullet", "SlideHeader", "SlideImage"]

      assert Enum.all?(
               Enum.filter(
                 review["speaker_decisions"],
                 &(&1["suggested_action"] == "preserve_literal")
               ),
               fn decision ->
                 decision["confidence"] == "high" and
                   decision["reasons"] == ["repeated_scoped_presentation_channel"] and
                   decision["matched_scope_regions"] == 2 and
                   decision["speaker_matched_scope_regions"] == 2
               end
             )

      assert [
               %{
                 "decision" => "review",
                 "evidence" => "single_adjacent_transposition_with_dominant_frequency",
                 "less_frequent" => "Capsely",
                 "more_frequent" => "Capsley"
               }
             ] = review["possible_speaker_aliases"]

      decisions =
        Enum.map(selected_suggestions(review), fn
          %{"speaker" => "Capsely"} = decision ->
            decision
            |> Map.put("action", "map_to_sheet")
            |> Map.put("target_speaker", "Capsley")

          decision ->
            decision
        end)

      assert {:ok, resolved_plan} = ReviewDecisions.apply(plan, true, decisions)

      assert resolved_plan.data["import_review"]["speaker_decision_count"] == 5
      assert resolved_plan.data["import_review_resolution"]["version"] == 2
      assert is_binary(resolved_plan.data["import_review_resolution"]["decision_fingerprint"])
      assert ReviewDecisions.resolved?(resolved_plan)

      assert Enum.map(resolved_plan.data["sheets"], & &1["name"]) == ["Capsley"]

      [flow] = resolved_plan.data["flows"]

      presentation_dialogues =
        Enum.filter(flow["nodes"], fn node ->
          node["type"] == "dialogue" and
            node["data"]["speaker_sheet_id"] == nil and
            String.starts_with?(node["data"]["text"], ["SlideBullet:", "SlideHeader:", "SlideImage:"])
        end)

      assert presentation_dialogues
             |> Enum.map(& &1["data"]["text"])
             |> Enum.sort() == [
               "SlideBullet: Storyarn",
               "SlideBullet: Yarn Spinner",
               "SlideHeader: Agenda",
               "SlideHeader: Code",
               "SlideImage: code-1",
               "SlideImage: intro-1"
             ]

      connected_sources = MapSet.new(flow["connections"], & &1["source_node_id"])
      connected_targets = MapSet.new(flow["connections"], & &1["target_node_id"])

      assert Enum.all?(presentation_dialogues, fn dialogue ->
               MapSet.member?(connected_sources, dialogue["id"]) and
                 MapSet.member?(connected_targets, dialogue["id"])
             end)

      # The encrypted, unmaterialized plan retains bounded review metadata so
      # a user can revise a decision without reparsing the uploaded file.
      assert Enum.count(flow["nodes"], fn node ->
               is_binary(node["data"]["import_yarn_speaker"])
             end) == 10

      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, preview} = Imports.preview(project.id, plan)
      assert preview.import_review == review
    end

    test "treats paired-scope evidence as an editable suggestion, never semantic authority" do
      source = """
      title: Start
      ---
      <<clear_cutscene>>
      <<start_cutscene>>
      CutsceneCamera: pan-left
      CutsceneOverlay: fade-in
      Alice: We made it.
      CutsceneNarrator: Inside the cutscene.
      <<end_cutscene>>
      CutsceneNarrator: Outside the cutscene.
      <<start_cutscene>>
      CutsceneCamera: pan-right
      CutsceneOverlay: fade-out
      <<end_cutscene>>
      <<start_fx>>
      FxNarrator: A lone matching name is not enough evidence.
      <<end_fx>>
      <<start_slide>>
      SlideOnly: An unmatched opener is not evidence.
      ===
      """

      assert {:ok, plan} = Imports.parse_file("custom-presenter.yarn", source)

      sheet_names = plan.data["sheets"] |> Enum.map(& &1["name"]) |> Enum.sort()

      assert sheet_names == ["Alice", "CutsceneNarrator", "FxNarrator", "SlideOnly"]
      refute "CutsceneCamera" in sheet_names
      refute "CutsceneOverlay" in sheet_names

      assert Enum.find(
               plan.data["import_review"]["speaker_decisions"],
               &(&1["speaker"] == "FxNarrator")
             )["suggested_action"] == "create_sheet"

      decisions =
        plan.data["import_review"]
        |> selected_suggestions()
        |> Enum.map(fn
          %{"speaker" => "CutsceneCamera"} = decision ->
            Map.put(decision, "action", "create_sheet")

          decision ->
            decision
        end)

      assert {:ok, resolved_plan} = ReviewDecisions.apply(plan, true, decisions)

      resolved_sheet_names =
        resolved_plan.data["sheets"] |> Enum.map(& &1["name"]) |> Enum.sort()

      assert "CutsceneCamera" in resolved_sheet_names
      refute "CutsceneOverlay" in resolved_sheet_names

      [flow] = resolved_plan.data["flows"]

      assert Enum.count(flow["nodes"], fn node ->
               node["type"] == "dialogue" and
                 node["data"]["speaker_sheet_id"] ==
                   Enum.find(resolved_plan.data["sheets"], &(&1["name"] == "CutsceneCamera"))["id"]
             end) == 2

      assert flow["nodes"]
             |> Enum.filter(fn node ->
               node["type"] == "dialogue" and
                 node["data"]["speaker_sheet_id"] == nil and
                 String.starts_with?(node["data"]["text"], "CutsceneOverlay:")
             end)
             |> Enum.map(& &1["data"]["text"]) == [
               "CutsceneOverlay: fade-in",
               "CutsceneOverlay: fade-out"
             ]
    end

    test "requires presentation lifecycle evidence and repeated regions per candidate" do
      without_clear = """
      title: Start
      ---
      <<start_slide>>
      SlideHeader: First
      SlideImage: first.png
      <<end_slide>>
      <<start_slide>>
      SlideHeader: Second
      SlideImage: second.png
      <<end_slide>>
      ===
      """

      assert {:ok, unclassified_plan} =
               Imports.parse_file("no-presentation-lifecycle.yarn", without_clear)

      assert unclassified_plan.metadata.presentation_channel_count == 0

      assert unclassified_plan.data["sheets"]
             |> Enum.map(& &1["name"])
             |> Enum.sort() == ["SlideHeader", "SlideImage"]

      assert unclassified_plan.data["import_review"]["requires_acknowledgement"] == true

      assert Enum.all?(
               unclassified_plan.data["import_review"]["speaker_decisions"],
               &(&1["suggested_action"] == "create_sheet" and &1["confidence"] == "medium")
             )

      with_clear = """
      title: Start
      ---
      <<clear_slide>>
      <<start_slide>>
      SlideHeader: First
      SlideImage: first.png
      SlideMayor: This is a real character.
      <<end_slide>>
      <<start_slide>>
      SlideHeader: Second
      SlideImage: second.png
      <<end_slide>>
      ===
      """

      assert {:ok, classified_plan} =
               Imports.parse_file("presentation-lifecycle.yarn", with_clear)

      assert classified_plan.metadata.presentation_channel_count == 2
      assert Enum.map(classified_plan.data["sheets"], & &1["name"]) == ["SlideMayor"]

      review = classified_plan.data["import_review"]
      assert review["preserved_channel_count"] == 2
      assert review["sheet_speaker_count"] == 1
      assert review["requires_acknowledgement"] == true

      assert Enum.find(review["speaker_decisions"], &(&1["speaker"] == "SlideMayor"))[
               "suggested_action"
             ] == "create_sheet"

      override =
        Enum.map(selected_suggestions(review), fn decision ->
          Map.put(decision, "action", "create_sheet")
        end)

      assert {:ok, resolved_plan} = ReviewDecisions.apply(classified_plan, true, override)

      assert resolved_plan.data["sheets"]
             |> Enum.map(& &1["name"])
             |> Enum.sort() == ["SlideHeader", "SlideImage", "SlideMayor"]

      [resolved_flow] = resolved_plan.data["flows"]

      assert Enum.all?(resolved_flow["nodes"], fn node ->
               node["type"] != "dialogue" or
                 not String.starts_with?(node["data"]["text"], ["SlideHeader:", "SlideImage:"])
             end)
    end

    test "does not classify parameterized scopes or speaker lines followed by options" do
      source = """
      title: Start
      ---
      <<start_scene first>>
      SceneCamera: pan-left
      SceneOverlay: fade-in
      <<end_scene first>>
      <<start_scene second>>
      SceneCamera: pan-right
      SceneOverlay: fade-out
      <<end_scene second>>
      <<start_ui>>
      UiHeader: Choose
      UiImage: portrait
      UiPrompt: Pick one
      -> Continue
      <<end_ui>>
      <<clear_ui>>
      <<start_ui>>
      UiHeader: Again
      UiImage: portrait-2
      UiPrompt: Pick another
      -> Stop
      <<end_ui>>
      ===
      """

      assert {:ok, plan} = Imports.parse_file("ambiguous-presenters.yarn", source)

      sheet_names = plan.data["sheets"] |> Enum.map(& &1["name"]) |> Enum.sort()

      assert "SceneCamera" in sheet_names
      assert "SceneOverlay" in sheet_names
      assert "UiPrompt" in sheet_names
      refute "UiHeader" in sheet_names
      refute "UiImage" in sheet_names
      assert plan.metadata.presentation_channel_count == 2

      assert Enum.find(
               plan.data["import_review"]["speaker_decisions"],
               &(&1["speaker"] == "UiPrompt")
             )["suggested_action"] == "create_sheet"

      decisions =
        plan.data["import_review"]
        |> selected_suggestions()
        |> Enum.map(fn
          %{"speaker" => "UiPrompt"} = decision ->
            Map.put(decision, "action", "preserve_literal")

          decision ->
            decision
        end)

      assert {:ok, resolved_plan} = ReviewDecisions.apply(plan, true, decisions)

      [flow] = resolved_plan.data["flows"]

      presentation_texts =
        flow["nodes"]
        |> Enum.filter(fn node ->
          node["type"] == "dialogue" and
            node["data"]["speaker_sheet_id"] == nil and
            String.starts_with?(node["data"]["text"], ["UiHeader:", "UiImage:"])
        end)
        |> Enum.map(& &1["data"]["text"])

      assert presentation_texts == [
               "UiHeader: Choose",
               "UiImage: portrait",
               "UiHeader: Again",
               "UiImage: portrait-2"
             ]

      assert Enum.count(flow["nodes"], fn node ->
               node["type"] == "dialogue" and
                 node["data"]["text"] == "UiPrompt: Pick one" and
                 length(node["data"]["responses"]) == 1 and
                 node["data"]["speaker_sheet_id"] == nil
             end) == 1

      assert Enum.count(flow["nodes"], fn node ->
               node["type"] == "dialogue" and
                 node["data"]["text"] == "UiPrompt: Pick another" and
                 length(node["data"]["responses"]) == 1 and
                 node["data"]["speaker_sheet_id"] == nil
             end) == 1
    end

    test "does not suggest merging equally frequent adjacent-transposition names" do
      source = """
      title: Start
      ---
      Brian: Keep us separate.
      Brain: This may be an intentional name.
      ===
      """

      assert {:ok, plan} = Imports.parse_file("similar-names.yarn", source)

      assert plan.data["sheets"]
             |> Enum.map(& &1["name"])
             |> Enum.sort() == ["Brain", "Brian"]

      assert plan.data["import_review"]["possible_speaker_aliases"] == []
      refute Enum.any?(plan.issues, &(&1.code == :possible_yarn_speaker_alias))
    end

    test "flags distinct NFKC-casefold speaker variants for explicit review without merging them" do
      source = """
      title: Start
      ---
      Alice: First.
      Alice: Second.
      ALICE: Third.
      Ａlice: Fourth.
      ===
      """

      assert {:ok, plan} = Imports.parse_file("case-variants.yarn", source)

      assert plan.data["sheets"]
             |> Enum.map(& &1["name"])
             |> Enum.sort() == ["ALICE", "Alice", "Ａlice"]

      aliases = plan.data["import_review"]["possible_speaker_aliases"]

      assert Enum.map(aliases, & &1["right"]) == ["ALICE", "Ａlice"]

      assert Enum.all?(aliases, fn alias_review ->
               alias_review["decision"] == "review" and
                 alias_review["evidence"] == "same_nfkc_casefold" and
                 alias_review["left"] == "Alice" and
                 alias_review["left_occurrences"] == 2 and
                 alias_review["right_occurrences"] == 1 and
                 alias_review["more_frequent"] == "Alice" and
                 alias_review["less_frequent"] == alias_review["right"]
             end)

      assert plan.metadata.possible_speaker_alias_count == 2
      assert Enum.count(plan.issues, &(&1.code == :possible_yarn_speaker_alias)) == 2
    end

    test "bounds speaker review details while reporting the complete total" do
      lines =
        Enum.map_join(1..1_001, "\n", fn index ->
          "Speaker#{String.pad_leading(Integer.to_string(index), 4, "0")}: Line"
        end)

      source = """
      title: Start
      ---
      #{lines}
      ===
      """

      assert {:ok, plan} = Imports.parse_file("many-speakers.yarn", source)

      review = plan.data["import_review"]
      assert review["speaker_decision_count"] == 1_001
      assert review["speaker_decisions_truncated"] == true
      assert length(review["speaker_decisions"]) == 1_000
      assert review["sheet_speaker_count"] == 1_001
      assert review["preserved_channel_count"] == 0
      assert review["possible_speaker_alias_count"] == 0
      assert review["possible_speaker_aliases_truncated"] == false
      assert review["requires_acknowledgement"] == true

      assert {:error, :import_review_too_large} =
               ReviewDecisions.apply(plan, true, selected_suggestions(review))
    end

    test "requires acknowledgement for channels outside the truncated review details" do
      ordinary_speakers =
        Enum.map_join(1..1_000, "\n", fn index ->
          "Speaker#{String.pad_leading(Integer.to_string(index), 4, "0")}: Line"
        end)

      source = """
      title: Start
      ---
      #{ordinary_speakers}
      <<clear_zulu>>
      <<start_zulu>>
      ZuluCamera: first
      ZuluImage: first.png
      <<end_zulu>>
      <<start_zulu>>
      ZuluCamera: second
      ZuluImage: second.png
      <<end_zulu>>
      ===
      """

      assert {:ok, plan} = Imports.parse_file("truncated-channel-review.yarn", source)

      review = plan.data["import_review"]
      assert review["speaker_decision_count"] == 1_002
      assert review["speaker_decisions_truncated"] == true
      assert length(review["speaker_decisions"]) == 1_000

      assert review["speaker_decisions"]
             |> Enum.take(2)
             |> Enum.map(& &1["speaker"]) == ["ZuluCamera", "ZuluImage"]

      assert Enum.count(
               review["speaker_decisions"],
               &(&1["suggested_action"] == "preserve_literal")
             ) == 2

      assert review["sheet_speaker_count"] == 1_000
      assert review["preserved_channel_count"] == 2
      assert review["requires_acknowledgement"] == true
    end

    test "bounds alias analysis work and blocks incomplete review" do
      lines =
        Enum.map_join(1..5_000, "\n", fn index ->
          suffix = String.pad_leading(Integer.to_string(index), 4, "0")
          "ExtremelyLongUniqueSpeakerNameForAliasBudget#{suffix}: Line"
        end)

      source = """
      title: Start
      ---
      #{lines}
      ===
      """

      assert {:ok, plan} = Imports.parse_file("alias-budget.yarn", source)

      review = plan.data["import_review"]
      assert review["possible_speaker_aliases_truncated"] == true

      assert {:error, :import_review_too_large} =
               ReviewDecisions.apply(plan, true, selected_suggestions(review))
    end

    test "does not leak an empty paired scope into following dialogue" do
      source = """
      title: Start
      ---
      <<start_scene>>
      <<end_scene>>
      SceneCamera: A real speaker after the empty region.
      SceneOverlay: Another real speaker after the empty region.
      <<start_scene>>
      <<end_scene>>
      ===
      """

      assert {:ok, plan} = Imports.parse_file("empty-scopes.yarn", source)

      assert plan.data["sheets"]
             |> Enum.map(& &1["name"])
             |> Enum.sort() == ["SceneCamera", "SceneOverlay"]

      assert plan.metadata.presentation_channel_count == 0
    end

    test "retains unsupported commands as annotations and safe warning codes" do
      source = """
      title: Start
      ---
      <<camera focus SecretCharacterName>>
      Hello
      ===
      """

      assert {:ok, plan} = Imports.parse_file("private-character-name.yarn", source)

      assert Enum.any?(plan.issues, &(&1.code == :unsupported_yarn_command))
      assert Enum.all?(plan.issues, &(&1.source == "source_1"))
      refute inspect(plan.issues) =~ "private-character-name"
      refute inspect(plan.issues) =~ "SecretCharacterName"

      review = plan.data["import_review"]
      assert review["compatibility_warning_count"] == 1
      assert review["compatibility_warning_counts_by_code"] == %{"unsupported_yarn_command" => 1}
      assert review["requires_acknowledgement"] == true

      [flow] = plan.data["flows"]
      annotation = Enum.find(flow["nodes"], &(&1["type"] == "annotation"))
      dialogue = Enum.find(flow["nodes"], &(&1["type"] == "dialogue"))
      assert annotation["data"]["text"] =~ "<<camera focus SecretCharacterName>>"

      refute Enum.any?(flow["connections"], fn connection ->
               annotation["id"] in [connection["source_node_id"], connection["target_node_id"]]
             end)

      assert Enum.any?(flow["connections"], &(&1["target_node_id"] == dialogue["id"]))
      assert Enum.any?(flow["connections"], &(&1["source_node_id"] == dialogue["id"]))
    end

    test "keeps logical operator words inside string literals" do
      source = """
      title: Start
      ---
      <<declare $name = "Tom and Jerry">>
      <<if $name == "Tom and Jerry">>
        Hello
      <<endif>>
      ===
      """

      assert {:ok, plan} = Imports.parse_file("project.yarn", source)
      refute ImportPlan.error?(plan)

      [flow] = plan.data["flows"]
      condition = Enum.find(flow["nodes"], &(&1["type"] == "condition"))["data"]["condition"]
      [rule] = condition["blocks"] |> List.first() |> Map.fetch!("rules")
      assert rule["value"] == "Tom and Jerry"
    end

    test "supports compact symbolic boolean operators without splitting string literals" do
      source = """
      title: Start
      ---
      <<declare $first = true>>
      <<declare $second = false>>
      <<declare $label = "first&&second||third">>
      <<if $first&&$second>>
        Both
      <<elseif $first||$second>>
        Either
      <<elseif $label == "first&&second||third">>
        Literal
      <<endif>>
      ===
      """

      assert {:ok, plan} = Imports.parse_file("project.yarn", source)
      refute ImportPlan.error?(plan)

      [flow] = plan.data["flows"]

      # One switch node now carries the three cases, each keeping the logic its
      # own operator implies: `&&` is all, `||` is any, and the `&&`/`||` inside
      # the string literal is still not treated as an operator.
      [condition] = Enum.filter(flow["nodes"], &(&1["type"] == "condition"))

      assert Enum.map(condition["data"]["condition"]["blocks"], & &1["logic"]) == ["all", "any", "all"]
    end

    test "rejects symbolic boolean operators with an empty operand" do
      Enum.each(["$flag&&", "&&$flag", "$flag||", "||$flag"], fn condition ->
        source = """
        title: Start
        ---
        <<declare $flag = true>>
        <<if #{condition}>>
          Hidden
        <<endif>>
        ===
        """

        assert {:ok, plan} = raw_yarn_plan(source)
        assert Enum.any?(plan.issues, &(&1.code == :unsupported_yarn_condition))
        assert {:error, :import_plan_has_errors} = Imports.parse_file("project.yarn", source)
      end)
    end

    test "does not split boolean operator words embedded in variable names" do
      source = """
      title: Start
      ---
      <<declare $candy = true>>
      <<declare $origin = false>>
      <<if $candy>>
        Candy
      <<elseif $origin>>
        Origin
      <<endif>>
      ===
      """

      assert {:ok, plan} = Imports.parse_file("project.yarn", source)
      [flow] = plan.data["flows"]

      # The elseif chain compiles to a single switch node, so the two cases are
      # blocks of one condition rather than two separate condition nodes.
      [condition] = Enum.filter(flow["nodes"], &(&1["type"] == "condition"))

      variables =
        Enum.map(condition["data"]["condition"]["blocks"], fn block ->
          [rule] = Map.fetch!(block, "rules")
          rule["variable"]
        end)

      assert variables == ["candy", "origin"]
    end

    test "normalizes symbolic boolean negation" do
      source = """
      title: Start
      ---
      <<declare $flag = false>>
      <<if !$flag>>
        Visible
      <<endif>>
      ===
      """

      assert {:ok, plan} = Imports.parse_file("project.yarn", source)
      [flow] = plan.data["flows"]
      condition = Enum.find(flow["nodes"], &(&1["type"] == "condition"))["data"]["condition"]
      [rule] = condition["blocks"] |> List.first() |> Map.fetch!("rules")
      assert rule["operator"] == "is_false"
      assert rule["variable"] == "flag"
    end

    test "rejects unsupported block conditions and keeps their fallback closed" do
      source = """
      title: Start
      ---
      <<if visited("SecretNode")>>
        Hidden branch
      <<endif>>
      ===
      """

      assert {:ok, plan} = raw_yarn_plan(source)

      assert Enum.any?(plan.issues, fn issue ->
               issue.code == :unsupported_yarn_condition and issue.severity == :error
             end)

      [flow] = plan.data["flows"]
      condition = Enum.find(flow["nodes"], &(&1["type"] == "condition"))["data"]["condition"]
      assert {false, [_rule]} = ConditionEval.evaluate(condition, %{})
      refute inspect(plan.issues) =~ "SecretNode"

      assert {:error, :import_plan_has_errors} = Imports.parse_file("project.yarn", source)
    end

    test "rejects unsupported option conditions instead of making the option unconditional" do
      source = """
      title: Start
      ---
      Choose
      -> Secret <<if visited("Vault")>>
      -> Public
      ===
      """

      assert {:ok, plan} = raw_yarn_plan(source)
      assert Enum.any?(plan.issues, &(&1.code == :unsupported_yarn_condition and &1.severity == :error))

      [flow] = plan.data["flows"]
      dialogue = Enum.find(flow["nodes"], &(&1["type"] == "dialogue"))
      secret = Enum.find(dialogue["data"]["responses"], &(&1["text"] == "Secret"))
      assert {false, [_rule]} = ConditionEval.evaluate_string(secret["condition"], %{})

      assert {:error, :import_plan_has_errors} = Imports.parse_file("project.yarn", source)
    end

    test "rejects Yarn 3 smart variables instead of silently converting them" do
      source = """
      title: Start
      ---
      <<declare $strength = 60>>
      <<declare $magic = 20>>
      <<declare $is_powerful = $strength > 50 && $magic >= 20>>
      Powerful: {$is_powerful}
      ===
      """

      assert {:ok, plan} = raw_yarn_plan(source)

      assert Enum.any?(plan.issues, fn issue ->
               issue.code == :unsupported_yarn_declaration and issue.severity == :error
             end)

      refute inspect(plan.issues) =~ "$strength > 50"
      assert {:error, :import_plan_has_errors} = Imports.parse_file("project.yarn", source)
    end

    test "rejects Yarn 3 line groups instead of importing every alternative in sequence" do
      source = """
      title: Start
      ---
      => Guide: First greeting
      => Guide: Alternate greeting
      ===
      """

      assert {:ok, plan} = raw_yarn_plan(source)

      assert Enum.any?(plan.issues, fn issue ->
               issue.code == :unsupported_yarn_line_group and issue.severity == :error
             end)

      assert plan.metadata.error_count == 2
      assert {:error, :import_plan_has_errors} = Imports.parse_file("project.yarn", source)
    end

    test "rejects Yarn node conditions even when the title is unique" do
      source = """
      title: Candidate
      when: $met_guide
      ---
      Conditional dialogue
      ===
      """

      assert {:ok, plan} = raw_yarn_plan(source)

      assert Enum.any?(plan.issues, fn issue ->
               issue.code == :unsupported_yarn_node_condition and issue.severity == :error
             end)

      assert plan.metadata.error_count == 1
      assert {:error, :import_plan_has_errors} = Imports.parse_file("project.yarn", source)
    end

    test "rejects once blocks instead of weakening their stateful control flow" do
      source = """
      title: Start
      ---
      <<once>>
        This should only appear once.
      <<endonce>>
      ===
      """

      assert {:ok, plan} = raw_yarn_plan(source)

      assert Enum.count(plan.issues, fn issue ->
               issue.code == :unsupported_yarn_control_command and issue.severity == :error
             end) == 2

      assert plan.metadata.error_count == 2
      assert {:error, :import_plan_has_errors} = Imports.parse_file("project.yarn", source)
    end

    test "rejects inline once modifiers on dialogue and options" do
      source = """
      title: Start
      ---
      Guide: This should only appear once. <<once>>
      -> Conditional option <<once if $flag>>
      ===
      """

      assert {:ok, plan} = raw_yarn_plan(source)

      assert Enum.count(plan.issues, fn issue ->
               issue.code == :unsupported_yarn_control_command and issue.severity == :error
             end) == 2

      assert plan.metadata.error_count == 2
      assert {:error, :import_plan_has_errors} = Imports.parse_file("project.yarn", source)
    end

    test "warns when a dynamic speaker cannot be linked to a character sheet" do
      source = """
      title: Start
      ---
      <<declare $speaker = "Guide">>
      {$speaker}: Hello
      ===
      """

      assert {:ok, plan} = Imports.parse_file("project.yarn", source)

      assert Enum.any?(plan.issues, fn issue ->
               issue.code == :dynamic_yarn_speaker and issue.severity == :warning
             end)

      assert plan.metadata.warning_count == 1
      review = plan.data["import_review"]

      assert [
               %{
                 "speaker" => "{$speaker}",
                 "suggested_action" => "preserve_literal",
                 "confidence" => "high",
                 "reasons" => ["dynamic_speaker_expression"]
               }
             ] = review["speaker_decisions"]

      assert review["requires_acknowledgement"] == true
      refute Enum.any?(plan.data["sheets"], &(&1["name"] == "{$speaker}"))

      [flow] = plan.data["flows"]
      dialogue = Enum.find(flow["nodes"], &(&1["type"] == "dialogue"))
      assert dialogue["data"]["speaker_sheet_id"] == nil
      assert dialogue["data"]["text"] == "Hello"

      assert {:ok, resolved_plan} =
               ReviewDecisions.apply(plan, true, [
                 %{"speaker" => "{$speaker}", "action" => "preserve_literal"}
               ])

      [resolved_flow] = resolved_plan.data["flows"]
      resolved_dialogue = Enum.find(resolved_flow["nodes"], &(&1["type"] == "dialogue"))
      assert resolved_dialogue["data"]["speaker_sheet_id"] == nil
      assert resolved_dialogue["data"]["text"] == "{yarn.speaker}: Hello"

      assert {:error, :invalid_import_review_selection} =
               ReviewDecisions.apply(plan, true, [
                 %{"speaker" => "{$speaker}", "action" => "create_sheet"}
               ])
    end

    test "rejects unknown inline commands in dialogue and options" do
      source = """
      title: Start
      ---
      Guide: Wait here. <<wait 1>>
      -> Choose me <<custom_action>>
      ===
      """

      assert {:ok, plan} = raw_yarn_plan(source)

      assert Enum.count(plan.issues, fn issue ->
               issue.code == :unsupported_yarn_inline_command and issue.severity == :error
             end) == 2

      assert {:error, :import_plan_has_errors} = Imports.parse_file("project.yarn", source)
    end

    test "warns when dynamic interpolation, markup and tags remain for review" do
      source = """
      title: Start
      ---
      Alice: Roll {random_range(1, 10)} [emotion="angry" /] #shadow:original_line
      ===
      """

      assert {:ok, plan} = Imports.parse_file("project.yarn", source)

      warning_codes = ImportPlan.warning_codes(plan)
      assert :unsupported_yarn_interpolation in warning_codes
      assert :unsupported_yarn_markup in warning_codes
      assert :unsupported_yarn_tag in warning_codes
      assert plan.metadata.warning_count == 3

      review = plan.data["import_review"]
      assert review["compatibility_warning_count"] == 3

      assert review["compatibility_warning_counts_by_code"] == %{
               "unsupported_yarn_interpolation" => 1,
               "unsupported_yarn_markup" => 1,
               "unsupported_yarn_tag" => 1
             }

      assert review["requires_acknowledgement"] == true

      [flow] = plan.data["flows"]
      dialogue = Enum.find(flow["nodes"], &(&1["type"] == "dialogue"))
      assert dialogue["data"]["text"] =~ "{random_range(1, 10)}"
      assert dialogue["data"]["text"] =~ ~s([emotion="angry" /])
      assert dialogue["data"]["text"] =~ "#shadow:original_line"
    end

    test "blocks explicit Yarn character markup instead of guessing a static speaker" do
      source = """
      title: Start
      ---
      [character name="Alice"]Hello there.[/character]
      ===
      """

      assert {:ok, plan} = raw_yarn_plan(source)

      assert Enum.any?(plan.issues, fn issue ->
               issue.code == :unsupported_yarn_character_markup and
                 issue.severity == :error
             end)

      assert Enum.any?(plan.issues, fn issue ->
               issue.code == :unsupported_yarn_markup and
                 issue.severity == :warning
             end)

      refute inspect(plan.issues) =~ "Alice"

      assert {:error, :import_plan_has_errors} =
               Imports.parse_file("character-markup.yarn", source)
    end

    test "rejects assignments to undeclared variables whose type cannot be reproduced" do
      source = """
      title: Start
      ---
      <<set $score = 1>>
      <<set $score = $score + 1>>
      Alice: Score {$score}
      ===
      """

      assert {:ok, plan} = raw_yarn_plan(source)

      assert Enum.any?(plan.issues, fn issue ->
               issue.code == :undeclared_yarn_assignment_variable and issue.severity == :error
             end)

      assert {:error, :import_plan_has_errors} = Imports.parse_file("project.yarn", source)
    end

    test "rejects unsupported option-condition syntax instead of missing it" do
      source = """
      title: Start
      ---
      Choose
      -> Secret <<if $flag>> #custom-tag
      ===
      """

      assert {:ok, plan} = raw_yarn_plan(source)
      assert Enum.any?(plan.issues, &(&1.code == :unsupported_yarn_condition and &1.severity == :error))
      assert {:error, :import_plan_has_errors} = Imports.parse_file("project.yarn", source)
    end

    test "rejects conditional variables whose runtime value cannot be reproduced" do
      source = """
      title: Start
      ---
      <<if $external_flag>>
        Hidden
      <<endif>>
      ===
      """

      assert {:ok, plan} = raw_yarn_plan(source)

      assert Enum.any?(plan.issues, fn issue ->
               issue.code == :undeclared_yarn_condition_variable and issue.severity == :error
             end)

      assert {:error, :import_plan_has_errors} = Imports.parse_file("project.yarn", source)
    end

    test "does not let warning volume hide a later semantic error" do
      warnings = Enum.map_join(1..1_000, "\n", &"Value {$warning_#{&1}}")

      source = """
      title: Start
      ---
      #{warnings}
      <<if visited("SecretNode")>>
        Hidden
      <<endif>>
      ===
      """

      assert {:ok, plan} = raw_yarn_plan(source)
      assert length(plan.issues) == 1_000
      assert ImportPlan.error?(plan)
      assert Enum.any?(plan.issues, &(&1.code == :unsupported_yarn_condition))
      assert {:error, :import_plan_has_errors} = Imports.parse_file("project.yarn", source)
    end

    test "counts every normalization warning before retaining the bounded issue list" do
      commands = Enum.map_join(1..1_001, "\n", &"<<custom_command #{&1}>>")

      source = """
      title: Start
      ---
      #{commands}
      ===
      """

      assert {:ok, plan} = Imports.parse_file("project.yarn", source)

      assert length(plan.issues) == 1_000
      assert plan.metadata.warning_count == 1_001
      assert plan.metadata.error_count == 0
      assert plan.metadata.issue_count == 1_001
      assert plan.metadata.issues_truncated == true
      assert plan.metadata.issue_counts_by_code == %{unsupported_yarn_command: 1_001}

      review = plan.data["import_review"]
      assert review["compatibility_warning_count"] == 1_001
      assert review["compatibility_warning_counts_by_code"] == %{"unsupported_yarn_command" => 1_001}
      assert review["requires_acknowledgement"] == true
    end

    test "rejects malformed commands instead of treating them as annotations" do
      source = """
      title: Start
      ---
      <<if $flag
        Hidden
      ===
      """

      assert {:error, :invalid_yarn_command} = Imports.parse_file("project.yarn", source)
    end

    test "rejects parameters on parameterless built-in control commands" do
      Enum.each(["return unexpected", "stop unexpected"], fn command ->
        source = """
        title: Start
        ---
        <<#{command}>>
        Reachable only if the invalid command were weakened.
        ===
        """

        assert {:ok, plan} = raw_yarn_plan(source)

        assert Enum.any?(plan.issues, fn issue ->
                 issue.code == :unsupported_yarn_control_command and
                   issue.severity == :error
               end)

        assert {:error, :import_plan_has_errors} =
                 Imports.parse_file("project.yarn", source)
      end)
    end

    test "does not materialize dialogue after terminal commands" do
      sources = [
        """
        title: Start
        ---
        <<stop>>
        Unreachable
        ===
        """,
        """
        title: Start
        ---
        <<return>>
        Unreachable
        ===
        """,
        """
        title: Start
        ---
        <<jump End>>
        Unreachable
        ===
        title: End
        ---
        Done
        ===
        """
      ]

      Enum.each(sources, fn source ->
        assert {:ok, plan} = Imports.parse_file("project.yarn", source)

        refute Enum.any?(plan.data["flows"], fn flow ->
                 Enum.any?(flow["nodes"], fn node ->
                   node["type"] == "dialogue" and node["data"]["text"] == "Unreachable"
                 end)
               end)
      end)
    end

    test "does not materialize tails after condition or option branches all terminate" do
      source = """
      title: Start
      ---
      <<declare $flag = true>>
      <<if $flag>>
        <<stop>>
      <<else>>
        <<return>>
      <<endif>>
      Unreachable after conditional
      ===
      title: Choices
      ---
      Choose
      -> Stop
          <<stop>>
      -> Return
          <<return>>
      Unreachable after options
      ===
      """

      assert {:ok, plan} = Imports.parse_file("project.yarn", source)

      dialogue_texts =
        plan.data["flows"]
        |> Enum.flat_map(& &1["nodes"])
        |> Enum.filter(&(&1["type"] == "dialogue"))
        |> Enum.map(& &1["data"]["text"])

      refute "Unreachable after conditional" in dialogue_texts
      refute "Unreachable after options" in dialogue_texts
    end

    test "preserves Yarn blank and comment option-boundary indentation" do
      cases = [
        {"    \n", [["First", "Second"]]},
        {"\n", [["First"], ["Second"]]},
        {"    // indented comment\n", [["First", "Second"]]},
        {"// unindented comment\n", [["First"], ["Second"]]}
      ]

      Enum.each(cases, fn {separator, expected_response_groups} ->
        source =
          "title: Start\n---\nChoose\n-> First\n#{separator}    Branch line\n-> Second\n    Second line\n===\n"

        assert {:ok, plan} = Imports.parse_file("project.yarn", source)
        [flow] = plan.data["flows"]

        response_groups =
          flow["nodes"]
          |> Enum.filter(fn node -> node["type"] == "dialogue" and node["data"]["responses"] != [] end)
          |> Enum.map(fn node -> Enum.map(node["data"]["responses"], & &1["text"]) end)

        assert response_groups == expected_response_groups
      end)
    end

    test "rejects unsupported state changes and missing control-flow targets" do
      source = """
      title: Start
      ---
      <<declare $gold = 10>>
      <<set $gold to random()>>
      <<jump MissingNode>>
      ===
      """

      assert {:ok, plan} = raw_yarn_plan(source)
      error_codes = plan.issues |> Enum.filter(&(&1.severity == :error)) |> Enum.map(& &1.code)
      assert :unsupported_yarn_assignment in error_codes
      assert :unknown_yarn_jump_target in error_codes
      assert {:error, :import_plan_has_errors} = Imports.parse_file("project.yarn", source)
    end

    test "rejects duplicate Yarn node titles" do
      source = """
      title: Same
      ---
      First
      ===
      title: Same
      ---
      Second
      ===
      """

      assert {:error, :duplicate_yarn_node_title} = Imports.parse_file("project.yarn", source)
    end

    test "rejects Yarn titles and descriptions beyond native entity limits" do
      long_title = String.duplicate("T", 201)
      long_description = String.duplicate("D", 2_001)

      assert {:error, :yarn_node_title_too_long} =
               Imports.parse_file(
                 "long-title.yarn",
                 "title: #{long_title}\n---\nLine\n===\n"
               )

      assert {:error, :yarn_node_description_too_long} =
               Imports.parse_file(
                 "long-description.yarn",
                 "title: Start\ndescription: #{long_description}\n---\nLine\n===\n"
               )
    end

    test "treats a colon prefix longer than a plausible name as dialogue, not a speaker" do
      # The recognizer caps names at 60 chars, so a long clause before a colon
      # stays prose instead of becoming a character or failing the import.
      long_prefix = String.duplicate("S", 61)

      assert {:ok, plan} =
               Imports.parse_file(
                 "long-speaker.yarn",
                 "title: Start\n---\n#{long_prefix}: Hello\n===\n"
               )

      refute ImportPlan.error?(plan)
      assert plan.data["import_review"]["speaker_decisions"] == []
    end

    test "rejects malformed conditional blocks" do
      source = """
      title: Start
      ---
      <<if $flag>>
        Missing endif
      ===
      """

      assert {:error, :missing_yarn_endif} = Imports.parse_file("project.yarn", source)
    end

    test "keeps normalized flow shortcuts unique" do
      source = """
      title: A B
      ---
      First
      ===
      title: A-B
      ---
      Second
      ===
      """

      assert {:ok, plan} = Imports.parse_file("project.yarn", source)
      assert Enum.map(plan.data["flows"], & &1["shortcut"]) == ["a-b", "a-b-2"]
    end

    test "bounds generated shortcuts while reserving room for collision suffixes" do
      shared_prefix = String.duplicate("A", 199)

      source = """
      title: #{shared_prefix}X
      ---
      #{String.duplicate("S", 60)}: First
      ===
      title: #{shared_prefix}Y
      ---
      Second
      ===
      """

      assert {:ok, plan} = Imports.parse_file("long-shortcuts.yarn", source)

      flow_shortcuts = Enum.map(plan.data["flows"], & &1["shortcut"])
      assert Enum.map(flow_shortcuts, &String.length/1) == [50, 50]
      assert Enum.uniq(flow_shortcuts) == flow_shortcuts
      assert flow_shortcuts |> List.last() |> String.ends_with?("-2")

      speaker_sheet =
        Enum.find(plan.data["sheets"], fn sheet ->
          sheet["name"] == String.duplicate("S", 60)
        end)

      assert String.length(speaker_sheet["shortcut"]) == 50
    end

    test "a bound that cuts at a separator never emits a trailing separator" do
      # 49 chars + a space: shortcutified this is "a…a-bcd…", and the 50-char
      # cut lands exactly on the hyphen. The shortcut must stay valid for
      # `validate_shortcut` — materialization is too late to find out.
      name = String.duplicate("A", 49) <> " " <> String.duplicate("B", 10)

      source = """
      title: Start
      ---
      #{name}: Hello there
      ===
      """

      assert {:ok, plan} = Imports.parse_file("boundary.yarn", source)
      speaker_sheet = Enum.find(plan.data["sheets"], &(&1["name"] == name))

      assert speaker_sheet
      assert String.length(speaker_sheet["shortcut"]) <= 50
      assert speaker_sheet["shortcut"] =~ ~r/^[a-z0-9][a-z0-9.\-]*[a-z0-9]$|^[a-z0-9]$/
    end

    test "rejects Yarn documents with excessive statement counts before normalization" do
      lines = Enum.map_join(1..5_001, "\n", &"Dialogue line #{&1}")
      source = "title: Start\n---\n#{lines}\n===\n"

      assert {:error, :yarn_statement_limit_exceeded} =
               Imports.parse_file("project.yarn", source)
    end

    test "rejects excessive Yarn document counts during source preflight" do
      source =
        Enum.map_join(1..501, "\n", fn index ->
          "title: Node #{index}\n---\nLine\n==="
        end)

      assert {:error, :yarn_document_limit_exceeded} =
               Imports.parse_file("project.yarn", source)
    end

    test "rejects excessive total statements during source preflight" do
      source =
        Enum.map_join(1..21, "\n", fn document_index ->
          statement_count = if document_index == 21, do: 1, else: 5_000
          lines = Enum.map_join(1..statement_count, "\n", &"Line #{document_index}-#{&1}")
          "title: Node #{document_index}\n---\n#{lines}\n==="
        end)

      assert {:error, :yarn_statement_limit_exceeded} =
               Imports.parse_file("project.yarn", source)
    end

    test "counts every sibling option against the per-document budget" do
      options = Enum.map_join(1..5_001, "\n", &"-> Option #{&1}")

      source = "title: Start\n---\nChoose\n#{options}\n==="

      assert {:error, :yarn_statement_limit_exceeded} =
               Imports.parse_file("project.yarn", source)
    end

    test "bounds ignored and header lines before allocating parser line maps" do
      source = String.duplicate("\n", 125_001) <> "title: Start\n---\nHello\n==="

      assert {:error, :yarn_statement_limit_exceeded} =
               Imports.parse_file("project.yarn", source)
    end

    test "scans very long indentation without grapheme-list amplification" do
      source = "title: Start\n---\n" <> String.duplicate(" ", 50_000) <> "Hello\n==="

      assert {:ok, plan} = Imports.parse_file("project.yarn", source)
      refute ImportPlan.error?(plan)
    end

    test "rejects a single oversized line before regex and indentation parsing" do
      source = "title: Start\n---\n" <> String.duplicate(" ", 100_001) <> "Hello\n==="

      assert {:error, :yarn_statement_limit_exceeded} =
               Imports.parse_file("project.yarn", source)
    end
  end

  describe "graph shape" do
    @nested """
    title: Start
    ---
    Guide: One.
    Guide: Two.
    -> First
        Guide: Inside first.
        -> Deeper
            Guide: Bottom.
    -> Second
        Guide: Inside second.
    -> Third
        Guide: Inside third.
    Guide: After the choices.
    ===
    """

    test "converges branches onto the next node instead of emitting merge hubs" do
      assert {:ok, plan} = Imports.parse_file("project.yarn", @nested)
      refute ImportPlan.error?(plan)

      flow = Enum.find(plan.data["flows"], &(&1["name"] == "Start"))

      # A hub is a named jump target, not a join. Nothing in a Yarn import
      # creates one, so an unlabelled "0 jumps" hub must never appear.
      assert Enum.filter(flow["nodes"], &(&1["type"] == "hub")) == []

      after_choices =
        Enum.find(flow["nodes"], fn node ->
          node["type"] == "dialogue" and node["data"]["text"] == "After the choices."
        end)

      # Every branch tail lands directly on the node that follows the block.
      inbound =
        Enum.filter(flow["connections"], &(&1["target_node_id"] == after_choices["id"]))

      assert length(inbound) == 3
      assert Enum.all?(inbound, &(&1["target_pin"] == "input"))
      assert inbound |> Enum.map(& &1["source_node_id"]) |> Enum.uniq() |> length() == 3

      assert_valid_graph(flow)
    end

    test "places nodes in dependency order so no successor sits left of its source" do
      assert {:ok, plan} = Imports.parse_file("project.yarn", @nested)

      flow = Enum.find(plan.data["flows"], &(&1["name"] == "Start"))
      nodes_by_id = Map.new(flow["nodes"], &{&1["id"], &1})

      for connection <- flow["connections"] do
        source = Map.fetch!(nodes_by_id, connection["source_node_id"])
        target = Map.fetch!(nodes_by_id, connection["target_node_id"])

        assert target["position_x"] > source["position_x"],
               "#{target["type"]} at x=#{target["position_x"]} is not right of its source #{source["type"]} at x=#{source["position_x"]}"
      end
    end

    test "never overlaps two nodes on the canvas at their estimated rendered sizes" do
      # The canvas renders far larger boxes than the 190x130 placeholder — a
      # dialogue is 280-350px wide and grows with content — so disjointness is
      # asserted against the layout's own per-type estimates.
      assert {:ok, plan} = Imports.parse_file("project.yarn", @project)

      for flow <- plan.data["flows"], a <- flow["nodes"], b <- flow["nodes"], a["id"] < b["id"] do
        overlap_x =
          a["position_x"] < b["position_x"] + Layout.node_width(b) and
            b["position_x"] < a["position_x"] + Layout.node_width(a)

        overlap_y =
          a["position_y"] < b["position_y"] + Layout.node_height(b) and
            b["position_y"] < a["position_y"] + Layout.node_height(a)

        refute overlap_x and overlap_y,
               "#{a["type"]} and #{b["type"]} overlap in #{flow["name"]}"
      end
    end

    test "dialogue height estimates grow with text and wrapped response labels" do
      short = %{"type" => "dialogue", "data" => %{"text" => "Hi", "responses" => []}}

      long_text = %{
        "type" => "dialogue",
        "data" => %{"text" => String.duplicate("a", 150), "responses" => []}
      }

      assert Layout.node_height(long_text) > Layout.node_height(short)

      short_label = %{"type" => "dialogue", "data" => %{"text" => "Hi", "responses" => [%{"text" => "Ok"}]}}

      wrapped_label = %{
        "type" => "dialogue",
        "data" => %{"text" => "Hi", "responses" => [%{"text" => String.duplicate("b", 80)}]}
      }

      assert Layout.node_height(wrapped_label) > Layout.node_height(short_label)
    end

    test "newlines count as rendered lines in dialogue height estimates" do
      # The canvas preserves newlines (whitespace-pre-wrap), so six short
      # lines are six rendered lines even though they are few characters.
      multiline = %{
        "type" => "dialogue",
        "data" => %{"text" => String.duplicate("line\n", 6) <> "end", "responses" => []}
      }

      flat = %{
        "type" => "dialogue",
        "data" => %{"text" => String.duplicate("line ", 6) <> "end", "responses" => []}
      }

      assert Layout.node_height(multiline) > Layout.node_height(flat)
    end

    test "column stride follows the widest node of the column, not a fixed box" do
      # A dialogue-heavy column is 350px wide; the next column must start
      # beyond it plus the 120px layer gap, or real rendered nodes touch.
      assert {:ok, plan} = Imports.parse_file("project.yarn", @project)

      for flow <- plan.data["flows"] do
        columns =
          flow["nodes"]
          |> Enum.group_by(& &1["position_x"])
          |> Enum.sort_by(fn {x, _nodes} -> x end)

        columns
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.each(fn [{left_x, left_nodes}, {right_x, _right_nodes}] ->
          widest = left_nodes |> Enum.map(&Layout.node_width/1) |> Enum.max()

          assert right_x - left_x >= widest + 120.0,
                 "column at #{right_x} starts inside the #{widest}px column at #{left_x} in #{flow["name"]}"
        end)
      end
    end

    test "parks retained command annotations clear of the executable graph" do
      source = """
      title: Start
      ---
      <<disable Ghost>>
      Guide: Still here.
      ===
      """

      assert {:ok, plan} = Imports.parse_file("project.yarn", source)

      flow = Enum.find(plan.data["flows"], &(&1["name"] == "Start"))
      annotation = Enum.find(flow["nodes"], &(&1["type"] == "annotation"))
      graph_nodes = Enum.reject(flow["nodes"], &(&1["type"] == "annotation"))

      assert annotation["data"]["text"] =~ "<<disable Ghost>>"

      # Annotations are visual-only, so they carry no edges and must not be
      # dropped into a column the graph is using.
      graph_bottom = graph_nodes |> Enum.map(& &1["position_y"]) |> Enum.max()
      assert annotation["position_y"] > graph_bottom
    end
  end

  describe "elseif chains" do
    @switch """
    title: Start
    ---
    <<declare $rank = 0>>
    <<if $rank == 3>>
        Guide: Captain.
    <<elseif $rank == 2>>
        Guide: Mate.
    <<elseif $rank == 1>>
        Guide: Swab.
    <<else>>
        Guide: Stowaway.
    <<endif>>
    Guide: Move along.
    ===
    """

    test "compiles an elseif chain into one switch condition node" do
      assert {:ok, plan} = Imports.parse_file("project.yarn", @switch)
      refute ImportPlan.error?(plan)

      flow = Enum.find(plan.data["flows"], &(&1["name"] == "Start"))
      conditions = Enum.filter(flow["nodes"], &(&1["type"] == "condition"))

      # One switch node, not a chain of three boolean nodes.
      assert length(conditions) == 1
      [condition] = conditions
      assert condition["data"]["switch_mode"] == true

      blocks = condition["data"]["condition"]["blocks"]
      assert length(blocks) == 3

      # The block id doubles as the case's output pin, so ids must be distinct.
      ids = Enum.map(blocks, & &1["id"])
      assert Enum.uniq(ids) == ids

      # Cases stay in source order: the evaluator halts on the first match, so
      # order is semantics, not presentation.
      assert Enum.map(blocks, fn b -> b["rules"] |> hd() |> Map.fetch!("value") end) == ["3.0", "2.0", "1.0"]

      pins = Enum.map(ids, & &1) ++ ["default"]
      assert NodeConnectionRules.output_pins("condition", condition["data"]) == pins

      # Every case pin and the default are wired.
      connected =
        flow["connections"]
        |> Enum.filter(&(&1["source_node_id"] == condition["id"]))
        |> Enum.map(& &1["source_pin"])
        |> Enum.sort()

      assert connected == Enum.sort(pins)
      assert_valid_graph(flow)
    end

    test "keeps the boolean chain when a case condition is unsupported" do
      source = """
      title: Start
      ---
      <<declare $rank = 0>>
      <<if $rank == 1>>
          Guide: One.
      <<elseif visited("Somewhere")>>
          Guide: Two.
      <<endif>>
      ===
      """

      # An unsupported condition is always an error issue, so this plan can never
      # be imported. The fallback still has to produce a coherent graph: the plan
      # is built to report the issue, and a half-formed switch would crash the
      # preview instead of showing the user why the import was refused.
      assert {:error, :import_plan_has_errors} = Imports.parse_file("project.yarn", source)
      assert {:ok, plan} = raw_yarn_plan(source)
      assert Enum.any?(plan.issues, &(&1.code == :unsupported_yarn_condition))

      flow = Enum.find(plan.data["flows"], &(&1["name"] == "Start"))
      conditions = Enum.filter(flow["nodes"], &(&1["type"] == "condition"))

      assert length(conditions) == 2
      assert Enum.all?(conditions, &(&1["data"]["switch_mode"] == false))
      assert_valid_graph(flow)
    end

    test "still emits a boolean node for a lone if whose branches are not single lines" do
      # Two lines in a branch cannot become one response, so this keeps the
      # boolean condition node rather than folding.
      source = """
      title: Start
      ---
      <<declare $seen = false>>
      <<if $seen>>
          Guide: Again.
          Guide: As I was saying.
      <<else>>
          Guide: First.
      <<endif>>
      ===
      """

      assert {:ok, plan} = Imports.parse_file("project.yarn", source)

      flow = Enum.find(plan.data["flows"], &(&1["name"] == "Start"))
      [condition] = Enum.filter(flow["nodes"], &(&1["type"] == "condition"))

      assert condition["data"]["switch_mode"] == false
      assert NodeConnectionRules.output_pins("condition", condition["data"]) == ["true", "false"]
    end
  end

  describe "unreachable code" do
    test "imports a file with dead code after a terminal command, reporting it as a warning" do
      # The compiler drops what a `<<stop>>` makes unreachable, but the speaker
      # review is built from the AST. Counting a speaker the graph never gained
      # used to fail the whole import as a tampered review — for a file whose
      # only sin is dead code, which is normal in a script being rewritten.
      source = """
      title: Start
      ---
      Alice: Hello
      <<stop>>
      Bob: Dead code
      ===
      """

      assert {:ok, plan} = Imports.parse_file("dead.yarn", source)
      refute ImportPlan.error?(plan)
      assert plan.metadata.issue_counts_by_code == %{unreachable_yarn_code: 1}

      # Bob never reaches the review, so both halves agree and the import runs.
      assert Enum.map(plan.data["import_review"]["speaker_decisions"], & &1["speaker"]) == ["Alice"]

      assert {:ok, _resolved} =
               ReviewDecisions.apply(plan, true, [%{"speaker" => "Alice", "action" => "create_sheet"}])
    end

    test "prunes dead code inside option and conditional bodies" do
      source = """
      title: Start
      ---
      <<declare $seen = false>>
      -> Go
          Alice: Leaving.
          <<jump Elsewhere>>
          Bob: Never runs.
      -> Stay
          <<if $seen>>
              Alice: Again.
              <<stop>>
              Carol: Also never runs.
          <<endif>>
      ===

      title: Elsewhere
      ---
      Alice: Arrived.
      ===
      """

      assert {:ok, plan} = Imports.parse_file("dead.yarn", source)
      refute ImportPlan.error?(plan)
      assert plan.metadata.issue_counts_by_code == %{unreachable_yarn_code: 2}

      speakers = Enum.map(plan.data["import_review"]["speaker_decisions"], & &1["speaker"])
      refute "Bob" in speakers
      refute "Carol" in speakers

      assert {:ok, _resolved} =
               ReviewDecisions.apply(plan, true, [%{"speaker" => "Alice", "action" => "create_sheet"}])
    end

    test "recognizes multi-word speakers, matching shipped Yarn implementations" do
      # Regression guard: the strict `[^\s:]+` recognizer silently demoted
      # "Captain Reyes" to dialogue text — no sheet, no review entry — while
      # every shipped Yarn implementation reads the name up to the first colon.
      source = """
      title: Start
      ---
      Captain Reyes: Hold position.
      Old Man: The gate opens at dawn.
      Mae: Wow!
      ===
      """

      assert {:ok, plan} = Imports.parse_file("crew.yarn", source)
      refute ImportPlan.error?(plan)

      speakers = Enum.map(plan.data["import_review"]["speaker_decisions"], & &1["speaker"])
      assert "Captain Reyes" in speakers
      assert "Old Man" in speakers
      assert "Mae" in speakers

      sheet_names = Enum.map(plan.data["sheets"], & &1["name"])
      assert "Captain Reyes" in sheet_names

      captain = Enum.find(plan.data["sheets"], &(&1["name"] == "Captain Reyes"))
      assert captain["shortcut"] == "captain-reyes"
    end

    test "an escaped colon suppresses the speaker split and is unescaped in the text" do
      # Yarn 3.2+: `Mae\: Wow!` is a speakerless line reading "Mae: Wow!".
      source = """
      title: Start
      ---
      Mae\\: Wow!
      Alice: The odds are 3\\:1 against.
      ===
      """

      assert {:ok, plan} = Imports.parse_file("escapes.yarn", source)
      refute ImportPlan.error?(plan)

      speakers = Enum.map(plan.data["import_review"]["speaker_decisions"], & &1["speaker"])
      assert speakers == ["Alice"]

      flow = Enum.find(plan.data["flows"], &(&1["name"] == "Start"))
      texts = for node <- flow["nodes"], node["type"] == "dialogue", do: get_in(node, ["data", "text"])

      assert Enum.any?(texts, &(is_binary(&1) and &1 =~ "Mae: Wow!"))
      assert Enum.any?(texts, &(is_binary(&1) and &1 =~ "3:1 against"))
    end

    test "propagates terminality through an if/else whose branches all terminate" do
      # Dialogue after such a block used to be counted by the speaker review
      # but never wired into the graph; the halves disagreeing failed the
      # import as an unresolvable review.
      source = """
      title: Start
      ---
      <<declare $key = false>>
      <<if $key>>
          Alice: With key.
          <<jump Vault>>
      <<else>>
          Alice: Without key.
          <<stop>>
      <<endif>>
      Bob: Never reachable.
      ===

      title: Vault
      ---
      Alice: Inside.
      ===
      """

      assert {:ok, plan} = Imports.parse_file("terminal-if.yarn", source)
      refute ImportPlan.error?(plan)
      assert plan.metadata.issue_counts_by_code == %{unreachable_yarn_code: 1}

      speakers = Enum.map(plan.data["import_review"]["speaker_decisions"], & &1["speaker"])
      assert speakers == ["Alice"]

      assert {:ok, _resolved} =
               ReviewDecisions.apply(plan, true, [%{"speaker" => "Alice", "action" => "create_sheet"}])
    end

    test "propagates terminality through options whose bodies all terminate" do
      source = """
      title: Start
      ---
      -> Fight
          <<jump Battle>>
      -> Flee
          <<stop>>
      Carol: Never reachable.
      ===

      title: Battle
      ---
      Alice: Charge!
      ===
      """

      assert {:ok, plan} = Imports.parse_file("terminal-options.yarn", source)
      refute ImportPlan.error?(plan)
      assert plan.metadata.issue_counts_by_code == %{unreachable_yarn_code: 1}

      speakers = Enum.map(plan.data["import_review"]["speaker_decisions"], & &1["speaker"])
      refute "Carol" in speakers
    end

    test "a stop or return with arguments does not hide the content after it" do
      # `<<stop now>>` is not the zero-argument control command: it is already
      # reported as an error, and pruning after it would additionally hide
      # reachable content behind that already-reported problem.
      source = """
      title: Start
      ---
      Guide: Before.
      <<stop now>>
      Guide: After.
      ===
      """

      assert {:ok, parser} = ParserRegistry.parser_for("argstop.yarn")
      assert {:ok, bundle} = SourceBundle.open("argstop.yarn", source)
      assert {:ok, plan} = parser.parse(bundle)

      assert Enum.any?(plan.issues, &(&1.code == :unsupported_yarn_control_command))
      refute Enum.any?(plan.issues, &(&1.code == :unreachable_yarn_code))

      [flow] = plan.data["flows"]
      texts = for node <- flow["nodes"], node["type"] == "dialogue", do: node["data"]["text"]
      assert Enum.any?(texts, &(is_binary(&1) and &1 =~ "After."))
    end

    test "an if without an else falls through and keeps the tail" do
      source = """
      title: Start
      ---
      <<declare $key = false>>
      <<if $key>>
          Alice: With key.
          <<stop>>
      <<endif>>
      Bob: Reachable on the false path.
      ===
      """

      assert {:ok, plan} = Imports.parse_file("fallthrough.yarn", source)
      refute ImportPlan.error?(plan)
      assert plan.metadata.issue_counts_by_code == %{}

      speakers = Enum.map(plan.data["import_review"]["speaker_decisions"], & &1["speaker"])
      assert "Bob" in speakers
    end

    test "keeps declarations that sit after a terminal command" do
      # Yarn's declaration collection is flow-insensitive — the docs' "Setup
      # node" is a node of declares nobody ever runs. Pruning before collecting
      # ate the declaration and failed a valid project with
      # `undeclared_yarn_condition_variable`.
      source = """
      title: Setup
      ---
      <<jump Start>>
      <<declare $has_key = false>>
      ===

      title: Start
      ---
      <<if $has_key>>
          Alice: You have the key.
      <<endif>>
      ===
      """

      assert {:ok, plan} = Imports.parse_file("setup.yarn", source)
      refute ImportPlan.error?(plan)

      # The declaration takes effect; the dead statement is still reported as
      # discarded, matching the compiler's unreachable-code diagnostic.
      assert plan.metadata.issue_counts_by_code == %{unreachable_yarn_code: 1}

      variable_sheet = Enum.find(plan.data["sheets"], &(&1["shortcut"] == "yarn"))
      assert Enum.map(variable_sheet["blocks"], & &1["variable_name"]) == ["has_key"]
    end
  end

  describe "variable naming" do
    test "rejects two distinct declarations that normalize onto one identifier" do
      # $hasClueA and $has_clue_a both variablify to has_clue_a. References
      # cannot disambiguate them after normalization, so merging silently
      # fuses two distinct states — the import must refuse instead.
      source = """
      title: Start
      ---
      <<declare $hasClueA = false>>
      <<declare $has_clue_a = 0>>
      Guide: Hello.
      ===
      """

      assert {:error, :import_plan_has_errors} = Imports.parse_file("collision.yarn", source)
    end

    test "rejects a declaration whose name has no usable characters" do
      # variablify("_") is "" — persisting an empty variable_name passes the
      # preview and aborts materialization, the worst place to find out.
      source = """
      title: Start
      ---
      <<declare $_ = 1>>
      Guide: Hello.
      ===
      """

      assert {:error, :import_plan_has_errors} = Imports.parse_file("underscore.yarn", source)
    end

    test "rejects an interpolation whose name has no usable characters" do
      # `{$_}` matched the syntax, was dropped from reference collection, and
      # then materialized as the shared fallback variable — a dangling
      # reference the user never wrote.
      source = """
      title: Start
      ---
      Guide: You have {$_} coins.
      ===
      """

      assert {:error, :invalid_yarn_interpolation} = Imports.parse_file("underscore-ref.yarn", source)
    end

    test "tolerates re-declaring the same spelling twice" do
      source = """
      title: Start
      ---
      <<declare $gold = 10>>
      <<declare $gold = 10>>
      Guide: Hello.
      ===
      """

      assert {:ok, plan} = Imports.parse_file("redeclare.yarn", source)
      refute ImportPlan.error?(plan)
    end

    test "splits camelCase Yarn variables instead of flattening them" do
      source = """
      title: Start
      ---
      <<declare $hasClueA = false>>
      <<declare $spokenToLeftGrave = false>>
      <<declare $already_snake = 0>>
      Guide: Hello.
      <<if $hasClueA>>
          Guide: Clue found.
      <<endif>>
      ===
      """

      assert {:ok, plan} = Imports.parse_file("project.yarn", source)
      refute ImportPlan.error?(plan)

      variable_sheet = Enum.find(plan.data["sheets"], &(&1["shortcut"] == "yarn"))

      assert Enum.map(variable_sheet["blocks"], & &1["variable_name"]) == [
               "already_snake",
               "has_clue_a",
               "spoken_to_left_grave"
             ]

      # The author's own spelling stays as the human-facing label.
      labels = Map.new(variable_sheet["blocks"], &{&1["variable_name"], &1["config"]["label"]})
      assert labels["has_clue_a"] == "hasClueA"
      assert labels["spoken_to_left_grave"] == "spokenToLeftGrave"

      # Conditions must reference the same identifier the block declares.
      flow = Enum.find(plan.data["flows"], &(&1["name"] == "Start"))
      condition = Enum.find(flow["nodes"], &(&1["type"] == "condition"))
      rule = condition["data"]["condition"]["blocks"] |> hd() |> Map.fetch!("rules") |> hd()
      assert rule["variable"] == "has_clue_a"
    end
  end

  describe "choice blocks without a line of their own" do
    test "attributes the hosting node to the character speaking into it" do
      source = """
      title: Start
      ---
      <<declare $seen = false>>
      <<if not $seen>>
          Louise: First time?
          <<set $seen to true>>
      <<else>>
          Louise: Back again?
      <<endif>>

      -> Yes
          Louise: Good.
      -> No
          Louise: Shame.
      ===
      """

      assert {:ok, plan} = Imports.parse_file("project.yarn", source)
      refute ImportPlan.error?(plan)

      louise = Enum.find(plan.data["sheets"], &(&1["name"] == "Louise"))
      flow = Enum.find(plan.data["flows"], &(&1["name"] == "Start"))

      # Two text-less dialogue nodes exist here and they are different things:
      # the folded `<<if>>/<<else>>` line selection, whose responses all carry
      # conditions, and the player menu, whose responses carry none.
      host =
        Enum.find(flow["nodes"], fn node ->
          node["type"] == "dialogue" and node["data"]["text"] == "" and
            node["data"]["responses"] != [] and
            Enum.all?(node["data"]["responses"], &is_nil(&1["condition"]))
        end)

      assert Enum.map(host["data"]["responses"], & &1["text"]) == ["Yes", "No"]
      assert host["data"]["speaker_sheet_id"] == louise["id"]

      # The menu has no literal Yarn speaker prefix of its own, so it claims none.
      refute Map.has_key?(host["data"], "import_yarn_speaker")
    end
  end

  describe "semantic review decisions" do
    test "rejects missing, incomplete and tampered speaker mappings" do
      source = """
      title: Start
      ---
      Alice: Hello.
      SlideImage: portrait
      ===
      """

      assert {:ok, plan} = Imports.parse_file("review.yarn", source)
      review = plan.data["import_review"]
      decisions = selected_suggestions(review)

      assert {:error, :import_review_required} =
               ReviewDecisions.apply(plan, false, decisions)

      assert {:error, :import_review_required} =
               ReviewDecisions.apply(plan, true, Enum.drop(decisions, 1))

      tampered_review =
        update_in(review["speaker_decisions"], fn [first | rest] ->
          [Map.update!(first, "occurrences", &(&1 + 1)) | rest]
        end)

      tampered_plan = %{plan | data: Map.put(plan.data, "import_review", tampered_review)}

      assert {:error, :invalid_import_review} =
               ReviewDecisions.apply(tampered_plan, true, decisions)

      assert {:ok, resolved_plan} = ReviewDecisions.apply(plan, true, decisions)
      assert {:ok, ^resolved_plan} = ReviewDecisions.apply(resolved_plan, true, decisions)

      [first | rest] = decisions
      changed_action = if first["action"] == "create_sheet", do: "preserve_literal", else: "create_sheet"

      original_fingerprint =
        resolved_plan.data["import_review_resolution"]["decision_fingerprint"]

      assert {:ok, revised_plan} =
               ReviewDecisions.apply(
                 resolved_plan,
                 true,
                 [Map.put(first, "action", changed_action) | rest]
               )

      refute revised_plan.data["import_review_resolution"]["decision_fingerprint"] ==
               original_fingerprint

      assert ReviewDecisions.resolved?(revised_plan)
    end

    test "rejects legacy Yarn plans and malformed review structures" do
      assert {:ok, plan} =
               Imports.parse_file(
                 "review.yarn",
                 "title: Start\n---\nAlice: Hello.\n===\n"
               )

      decisions = selected_suggestions(plan.data["import_review"])

      assert {:error, :invalid_import_review} =
               ReviewDecisions.apply(%{plan | parser_version: "4"}, true, decisions)

      malformed_plan = %{plan | data: Map.delete(plan.data, "import_review")}

      assert {:error, :invalid_import_review} =
               ReviewDecisions.apply(malformed_plan, true, decisions)
    end
  end

  describe "execute/3" do
    test "materializes a Yarn plan atomically through the native importer" do
      user = user_fixture()
      project = project_fixture(user)

      assert {:ok, plan} = Imports.parse_file("dialogue.yarn", @project)

      assert {:ok, resolved_plan} =
               ReviewDecisions.apply(
                 plan,
                 true,
                 selected_suggestions(plan.data["import_review"])
               )

      assert {:ok, result} = Imports.execute(project, resolved_plan, conflict_strategy: :rename)

      assert length(result.flows) == 2
      assert length(result.sheets) == 2

      flows = Flows.list_flows(project.id)
      assert Enum.any?(flows, &(&1.name == "Start"))
      assert Enum.any?(flows, &(&1.name == "Ending"))

      start_flow = flows |> Enum.find(&(&1.name == "Start")) |> Repo.preload(:nodes)
      dialogue = Enum.find(start_flow.nodes, &(&1.type == "dialogue"))
      assert dialogue.word_count > 0
      assert dialogue.word_count == WordCount.for_node_data("dialogue", dialogue.data)

      refute Enum.any?(start_flow.nodes, fn node ->
               Enum.any?(Map.keys(node.data), &String.starts_with?(&1, "import_yarn_"))
             end)

      sheets = Sheets.list_all_sheets(project.id)
      assert Enum.any?(sheets, &(&1.shortcut == "yarn"))
      assert Enum.any?(sheets, &(&1.name == "Guide"))
    end

    test "refuses an unsafe plan through every public materialization entry point" do
      user = user_fixture()
      project = project_fixture(user)

      source = """
      title: Start
      ---
      <<if visited("SecretNode")>>
        Hidden
      <<endif>>
      ===
      """

      assert {:ok, plan} = raw_yarn_plan(source)
      assert ImportPlan.error?(plan)
      assert {:error, :import_plan_has_errors} = Imports.preview(project.id, plan)
      assert {:error, :import_plan_has_errors} = Imports.execute(project, plan, conflict_strategy: :rename)
      assert {:error, :import_plan_required} = Imports.preview(project.id, plan.data)
      assert {:error, :import_plan_required} = Imports.execute(project, plan.data, conflict_strategy: :rename)
      assert {:error, :import_plan_required} = Materializer.execute(project, plan.data)

      assert {:ok, :raw_materializer_rejected} =
               Repo.transact(fn ->
                 assert {:error, :import_plan_required} =
                          Materializer.materialize_in_transaction(project, plan.data)

                 {:ok, :raw_materializer_rejected}
               end)

      assert {:error, :import_plan_has_errors} = PlanStorage.store(project.id, plan)
      refute Enum.any?(Flows.list_flows(project.id), &(&1.name == "Start"))
    end
  end

  defp raw_yarn_plan(source) do
    with {:ok, parser} <- ParserRegistry.parser_for("project.yarn"),
         {:ok, bundle} <- SourceBundle.open("project.yarn", source) do
      parser.parse(bundle)
    end
  end

  defp selected_suggestions(review) do
    Enum.map(review["speaker_decisions"], fn decision ->
      %{
        "speaker" => decision["speaker"],
        "action" => decision["suggested_action"]
      }
    end)
  end

  defp assert_valid_graph(flow) do
    nodes = flow["nodes"]
    connections = flow["connections"]
    node_ids = Enum.map(nodes, & &1["id"])
    connection_ids = Enum.map(connections, & &1["id"])
    nodes_by_id = Map.new(nodes, &{&1["id"], &1})

    assert Enum.uniq(node_ids) == node_ids
    assert Enum.uniq(connection_ids) == connection_ids

    Enum.each(connections, fn connection ->
      source = Map.fetch!(nodes_by_id, connection["source_node_id"])
      target = Map.fetch!(nodes_by_id, connection["target_node_id"])

      assert NodeConnectionRules.valid_output_pin?(
               source["type"],
               source["data"],
               connection["source_pin"]
             )

      assert NodeConnectionRules.valid_input_pin?(
               target["type"],
               connection["target_pin"]
             )
    end)
  end
end
