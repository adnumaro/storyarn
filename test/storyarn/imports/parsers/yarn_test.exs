defmodule Storyarn.Imports.Parsers.YarnTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.Evaluator.ConditionEval
  alias Storyarn.Imports
  alias Storyarn.Imports.ImportPlan
  alias Storyarn.Imports.ParserRegistry
  alias Storyarn.Imports.Parsers.StoryarnJSON
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

      assert plan.parser_version == "3"
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

      [flow] = plan.data["flows"]
      annotation = Enum.find(flow["nodes"], &(&1["type"] == "annotation"))
      assert annotation["data"]["text"] =~ "<<camera focus SecretCharacterName>>"
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

      assert Enum.map(Enum.filter(flow["nodes"], &(&1["type"] == "condition")), fn node ->
               node["data"]["condition"]["logic"]
             end) == ["all", "any", "all"]
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

      variables =
        flow["nodes"]
        |> Enum.filter(&(&1["type"] == "condition"))
        |> Enum.map(fn node ->
          [rule] = node["data"]["condition"]["blocks"] |> List.first() |> Map.fetch!("rules")
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
      [flow] = plan.data["flows"]
      dialogue = Enum.find(flow["nodes"], &(&1["type"] == "dialogue"))
      assert dialogue["data"]["speaker_sheet_id"] == nil
      assert dialogue["data"]["text"] == "{yarn.speaker}: Hello"
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

      [flow] = plan.data["flows"]
      dialogue = Enum.find(flow["nodes"], &(&1["type"] == "dialogue"))
      assert dialogue["data"]["text"] =~ "{random_range(1, 10)}"
      assert dialogue["data"]["text"] =~ ~s([emotion="angry" /])
      assert dialogue["data"]["text"] =~ "#shadow:original_line"
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

  describe "execute/3" do
    test "materializes a Yarn plan atomically through the native importer" do
      user = user_fixture()
      project = project_fixture(user)

      assert {:ok, plan} = Imports.parse_file("dialogue.yarn", @project)
      assert {:ok, result} = Imports.execute(project, plan, conflict_strategy: :rename)

      assert length(result.flows) == 2
      assert length(result.sheets) == 2

      flows = Flows.list_flows(project.id)
      assert Enum.any?(flows, &(&1.name == "Start"))
      assert Enum.any?(flows, &(&1.name == "Ending"))

      start_flow = flows |> Enum.find(&(&1.name == "Start")) |> Repo.preload(:nodes)
      dialogue = Enum.find(start_flow.nodes, &(&1.type == "dialogue"))
      assert dialogue.word_count > 0
      assert dialogue.word_count == WordCount.for_node_data("dialogue", dialogue.data)

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
      assert {:error, :import_plan_required} = StoryarnJSON.execute(project, plan.data)

      assert {:ok, :raw_materializer_rejected} =
               Repo.transact(fn ->
                 assert {:error, :import_plan_required} =
                          StoryarnJSON.materialize_in_transaction(project, plan.data)

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
end
