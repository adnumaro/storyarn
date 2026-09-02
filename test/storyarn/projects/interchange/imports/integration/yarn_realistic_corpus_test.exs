defmodule Storyarn.Projects.Imports.YarnRealisticCorpusTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Projects.Imports
  alias Storyarn.Projects.Imports.ImportPlan
  alias Storyarn.Projects.Imports.Parsers.Yarn
  alias Storyarn.Projects.Imports.Parsers.Yarn.ReviewDecisions
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Test.YarnCompiler

  @fixture_root Path.expand("../../../../../fixtures/imports/yarn/space_journey", __DIR__)
  @archive_files ["SpaceJourney.yarnproject", "SpaceJourney_FinalVersion.yarn"]
  @upstream_file "upstream/SpaceJourney_FinalVersion.yarn"
  @expected_connection_shapes %{
    "Start" => %{
      {"dialogue", "output", "dialogue", "input"} => 3,
      {"dialogue", "response", "exit", "input"} => 3,
      {"entry", "output", "dialogue", "input"} => 1
    },
    "TalkToEngineer" => %{
      {"dialogue", "output", "dialogue", "input"} => 16,
      {"dialogue", "output", "exit", "input"} => 1,
      {"dialogue", "response", "dialogue", "input"} => 3,
      {"entry", "output", "dialogue", "input"} => 1
    },
    "TalkToCrewmate" => %{
      {"dialogue", "output", "dialogue", "input"} => 11,
      {"dialogue", "output", "exit", "input"} => 1,
      {"entry", "output", "dialogue", "input"} => 1
    },
    "TalkToCaptain" => %{
      {"dialogue", "output", "dialogue", "input"} => 35,
      {"dialogue", "output", "exit", "input"} => 1,
      {"dialogue", "output", "instruction", "input"} => 4,
      {"dialogue", "response", "dialogue", "input"} => 17,
      {"dialogue", "response", "instruction", "input"} => 1,
      {"entry", "output", "dialogue", "input"} => 1,
      {"instruction", "output", "dialogue", "input"} => 5
    },
    "BridgeEnding" => %{
      {"condition", "false", "dialogue", "input"} => 2,
      {"condition", "true", "dialogue", "input"} => 2,
      {"dialogue", "output", "condition", "input"} => 4,
      {"dialogue", "output", "dialogue", "input"} => 13,
      {"dialogue", "output", "exit", "input"} => 1,
      {"dialogue", "response", "dialogue", "input"} => 4,
      {"entry", "output", "dialogue", "input"} => 1
    }
  }

  test "pins the MIT source and keeps the importable adaptation reproducible" do
    manifest = fixture_json!("compatibility-manifest.json")

    assert manifest["upstream"] == %{
             "repository" => "https://github.com/YarnSpinnerTool/ExampleProjects",
             "revision" => "954b71207fbe6992fe188d1ab22f8b6330080a2b",
             "path" => "SpaceJourney/Assets/Dialogue/SpaceJourney_FinalVersion.yarn",
             "gitBlob" => "83f61dba31c9fbb24a62a270cbcc97ff3823a022",
             "license" => "MIT",
             "copyright" => "Copyright (c) 2021 Secret Lab Pty. Ltd."
           }

    assert fixture!("LICENSE.md") =~ "MIT License"
    assert fixture!("LICENSE.md") =~ "Copyright (c) 2021 Secret Lab Pty. Ltd."

    normalized_upstream = fixture!(@upstream_file)

    assert String.ends_with?(normalized_upstream, "\n")
    refute String.ends_with?(normalized_upstream, "\n\n")

    upstream_blob =
      <<0xEF, 0xBB, 0xBF>> <>
        binary_part(normalized_upstream, 0, byte_size(normalized_upstream) - 1)

    assert git_blob_sha(upstream_blob) == "83f61dba31c9fbb24a62a270cbcc97ff3823a022"
    assert git_blob_sha(upstream_blob) == manifest["upstream"]["gitBlob"]

    expected_adaptation =
      normalized_upstream
      |> String.replace(
        "title: Start\n---\n",
        "title: Start\n---\n" <>
          "<<declare $away_mission_readiness = 0>>\n" <>
          "<<declare $captain_is_friend = false>>\n",
        global: false
      )
      |> String.replace(
        "<<set $away_mission_readiness += 1>>",
        "<<set $away_mission_readiness to $away_mission_readiness + 1>>"
      )

    assert fixture!("SpaceJourney_FinalVersion.yarn") == expected_adaptation
    assert length(manifest["fixtureAdaptations"]) == 3

    accepted_semantics =
      Map.new(manifest["expectedSemantics"]["accepted"], &{&1["construct"], &1})

    assert accepted_semantics["start-choice-destinations"]["values"] == %{
             "Go and talk to the Captain" => "TalkToCaptain",
             "Go see the Engineer as per orders" => "TalkToEngineer",
             "Meet up with your friend" => "TalkToCrewmate"
           }

    assert accepted_semantics["bridge-condition-branches"]["values"] == %{
             "$away_mission_readiness < 2" => %{
               "false" => "Now's my chance! Take me to fight the pirates!",
               "true" => "Take me to fight the pirates! I was made for this!"
             },
             "$captain_is_friend" => %{
               "false" => "I'm sure somebody will miss you if you die.",
               "true" => "I'll miss you if you die... friend."
             }
           }

    assert accepted_semantics["assignments"]["count"] == 5
  end

  @tag :ysc_validation
  test "the adapted Space Journey source compiles with the official Yarn Spinner compiler" do
    source = fixture!("SpaceJourney_FinalVersion.yarn")

    assert YarnCompiler.valid?(source),
           "ysc rejected the adapted Space Journey fixture:\n#{inspect(YarnCompiler.validate(source))}"
  end

  test "the unadapted upstream fails closed with every incompatibility reported" do
    source = fixture!(@upstream_file)

    assert {:error, :import_plan_has_errors} =
             Imports.parse_file("SpaceJourney_FinalVersion.yarn", source)

    assert {:ok, bundle} = Yarn.open_source("SpaceJourney_FinalVersion.yarn", source)
    assert {:ok, %ImportPlan{} = plan} = Yarn.parse(bundle)

    assert Enum.frequencies_by(plan.issues, &{&1.severity, &1.code}) == %{
             {:error, :undeclared_yarn_condition_variable} => 2,
             {:error, :unsupported_yarn_assignment} => 3,
             {:warning, :unsupported_yarn_command} => 52
           }
  end

  test "the adapted project preserves its narrative graph and surfaces engine commands for review" do
    assert {:ok, %ImportPlan{} = plan} = realistic_plan()

    assert plan.source_kind == :archive
    assert plan.replace_eligible
    assert plan.metadata.error_count == 0
    assert plan.metadata.warning_count == 52

    assert Enum.frequencies_by(plan.issues, &{&1.severity, &1.code}) == %{
             {:warning, :unsupported_yarn_command} => 52
           }

    flows_by_name = Map.new(plan.data["flows"], &{&1["name"], &1})
    flows_by_id = Map.new(plan.data["flows"], &{&1["id"], &1["name"]})

    assert flows_by_name |> Map.keys() |> Enum.sort() ==
             ["BridgeEnding", "Start", "TalkToCaptain", "TalkToCrewmate", "TalkToEngineer"]

    assert flows_by_name["Start"]["is_main"]
    refute Enum.any?(plan.data["flows"], &(&1["name"] != "Start" and &1["is_main"]))

    assert flow_references(plan.data["flows"], flows_by_id) ==
             MapSet.new([
               {"Start", "TalkToCaptain"},
               {"Start", "TalkToCrewmate"},
               {"Start", "TalkToEngineer"},
               {"TalkToCaptain", "BridgeEnding"},
               {"TalkToCrewmate", "BridgeEnding"},
               {"TalkToEngineer", "BridgeEnding"}
             ])

    assert plan_connection_shapes(plan.data["flows"]) == @expected_connection_shapes

    start_choice =
      Enum.find(flows_by_name["Start"]["nodes"], fn node ->
        node["type"] == "dialogue" and node["data"]["text"] == "I wonder what I should do?"
      end)

    assert Enum.map(start_choice["data"]["responses"], & &1["text"]) == [
             "Go and talk to the Captain",
             "Go see the Engineer as per orders",
             "Meet up with your friend"
           ]

    assert plan_start_routes(flows_by_name["Start"], flows_by_id) == %{
             "Go and talk to the Captain" => "TalkToCaptain",
             "Go see the Engineer as per orders" => "TalkToEngineer",
             "Meet up with your friend" => "TalkToCrewmate"
           }

    assert plan_condition_routes(flows_by_name["BridgeEnding"]) == %{
             {"away_mission_readiness", "less_than", "2.0"} => %{
               "false" => "Now's my chance! Take me to fight the pirates!",
               "true" => "Take me to fight the pirates! I was made for this!"
             },
             {"captain_is_friend", "is_true", nil} => %{
               "false" => "I'm sure somebody will miss you if you die.",
               "true" => "I'll miss you if you die... friend."
             }
           }

    condition_rules = condition_rules(plan.data["flows"])

    assert assignment_frequencies(plan.data["flows"], & &1["nodes"]) == %{
             {"yarn", "away_mission_readiness", "add", "1.0"} => 3,
             {"yarn", "captain_is_friend", "set_false", nil} => 1,
             {"yarn", "captain_is_friend", "set_true", nil} => 1
           }

    assert Enum.any?(
             condition_rules,
             &match?(%{"variable" => "away_mission_readiness", "operator" => "less_than", "value" => "2.0"}, &1)
           )

    assert Enum.any?(condition_rules, &match?(%{"variable" => "captain_is_friend", "operator" => "is_true"}, &1))

    annotations =
      for flow <- plan.data["flows"],
          node <- flow["nodes"],
          node["type"] == "annotation",
          do: node["data"]["text"]

    assert length(annotations) == 52
    assert "Review imported Yarn Spinner command:\n<<camera Title>>" in annotations
    assert "Review imported Yarn Spinner command:\n<<expression Captain angry>>" in annotations

    review = plan.data["import_review"]
    assert review["requires_acknowledgement"]
    assert review["compatibility_warning_counts_by_code"] == %{"unsupported_yarn_command" => 52}
    assert Enum.any?(review["speaker_decisions"], &(&1["speaker"] == "Crewemate"))
  end

  test "materializes linked flows, variables, speakers and representative conditions" do
    user = user_fixture()
    project = project_fixture(user)

    assert {:ok, plan} = realistic_plan()
    assert {:ok, resolved_plan} = resolve_review(plan)
    assert {:ok, _result} = Imports.execute(project, resolved_plan, conflict_strategy: :rename)

    flows = Flows.list_flows(project.id)
    flows_by_name = Map.new(flows, &{&1.name, &1})
    flows_by_id = Map.new(flows, &{&1.id, &1.name})

    assert flows_by_name["Start"].is_main

    assert materialized_flow_references(flows, flows_by_id) ==
             MapSet.new([
               {"Start", "TalkToCaptain"},
               {"Start", "TalkToCrewmate"},
               {"Start", "TalkToEngineer"},
               {"TalkToCaptain", "BridgeEnding"},
               {"TalkToCrewmate", "BridgeEnding"},
               {"TalkToEngineer", "BridgeEnding"}
             ])

    assert materialized_connection_shapes(flows) == @expected_connection_shapes

    assert materialized_start_routes(flows_by_name["Start"], flows_by_id) == %{
             "Go and talk to the Captain" => "TalkToCaptain",
             "Go see the Engineer as per orders" => "TalkToEngineer",
             "Meet up with your friend" => "TalkToCrewmate"
           }

    start_nodes = Flows.list_nodes(flows_by_name["Start"].id)

    assert Enum.any?(start_nodes, fn node ->
             node.type == "dialogue" and node.data["text"] == "Another day in Space Fleet."
           end)

    assert Enum.any?(start_nodes, fn node ->
             node.type == "annotation" and node.data["text"] =~ "<<camera Title>>"
           end)

    ending_nodes = Flows.list_nodes(flows_by_name["BridgeEnding"].id)
    ending_rules = native_condition_rules(ending_nodes)

    assert assignment_frequencies(flows, fn flow ->
             flow.id
             |> Flows.list_nodes()
             |> Enum.map(&%{"type" => &1.type, "data" => &1.data})
           end) == %{
             {"yarn", "away_mission_readiness", "add", "1.0"} => 3,
             {"yarn", "captain_is_friend", "set_false", nil} => 1,
             {"yarn", "captain_is_friend", "set_true", nil} => 1
           }

    assert materialized_condition_routes(flows_by_name["BridgeEnding"], ending_nodes) == %{
             {"away_mission_readiness", "less_than", "2.0"} => %{
               "false" => "Now's my chance! Take me to fight the pirates!",
               "true" => "Take me to fight the pirates! I was made for this!"
             },
             {"captain_is_friend", "is_true", nil} => %{
               "false" => "I'm sure somebody will miss you if you die.",
               "true" => "I'll miss you if you die... friend."
             }
           }

    assert Enum.any?(
             ending_rules,
             &match?(%{"variable" => "away_mission_readiness", "operator" => "less_than", "value" => "2.0"}, &1)
           )

    assert Enum.any?(ending_rules, &match?(%{"variable" => "captain_is_friend", "operator" => "is_true"}, &1))

    variable_sheet = project.id |> Sheets.get_sheet_by_shortcut("yarn") |> Repo.preload(:blocks)

    assert Map.new(variable_sheet.blocks, &{&1.variable_name, {&1.type, &1.value}}) == %{
             "away_mission_readiness" => {"number", %{"content" => 0.0}},
             "captain_is_friend" => {"boolean", %{"content" => false}}
           }

    sheets_by_name = Map.new(Sheets.list_all_sheets(project.id), &{&1.name, &1})

    assert sheets_by_name
           |> Map.take(["Captain", "Crewmate", "Engineer", "Intercom", "Player"])
           |> map_size() == 5

    refute Map.has_key?(sheets_by_name, "Crewemate")

    crewmate_nodes = Flows.list_nodes(flows_by_name["TalkToCrewmate"].id)

    assert Enum.any?(crewmate_nodes, fn node ->
             node.type == "dialogue" and
               node.data["text"] == "Crewemate: Oh, fine. It's just beef-flavoured toothpaste, you know..." and
               is_nil(node.data["speaker_sheet_id"])
           end)

    captain_dialogue =
      Enum.find(ending_nodes, fn node ->
        node.type == "dialogue" and node.data["text"] == "We're totally doomed. It's the Space Pirates!"
      end)

    assert captain_dialogue.data["speaker_sheet_id"] == sheets_by_name["Captain"].id
  end

  defp realistic_plan do
    Imports.parse_file("space-journey.zip", fixture_archive())
  end

  defp resolve_review(plan) do
    decisions =
      Enum.map(plan.data["import_review"]["speaker_decisions"], fn decision ->
        action = if decision["speaker"] == "Crewemate", do: "preserve_literal", else: "create_sheet"
        %{"speaker" => decision["speaker"], "action" => action}
      end)

    ReviewDecisions.apply(plan, true, decisions)
  end

  defp fixture_archive do
    entries =
      Enum.map(@archive_files, fn relative_path ->
        {String.to_charlist(relative_path), fixture!(relative_path)}
      end)

    {:ok, {_name, archive}} = :zip.create(~c"space-journey.zip", entries, [:memory])
    archive
  end

  defp fixture!(relative_path), do: File.read!(Path.join(@fixture_root, relative_path))

  defp fixture_json!(relative_path) do
    relative_path
    |> fixture!()
    |> Jason.decode!()
  end

  defp git_blob_sha(content) do
    :sha
    |> :crypto.hash("blob #{byte_size(content)}\0" <> content)
    |> Base.encode16(case: :lower)
  end

  defp flow_references(flows, flows_by_id) do
    flows
    |> Enum.flat_map(fn flow ->
      for node <- flow["nodes"],
          node["type"] == "exit",
          referenced_id = node["data"]["referenced_flow_id"],
          is_binary(referenced_id),
          do: {flow["name"], Map.fetch!(flows_by_id, referenced_id)}
    end)
    |> MapSet.new()
  end

  defp materialized_flow_references(flows, flows_by_id) do
    flows
    |> Enum.flat_map(fn flow ->
      for node <- Flows.list_nodes(flow.id),
          node.type == "exit",
          referenced_id = node.data["referenced_flow_id"],
          is_integer(referenced_id),
          do: {flow.name, Map.fetch!(flows_by_id, referenced_id)}
    end)
    |> MapSet.new()
  end

  defp plan_start_routes(flow, flows_by_id) do
    nodes_by_id = Map.new(flow["nodes"], &{&1["id"], &1})

    choice =
      Enum.find(flow["nodes"], fn node ->
        node["type"] == "dialogue" and node["data"]["text"] == "I wonder what I should do?"
      end)

    Map.new(choice["data"]["responses"], fn response ->
      connection =
        Enum.find(flow["connections"], fn connection ->
          connection["source_node_id"] == choice["id"] and
            connection["source_pin"] == response["id"]
        end)

      exit = Map.fetch!(nodes_by_id, connection["target_node_id"])
      {response["text"], Map.fetch!(flows_by_id, exit["data"]["referenced_flow_id"])}
    end)
  end

  defp materialized_start_routes(flow, flows_by_id) do
    nodes = Flows.list_nodes(flow.id)
    nodes_by_id = Map.new(nodes, &{&1.id, &1})
    connections = Flows.list_connections(flow.id)

    choice =
      Enum.find(nodes, fn node ->
        node.type == "dialogue" and node.data["text"] == "I wonder what I should do?"
      end)

    Map.new(choice.data["responses"], fn response ->
      connection =
        Enum.find(connections, fn connection ->
          connection.source_node_id == choice.id and connection.source_pin == response["id"]
        end)

      exit = Map.fetch!(nodes_by_id, connection.target_node_id)
      {response["text"], Map.fetch!(flows_by_id, exit.data["referenced_flow_id"])}
    end)
  end

  defp plan_condition_routes(flow) do
    nodes_by_id = Map.new(flow["nodes"], &{&1["id"], &1})

    flow["nodes"]
    |> Enum.filter(&(&1["type"] == "condition"))
    |> Map.new(fn condition ->
      {condition_rule_signature(condition["data"]),
       %{
         "false" => first_plan_dialogue(flow["connections"], nodes_by_id, condition["id"], "false"),
         "true" => first_plan_dialogue(flow["connections"], nodes_by_id, condition["id"], "true")
       }}
    end)
  end

  defp materialized_condition_routes(flow, nodes) do
    nodes_by_id = Map.new(nodes, &{&1.id, &1})
    connections = Flows.list_connections(flow.id)

    nodes
    |> Enum.filter(&(&1.type == "condition"))
    |> Map.new(fn condition ->
      {condition_rule_signature(condition.data),
       %{
         "false" => first_materialized_dialogue(connections, nodes_by_id, condition.id, "false"),
         "true" => first_materialized_dialogue(connections, nodes_by_id, condition.id, "true")
       }}
    end)
  end

  defp condition_rule_signature(data) do
    [block | _rest] = data["condition"]["blocks"]
    [rule | _rest] = block["rules"]
    {rule["variable"], rule["operator"], rule["value"]}
  end

  defp first_plan_dialogue(connections, nodes_by_id, source_id, source_pin) do
    connection =
      Enum.find(connections, fn connection ->
        connection["source_node_id"] == source_id and connection["source_pin"] == source_pin
      end)

    node = Map.fetch!(nodes_by_id, connection["target_node_id"])

    if node["type"] == "dialogue" do
      node["data"]["text"]
    else
      first_plan_dialogue(connections, nodes_by_id, node["id"], "output")
    end
  end

  defp first_materialized_dialogue(connections, nodes_by_id, source_id, source_pin) do
    connection =
      Enum.find(connections, fn connection ->
        connection.source_node_id == source_id and connection.source_pin == source_pin
      end)

    node = Map.fetch!(nodes_by_id, connection.target_node_id)

    if node.type == "dialogue" do
      node.data["text"]
    else
      first_materialized_dialogue(connections, nodes_by_id, node.id, "output")
    end
  end

  defp plan_connection_shapes(flows) do
    Map.new(flows, fn flow ->
      node_types = Map.new(flow["nodes"], &{&1["id"], &1["type"]})

      shapes =
        Enum.frequencies_by(flow["connections"], fn connection ->
          {
            Map.fetch!(node_types, connection["source_node_id"]),
            normalized_pin(connection["source_pin"]),
            Map.fetch!(node_types, connection["target_node_id"]),
            normalized_pin(connection["target_pin"])
          }
        end)

      {flow["name"], shapes}
    end)
  end

  defp materialized_connection_shapes(flows) do
    Map.new(flows, fn flow ->
      nodes = Flows.list_nodes(flow.id)
      node_types = Map.new(nodes, &{&1.id, &1.type})

      shapes =
        flow.id
        |> Flows.list_connections()
        |> Enum.frequencies_by(fn connection ->
          {
            Map.fetch!(node_types, connection.source_node_id),
            normalized_pin(connection.source_pin),
            Map.fetch!(node_types, connection.target_node_id),
            normalized_pin(connection.target_pin)
          }
        end)

      {flow.name, shapes}
    end)
  end

  defp normalized_pin("response_" <> _id), do: "response"
  defp normalized_pin(pin), do: pin

  defp condition_rules(flows) do
    for flow <- flows,
        node <- flow["nodes"],
        node["type"] == "condition",
        block <- node["data"]["condition"]["blocks"],
        rule <- block["rules"],
        do: rule
  end

  defp native_condition_rules(nodes) do
    for node <- nodes,
        node.type == "condition",
        block <- node.data["condition"]["blocks"],
        rule <- block["rules"],
        do: rule
  end

  defp assignment_frequencies(flows, nodes_for_flow) do
    flows
    |> Enum.flat_map(&flow_assignments(&1, nodes_for_flow))
    |> Enum.frequencies()
  end

  defp flow_assignments(flow, nodes_for_flow) do
    for node <- nodes_for_flow.(flow),
        node["type"] == "instruction",
        assignment <- node["data"]["assignments"] || [],
        do: assignment_signature(assignment)
  end

  defp assignment_signature(assignment) do
    operator = assignment["operator"]
    value = if operator in ["set_true", "set_false"], do: nil, else: assignment["value"]
    {assignment["sheet"], assignment["variable"], operator, value}
  end
end
