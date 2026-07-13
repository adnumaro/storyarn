defmodule Storyarn.Exports.Serializers.UnityJSONTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Exports.DataCollector
  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Exports.Serializers.UnityJSON
  alias Storyarn.Flows
  alias Storyarn.Localization
  alias Storyarn.Repo
  alias Storyarn.Sheets

  defp reload_flow(flow), do: Repo.preload(flow, [:nodes, :connections], force: true)

  defp create_project(_context) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  defp default_opts do
    {:ok, opts} = ExportOptions.new(%{format: :unity, validate_before_export: false})
    opts
  end

  defp export_and_decode(project, opts \\ nil) do
    opts = opts || default_opts()
    project_data = DataCollector.collect(project.id, opts)
    {:ok, json} = UnityJSON.serialize(project_data, opts)
    Jason.decode!(json)
  end

  defp field(asset, title) do
    maybe_field(asset, title) ||
      flunk("Expected field #{inspect(title)} in #{inspect(asset["fields"])}")
  end

  defp maybe_field(asset, title), do: Enum.find(asset["fields"] || [], &(&1["title"] == title))
  defp field_value(asset, title), do: asset |> field(title) |> Map.fetch!("value")

  defp maybe_field_value(asset, title) do
    case maybe_field(asset, title) do
      nil -> nil
      field -> field["value"]
    end
  end

  defp actor_by_name(result, name) do
    Enum.find(result["actors"], &(field_value(&1, "Name") == name)) ||
      flunk("Expected actor #{inspect(name)}")
  end

  defp conversation_by_title(result, title) do
    Enum.find(result["conversations"], &(field_value(&1, "Title") == title)) ||
      flunk("Expected conversation #{inspect(title)}")
  end

  defp entry_by_storyarn_node_id(entries, node_id) do
    node_id = to_string(node_id)

    Enum.find(entries, &(field_value(&1, "Storyarn Node ID") == node_id)) ||
      flunk("Expected dialogue entry for Storyarn node #{node_id}")
  end

  defp entry_by_storyarn_response_id(entries, response_id) do
    response_id = to_string(response_id)

    Enum.find(entries, &(maybe_field_value(&1, "Storyarn Response ID") == response_id)) ||
      flunk("Expected dialogue entry for Storyarn response #{response_id}")
  end

  defp entry_by_condition_branch_pin(entries, pin) do
    pin = to_string(pin)

    Enum.find(entries, &(maybe_field_value(&1, "Storyarn Condition Branch Pin") == pin)) ||
      flunk("Expected dialogue entry for Storyarn condition branch #{pin}")
  end

  defp assert_link(source_entry, destination_entry) do
    assert Enum.any?(source_entry["outgoingLinks"], fn link ->
             link["originConversationID"] == source_entry["conversationID"] and
               link["originDialogueID"] == source_entry["id"] and
               link["destinationConversationID"] == destination_entry["conversationID"] and
               link["destinationDialogueID"] == destination_entry["id"] and
               link["isConnector"] == false
           end)
  end

  describe "behaviour callbacks" do
    test "content_type returns application/json" do
      assert UnityJSON.content_type() == "application/json"
    end

    test "file_extension returns json" do
      assert UnityJSON.file_extension() == "json"
    end

    test "format_label returns human-readable name" do
      assert UnityJSON.format_label() == "Unity Dialogue System (JSON)"
    end

    test "supported_sections lists flows and sheets" do
      sections = UnityJSON.supported_sections()
      assert :flows in sections
      assert :sheets in sections
      assert :localization in sections
      assert :assets in sections
    end

    test "serialize_to_file returns not_implemented" do
      assert {:error, :not_implemented} = UnityJSON.serialize_to_file(nil, "", nil, [])
    end
  end

  describe "Dialogue System database envelope" do
    setup [:create_project]

    test "produces root-level DialogueDatabase collections", %{project: project} do
      result = export_and_decode(project)

      assert result["version"] == "1.0"
      assert result["author"] == "Storyarn"
      assert is_binary(result["description"])
      assert result["globalUserScript"] == ""
      assert is_list(result["emphasisSettings"])
      assert is_list(result["actors"])
      assert is_list(result["items"])
      assert is_list(result["locations"])
      assert is_list(result["variables"])
      assert is_list(result["conversations"])
      assert is_map(result["syncInfo"])
      assert is_binary(result["templateJson"])

      refute Map.has_key?(result, "database")
      refute Map.has_key?(result, "format")
      refute Map.has_key?(result, "storyarn_version")
    end

    test "templateJson is valid JSON", %{project: project} do
      result = export_and_decode(project)
      assert %{} = Jason.decode!(result["templateJson"])
    end
  end

  describe "actors from sheets" do
    setup [:create_project]

    test "exports a synthetic player actor", %{project: project} do
      result = export_and_decode(project)
      player = actor_by_name(result, "Player")

      assert player["id"] == 1
      assert field_value(player, "IsPlayer") == "True"
      assert field_value(player, "Storyarn Actor Kind") == "synthetic_player"
    end

    test "sheets become Dialogue System actor assets", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Jaime"})

      result = export_and_decode(project)
      actor = actor_by_name(result, "Jaime")

      assert actor["id"] > 1
      assert field_value(actor, "Name") == "Jaime"
      assert field_value(actor, "Display Name") == "Jaime"
      assert field_value(actor, "IsPlayer") == "False"
      assert field_value(actor, "Storyarn Sheet ID") == to_string(sheet.id)
      assert field_value(actor, "Storyarn Shortcut") == sheet.shortcut

      assert field(actor, "Name")["type"] == 0
      assert field(actor, "Name")["typeString"] == "CustomFieldType_Text"
      assert field(actor, "IsPlayer")["type"] == 2
      assert field(actor, "IsPlayer")["typeString"] == "CustomFieldType_Boolean"
    end

    test "uses the sheet default avatar as the actor Pictures file", %{project: project, user: user} do
      sheet = sheet_fixture(project, %{name: "Kael"})

      portrait =
        image_asset_fixture(project, user, %{
          filename: "kael_portrait.png",
          url: "Assets/Storyarn/Portraits/kael_portrait.png",
          key: "projects/storyarn/assets/kael_portrait.png"
        })

      {:ok, _avatar} = Sheets.add_avatar(sheet, portrait.id, %{name: "default"})

      result = export_and_decode(project)
      actor = actor_by_name(result, "Kael")

      assert field_value(actor, "Pictures") == "[Assets/Storyarn/Portraits/kael_portrait.png]"
      assert field_value(actor, "Storyarn Portrait Asset ID") == to_string(portrait.id)
      assert field_value(actor, "Storyarn Portrait Filename") == "kael_portrait.png"
      assert field_value(actor, "Storyarn Portrait URL") == "Assets/Storyarn/Portraits/kael_portrait.png"
      assert field(actor, "Pictures")["typeString"] == "CustomFieldType_Files"
    end
  end

  describe "variables from sheet blocks" do
    setup [:create_project]

    test "exports variables as Dialogue System variable assets", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        variable_name: "health",
        config: %{"label" => "Health"},
        value: %{"number" => 100}
      })

      result = export_and_decode(project)
      variable = Enum.find(result["variables"], &(field_value(&1, "Storyarn Variable Name") == "health"))

      assert variable
      assert field_value(variable, "Name") == "#{sheet.shortcut}.health"
      assert field_value(variable, "Initial Value") == "100"
      assert field_value(variable, "Storyarn Sheet Shortcut") == sheet.shortcut
      assert field_value(variable, "Storyarn Variable Type") == "number"
    end
  end

  describe "conversations and dialogue entries" do
    setup [:create_project]

    test "flows become Dialogue System conversations", %{project: project} do
      flow = flow_fixture(project, %{name: "Act 1"})

      result = export_and_decode(project)
      conversation = conversation_by_title(result, "Act 1")

      assert conversation["id"] == 1
      assert field_value(conversation, "Title") == flow.name
      assert field_value(conversation, "Storyarn Flow ID") == to_string(flow.id)
      assert field_value(conversation, "Storyarn Shortcut") == flow.shortcut
      assert is_list(conversation["dialogueEntries"])
      assert is_map(conversation["overrideSettings"])
      assert is_map(conversation["canvasScrollPosition"])
      assert conversation["canvasZoom"] == 1.0
    end

    test "entry node becomes a root dialogue entry", %{project: project} do
      flow = project |> flow_fixture(%{name: "Root Test"}) |> reload_flow()
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      result = export_and_decode(project)
      entries = result |> conversation_by_title("Root Test") |> Map.fetch!("dialogueEntries")
      root_entry = entry_by_storyarn_node_id(entries, entry.id)

      assert root_entry["conversationID"] == 1
      assert root_entry["isRoot"] == true
      assert root_entry["isGroup"] == true
      assert field_value(root_entry, "Title") == "<START>"
      assert field_value(root_entry, "Storyarn Node Type") == "entry"
      assert is_list(root_entry["outgoingLinks"])
      assert is_map(root_entry["canvasRect"])
    end

    test "annotation nodes are editor-only and are not exported as dialogue entries", %{project: project} do
      flow = project |> flow_fixture(%{name: "Annotation Test"}) |> reload_flow()

      annotation =
        node_fixture(flow, %{
          type: "annotation",
          data: %{"text" => "Designer note"}
        })

      result = export_and_decode(project)
      entries = result |> conversation_by_title("Annotation Test") |> Map.fetch!("dialogueEntries")

      refute Enum.any?(entries, &(maybe_field_value(&1, "Storyarn Node ID") == to_string(annotation.id)))
      refute Enum.any?(entries, &(maybe_field_value(&1, "Storyarn Node Type") == "annotation"))
    end

    test "linear dialogue exports fields and outgoing links", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Kael"})
      flow = project |> flow_fixture(%{name: "Dialogue Test"}) |> reload_flow()
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))
      exit_node = Enum.find(flow.nodes, &(&1.type == "exit"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Hello world!",
            "speaker_sheet_id" => sheet.id,
            "stage_directions" => "<p>smiles</p>",
            "responses" => []
          }
        })

      connection_fixture(flow, entry, dialogue)
      connection_fixture(flow, dialogue, exit_node)

      result = export_and_decode(project)
      entries = result |> conversation_by_title("Dialogue Test") |> Map.fetch!("dialogueEntries")

      root_entry = entry_by_storyarn_node_id(entries, entry.id)
      dialogue_entry = entry_by_storyarn_node_id(entries, dialogue.id)
      exit_entry = entry_by_storyarn_node_id(entries, exit_node.id)
      kael_actor_id = Integer.to_string(actor_by_name(result, "Kael")["id"])

      assert field_value(dialogue_entry, "Dialogue Text") == "Hello world!"
      assert field_value(dialogue_entry, "Description") == "smiles"
      assert field_value(dialogue_entry, "Storyarn Node Type") == "dialogue"
      assert field_value(dialogue_entry, "Actor") == kael_actor_id

      assert_link(root_entry, dialogue_entry)
      assert_link(dialogue_entry, exit_entry)
    end

    test "dialogue audio assets become voice over file fields and an audio sequence", %{
      project: project,
      user: user
    } do
      audio =
        audio_asset_fixture(project, user, %{
          filename: "kael_line_001.mp3",
          url: "Assets/Storyarn/Voice/kael_line_001.mp3",
          key: "projects/storyarn/assets/kael_line_001.mp3"
        })

      flow = project |> flow_fixture(%{name: "Audio Test"}) |> reload_flow()

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "With audio",
            "audio_asset_id" => audio.id,
            "responses" => []
          }
        })

      result = export_and_decode(project)
      entries = result |> conversation_by_title("Audio Test") |> Map.fetch!("dialogueEntries")
      dialogue_entry = entry_by_storyarn_node_id(entries, dialogue.id)

      assert field_value(dialogue_entry, "Sequence") == "AudioWait(entrytag)"
      assert field_value(dialogue_entry, "VoiceOverFile") == "kael_line_001"
      assert field_value(dialogue_entry, "Storyarn Audio Asset ID") == to_string(audio.id)
      assert field_value(dialogue_entry, "Storyarn Audio Filename") == "kael_line_001.mp3"
      assert field_value(dialogue_entry, "Storyarn Audio URL") == "Assets/Storyarn/Voice/kael_line_001.mp3"
    end

    test "dialogue responses become player entries with branch links", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Flags"})

      block_fixture(sheet, %{
        type: "boolean",
        variable_name: "has_sword",
        config: %{"label" => "Has Sword"},
        value: %{"boolean" => true}
      })

      flow = project |> flow_fixture(%{name: "Response Test"}) |> reload_flow()
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Choose wisely",
            "responses" => [
              %{
                "id" => "fight",
                "text" => "Fight",
                "condition" => %{
                  "logic" => "all",
                  "blocks" => [
                    %{
                      "type" => "block",
                      "logic" => "all",
                      "rules" => [
                        %{
                          "sheet" => sheet.shortcut,
                          "variable" => "has_sword",
                          "operator" => "is_true"
                        }
                      ]
                    }
                  ]
                },
                "instruction" =>
                  Jason.encode!([
                    %{
                      "sheet" => sheet.shortcut,
                      "variable" => "has_sword",
                      "operator" => "set_false"
                    }
                  ])
              },
              %{"id" => "run", "text" => "Run", "condition" => nil, "instruction" => nil}
            ]
          }
        })

      fight = node_fixture(flow, %{type: "dialogue", data: %{"text" => "You fight.", "responses" => []}})
      run = node_fixture(flow, %{type: "dialogue", data: %{"text" => "You run.", "responses" => []}})

      connection_fixture(flow, entry, dialogue)
      connection_fixture(flow, dialogue, fight, %{source_pin: "response_fight"})
      connection_fixture(flow, dialogue, run, %{source_pin: "response_run"})

      result = export_and_decode(project)
      entries = result |> conversation_by_title("Response Test") |> Map.fetch!("dialogueEntries")

      dialogue_entry = entry_by_storyarn_node_id(entries, dialogue.id)
      fight_response = entry_by_storyarn_response_id(entries, "fight")
      run_response = entry_by_storyarn_response_id(entries, "run")
      fight_entry = entry_by_storyarn_node_id(entries, fight.id)
      run_entry = entry_by_storyarn_node_id(entries, run.id)

      assert field_value(fight_response, "Actor") == "1"
      assert field_value(fight_response, "Menu Text") == "Fight"
      assert fight_response["conditionsString"] == ~s(Variable["#{sheet.shortcut}.has_sword"] == true)
      assert fight_response["userScript"] == ~s(Variable["#{sheet.shortcut}.has_sword"] = false)
      assert field_value(run_response, "Dialogue Text") == "Run"

      assert_link(dialogue_entry, fight_response)
      assert_link(dialogue_entry, run_response)
      assert_link(fight_response, fight_entry)
      assert_link(run_response, run_entry)
    end
  end

  describe "condition and instruction expressions" do
    setup [:create_project]

    test "boolean condition node exports branch entries with Lua conditionsString", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        variable_name: "health",
        config: %{"label" => "Health"},
        value: %{"number" => 100}
      })

      flow = project |> flow_fixture(%{name: "Expr Flow"}) |> reload_flow()
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      condition =
        node_fixture(flow, %{
          type: "condition",
          data: %{
            "condition" => %{
              "logic" => "all",
              "blocks" => [
                %{
                  "type" => "block",
                  "logic" => "all",
                  "rules" => [
                    %{
                      "sheet" => sheet.shortcut,
                      "variable" => "health",
                      "operator" => "greater_than",
                      "value" => 50
                    }
                  ]
                }
              ]
            }
          }
        })

      connection_fixture(flow, entry, condition)
      true_target = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Healthy", "responses" => []}})
      false_target = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Injured", "responses" => []}})
      connection_fixture(flow, condition, true_target, %{source_pin: "true"})
      connection_fixture(flow, condition, false_target, %{source_pin: "false"})

      result = export_and_decode(project)
      entries = result |> conversation_by_title("Expr Flow") |> Map.fetch!("dialogueEntries")
      condition_entry = entry_by_storyarn_node_id(entries, condition.id)
      true_branch = entry_by_condition_branch_pin(entries, "true")
      false_branch = entry_by_condition_branch_pin(entries, "false")
      true_entry = entry_by_storyarn_node_id(entries, true_target.id)
      false_entry = entry_by_storyarn_node_id(entries, false_target.id)

      assert condition_entry["conditionsString"] == ""
      assert true_branch["conditionsString"] == ~s(Variable["#{sheet.shortcut}.health"] > 50)
      assert false_branch["conditionsString"] == ~s|not (Variable["#{sheet.shortcut}.health"] > 50)|

      assert field_value(true_branch, "Storyarn Node Type") == "condition_branch"
      assert field_value(false_branch, "Storyarn Node Type") == "condition_branch"
      assert_link(condition_entry, true_branch)
      assert_link(condition_entry, false_branch)
      assert_link(true_branch, true_entry)
      assert_link(false_branch, false_entry)
    end

    test "switch condition exports case branches", %{project: project} do
      sheet = sheet_fixture(project, %{name: "World State"})

      block_fixture(sheet, %{
        type: "select",
        variable_name: "mood",
        config: %{"label" => "Mood", "options" => ["happy", "sad"]},
        value: %{"select" => "happy"}
      })

      flow = project |> flow_fixture(%{name: "Switch Flow"}) |> reload_flow()
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      condition =
        node_fixture(flow, %{
          type: "condition",
          data: %{
            "switch_mode" => true,
            "condition" => %{
              "logic" => "all",
              "blocks" => [
                %{
                  "id" => "happy",
                  "label" => "Happy",
                  "type" => "block",
                  "logic" => "all",
                  "rules" => [
                    %{
                      "sheet" => sheet.shortcut,
                      "variable" => "mood",
                      "operator" => "equals",
                      "value" => "happy"
                    }
                  ]
                },
                %{
                  "id" => "sad",
                  "label" => "Sad",
                  "type" => "block",
                  "logic" => "all",
                  "rules" => [
                    %{
                      "sheet" => sheet.shortcut,
                      "variable" => "mood",
                      "operator" => "equals",
                      "value" => "sad"
                    }
                  ]
                }
              ]
            }
          }
        })

      happy_target = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Happy path", "responses" => []}})
      sad_target = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Sad path", "responses" => []}})

      connection_fixture(flow, entry, condition)
      connection_fixture(flow, condition, happy_target, %{source_pin: "happy"})
      connection_fixture(flow, condition, sad_target, %{source_pin: "sad"})

      result = export_and_decode(project)
      entries = result |> conversation_by_title("Switch Flow") |> Map.fetch!("dialogueEntries")

      condition_entry = entry_by_storyarn_node_id(entries, condition.id)
      happy_branch = entry_by_condition_branch_pin(entries, "happy")
      sad_branch = entry_by_condition_branch_pin(entries, "sad")
      happy_entry = entry_by_storyarn_node_id(entries, happy_target.id)
      sad_entry = entry_by_storyarn_node_id(entries, sad_target.id)

      happy_condition = ~s(Variable["#{sheet.shortcut}.mood"] == "happy")
      sad_condition = ~s(Variable["#{sheet.shortcut}.mood"] == "sad")

      assert happy_branch["conditionsString"] == happy_condition
      assert sad_branch["conditionsString"] == sad_condition

      assert field_value(happy_branch, "Storyarn Condition Branch Label") == "Happy"
      assert field_value(sad_branch, "Storyarn Condition Branch Label") == "Sad"

      assert_link(condition_entry, happy_branch)
      assert_link(condition_entry, sad_branch)
      assert_link(happy_branch, happy_entry)
      assert_link(sad_branch, sad_entry)
    end

    test "instruction node exports Lua userScript", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Flags"})

      block_fixture(sheet, %{
        type: "boolean",
        variable_name: "met",
        config: %{"label" => "Met"},
        value: %{"boolean" => false}
      })

      flow = project |> flow_fixture(%{name: "Inst Flow"}) |> reload_flow()
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      instruction =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "sheet" => sheet.shortcut,
                "variable" => "met",
                "operator" => "set_true"
              }
            ]
          }
        })

      connection_fixture(flow, entry, instruction)

      result = export_and_decode(project)
      entries = result |> conversation_by_title("Inst Flow") |> Map.fetch!("dialogueEntries")
      instruction_entry = entry_by_storyarn_node_id(entries, instruction.id)

      assert instruction_entry["userScript"] == ~s(Variable["#{sheet.shortcut}.met"] = true)
    end
  end

  describe "flow control nodes" do
    setup [:create_project]

    test "jump links to the targeted hub entry", %{project: project} do
      flow = project |> flow_fixture(%{name: "Jump Flow"}) |> reload_flow()
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "checkpoint", "label" => "Checkpoint", "color" => "#22c55e"}
        })

      jump =
        node_fixture(flow, %{
          type: "jump",
          data: %{"target_hub_id" => "checkpoint"}
        })

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "After checkpoint", "responses" => []}
        })

      connection_fixture(flow, entry, jump)
      connection_fixture(flow, hub, dialogue)

      result = export_and_decode(project)
      entries = result |> conversation_by_title("Jump Flow") |> Map.fetch!("dialogueEntries")

      entry_entry = entry_by_storyarn_node_id(entries, entry.id)
      hub_entry = entry_by_storyarn_node_id(entries, hub.id)
      jump_entry = entry_by_storyarn_node_id(entries, jump.id)
      dialogue_entry = entry_by_storyarn_node_id(entries, dialogue.id)

      assert field_value(hub_entry, "Storyarn Hub ID") == "checkpoint"
      assert field_value(jump_entry, "Storyarn Target Hub ID") == "checkpoint"

      assert_link(entry_entry, jump_entry)
      assert_link(jump_entry, hub_entry)
      assert_link(hub_entry, dialogue_entry)
    end

    test "terminal exit has no outgoing links", %{project: project} do
      flow = project |> flow_fixture(%{name: "Exit Flow"}) |> reload_flow()
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))
      exit_node = Enum.find(flow.nodes, &(&1.type == "exit"))

      connection_fixture(flow, entry, exit_node)

      result = export_and_decode(project)
      entries = result |> conversation_by_title("Exit Flow") |> Map.fetch!("dialogueEntries")

      entry_entry = entry_by_storyarn_node_id(entries, entry.id)
      exit_entry = entry_by_storyarn_node_id(entries, exit_node.id)

      assert field_value(exit_entry, "Storyarn Exit Mode") == "terminal"
      assert_link(entry_entry, exit_entry)
      assert exit_entry["outgoingLinks"] == []
    end

    test "flow reference exit links to referenced conversation root", %{project: project} do
      target_flow = project |> flow_fixture(%{name: "Target Flow"}) |> reload_flow()
      source_flow = project |> flow_fixture(%{name: "Source Flow"}) |> reload_flow()
      source_entry = Enum.find(source_flow.nodes, &(&1.type == "entry"))
      target_entry = Enum.find(target_flow.nodes, &(&1.type == "entry"))

      exit_node =
        node_fixture(source_flow, %{
          type: "exit",
          data: %{"exit_mode" => "flow_reference", "referenced_flow_id" => target_flow.id}
        })

      connection_fixture(source_flow, source_entry, exit_node)

      result = export_and_decode(project)
      source_entries = result |> conversation_by_title("Source Flow") |> Map.fetch!("dialogueEntries")
      target_entries = result |> conversation_by_title("Target Flow") |> Map.fetch!("dialogueEntries")

      exit_entry = entry_by_storyarn_node_id(source_entries, exit_node.id)
      target_root_entry = entry_by_storyarn_node_id(target_entries, target_entry.id)

      assert field_value(exit_entry, "Storyarn Exit Mode") == "flow_reference"
      assert field_value(exit_entry, "Storyarn Referenced Flow ID") == to_string(target_flow.id)
      assert_link(exit_entry, target_root_entry)
    end

    test "subflow links to referenced conversation root", %{project: project} do
      target_flow = project |> flow_fixture(%{name: "Nested Flow"}) |> reload_flow()
      caller_flow = project |> flow_fixture(%{name: "Caller Flow"}) |> reload_flow()
      caller_entry = Enum.find(caller_flow.nodes, &(&1.type == "entry"))
      target_entry = Enum.find(target_flow.nodes, &(&1.type == "entry"))

      subflow =
        node_fixture(caller_flow, %{
          type: "subflow",
          data: %{
            "referenced_flow_id" => target_flow.id,
            "referenced_flow_shortcut" => target_flow.shortcut,
            "referenced_flow_name" => target_flow.name
          }
        })

      connection_fixture(caller_flow, caller_entry, subflow)

      result = export_and_decode(project)
      caller_entries = result |> conversation_by_title("Caller Flow") |> Map.fetch!("dialogueEntries")
      target_entries = result |> conversation_by_title("Nested Flow") |> Map.fetch!("dialogueEntries")

      caller_entry_entry = entry_by_storyarn_node_id(caller_entries, caller_entry.id)
      subflow_entry = entry_by_storyarn_node_id(caller_entries, subflow.id)
      target_root_entry = entry_by_storyarn_node_id(target_entries, target_entry.id)

      assert field_value(subflow_entry, "Storyarn Referenced Flow ID") == to_string(target_flow.id)
      assert field_value(subflow_entry, "Storyarn Referenced Flow Shortcut") == target_flow.shortcut

      assert_link(caller_entry_entry, subflow_entry)
      assert_link(subflow_entry, target_root_entry)
    end
  end

  describe "sequence metadata" do
    setup [:create_project]

    test "sequence containers are not exported as dialogue entries, but child entries keep sequence metadata", %{
      project: project
    } do
      flow = project |> flow_fixture(%{name: "Sequence Flow"}) |> reload_flow()
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      {:ok, sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Act I",
          "position_x" => 220.0,
          "position_y" => 120.0,
          "width" => 640.0,
          "height" => 360.0
        })

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          parent_id: sequence.id,
          position_x: 260.0,
          position_y: 180.0,
          data: %{"text" => "Inside the sequence.", "responses" => []}
        })

      connection_fixture(flow, entry, dialogue)

      result = export_and_decode(project)
      entries = result |> conversation_by_title("Sequence Flow") |> Map.fetch!("dialogueEntries")

      refute Enum.any?(entries, &(maybe_field_value(&1, "Storyarn Node ID") == to_string(sequence.id)))

      dialogue_entry = entry_by_storyarn_node_id(entries, dialogue.id)

      assert field_value(dialogue_entry, "Storyarn Sequence ID") == to_string(sequence.id)
      assert field_value(dialogue_entry, "Storyarn Sequence Name") == "Act I"
      assert field_value(dialogue_entry, "Storyarn Sequence Path") == "Act I"
      assert field_value(dialogue_entry, "Storyarn Sequence Depth") == "1"
      assert dialogue_entry["canvasRect"]["x"] == 260.0
      assert dialogue_entry["canvasRect"]["y"] == 180.0
    end

    test "nested sequence metadata preserves the full sequence path", %{project: project} do
      flow = project |> flow_fixture(%{name: "Nested Sequence Flow"}) |> reload_flow()
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      {:ok, outer} = Flows.create_sequence(flow.id, %{"name" => "Outer"})
      {:ok, inner} = Flows.create_sequence(flow.id, %{"name" => "Inner", "parent_id" => outer.id})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          parent_id: inner.id,
          data: %{"text" => "Nested.", "responses" => []}
        })

      connection_fixture(flow, entry, dialogue)

      result = export_and_decode(project)
      entries = result |> conversation_by_title("Nested Sequence Flow") |> Map.fetch!("dialogueEntries")
      dialogue_entry = entry_by_storyarn_node_id(entries, dialogue.id)

      assert field_value(dialogue_entry, "Storyarn Sequence ID") == to_string(inner.id)
      assert field_value(dialogue_entry, "Storyarn Sequence Name") == "Inner"
      assert field_value(dialogue_entry, "Storyarn Sequence Path") == "Outer / Inner"
      assert field_value(dialogue_entry, "Storyarn Sequence Depth") == "2"
    end
  end

  describe "localization fields" do
    setup [:create_project]

    test "dialogue entries keep source text and add localized text fields", %{project: project} do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      flow = project |> flow_fixture(%{name: "Localized Flow"}) |> reload_flow()

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "<p>Hello</p>",
            "menu_text" => "Talk",
            "stage_directions" => "Smiles",
            "responses" => []
          }
        })

      _source_text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: dialogue.id,
          source_field: "text",
          source_text: "Hello",
          locale_code: "en",
          translated_text: "Hello",
          status: "final"
        })

      _dialogue_text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: dialogue.id,
          source_field: "text",
          source_text: "Hello",
          locale_code: "es",
          translated_text: "<p>Hola</p>",
          status: "final"
        })

      _menu_text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: dialogue.id,
          source_field: "menu_text",
          source_text: "Talk",
          locale_code: "es",
          translated_text: "Hablar",
          status: "final"
        })

      _stage_directions =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: dialogue.id,
          source_field: "stage_directions",
          source_text: "Smiles",
          locale_code: "es",
          translated_text: "Sonríe",
          status: "final"
        })

      _unrelated_text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: System.unique_integer([:positive]),
          source_field: "text",
          source_text: "Other",
          locale_code: "es",
          translated_text: "Otro",
          status: "final"
        })

      result = export_and_decode(project)
      entries = result |> conversation_by_title("Localized Flow") |> Map.fetch!("dialogueEntries")
      dialogue_entry = entry_by_storyarn_node_id(entries, dialogue.id)

      assert field_value(dialogue_entry, "Dialogue Text") == "Hello"
      assert field_value(dialogue_entry, "Menu Text") == "Talk"
      assert field_value(dialogue_entry, "Description") == "Smiles"
      assert field_value(dialogue_entry, "Dialogue Text es") == "Hola"
      assert field_value(dialogue_entry, "Menu Text es") == "Hablar"
      assert field_value(dialogue_entry, "Description es") == "Sonríe"
      assert field(dialogue_entry, "Dialogue Text es")["type"] == 4
      assert field(dialogue_entry, "Dialogue Text es")["typeString"] == "CustomFieldType_Localization"
      assert field(dialogue_entry, "Menu Text es")["type"] == 4
      assert field(dialogue_entry, "Menu Text es")["typeString"] == "CustomFieldType_Localization"
      refute maybe_field(dialogue_entry, "Dialogue Text en")
      refute maybe_field(dialogue_entry, "Dialogue Text fr")
    end

    test "release excludes drafts and their voice while preview includes them and reports the policy", %{
      project: project,
      user: user
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      voice = audio_asset_fixture(project, user, %{filename: "draft_es.ogg"})
      flow = project |> flow_fixture(%{name: "Preview Localization"}) |> reload_flow()
      dialogue = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello", "responses" => []}})
      [text] = Localization.get_texts_for_source("flow_node", dialogue.id)

      assert {:ok, _text} =
               Localization.update_text(text, %{
                 translated_text: "Borrador",
                 status: "draft",
                 vo_asset_id: voice.id,
                 vo_status: "approved"
               })

      release = export_and_decode(project)

      release_entry =
        release
        |> conversation_by_title("Preview Localization")
        |> Map.fetch!("dialogueEntries")
        |> entry_by_storyarn_node_id(dialogue.id)

      refute maybe_field(release_entry, "Dialogue Text es")
      refute maybe_field(release_entry, "VoiceOverFile es")
      assert release["storyarnLocalization"]["policy"] == "release"
      assert release["storyarnLocalization"]["excludedStrings"] == 1

      %ExportOptions{} = preview_opts = default_opts()
      preview_opts = %{preview_opts | localization_policy: :preview}
      preview = export_and_decode(project, preview_opts)

      preview_entry =
        preview
        |> conversation_by_title("Preview Localization")
        |> Map.fetch!("dialogueEntries")
        |> entry_by_storyarn_node_id(dialogue.id)

      assert field_value(preview_entry, "Dialogue Text es") == "Borrador"
      assert field_value(preview_entry, "VoiceOverFile es") == "draft_es"
      assert preview["storyarnLocalization"]["policy"] == "preview"
      assert preview["storyarnLocalization"]["warnings"] != []
    end

    test "sheet actor names are localized because all sheets are emitted as engine actors", %{project: project} do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      sheet = sheet_fixture(project, %{name: "Hero"})
      [text] = Localization.get_texts_for_source("sheet", sheet.id)
      assert {:ok, _text} = Localization.update_text(text, %{translated_text: "Héroe", status: "final"})

      actor = project |> export_and_decode() |> actor_by_name("Hero")
      assert field_value(actor, "Name es") == "Héroe"
      assert field_value(actor, "Display Name es") == "Héroe"
    end

    test "exit entries export localized runtime labels", %{project: project} do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      flow = project |> flow_fixture(%{name: "Localized Exit"}) |> reload_flow()

      exit_node =
        node_fixture(flow, %{
          type: "exit",
          data: %{"label" => "Continue", "exit_mode" => "terminal"}
        })

      _exit_text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: exit_node.id,
          source_field: "label",
          source_text: "Continue",
          locale_code: "es",
          translated_text: "Continuar",
          status: "final"
        })

      entries =
        project
        |> export_and_decode()
        |> conversation_by_title("Localized Exit")
        |> Map.fetch!("dialogueEntries")

      exit_entry = entry_by_storyarn_node_id(entries, exit_node.id)

      assert field_value(exit_entry, "Dialogue Text") == "Continue"
      assert field_value(exit_entry, "Dialogue Text es") == "Continuar"
    end

    test "response entries add localized menu and dialogue text fields", %{project: project} do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      flow = project |> flow_fixture(%{name: "Localized Responses"}) |> reload_flow()

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Choose",
            "responses" => [%{"id" => "ask", "text" => "Ask", "condition" => nil, "instruction" => nil}]
          }
        })

      _response_text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: dialogue.id,
          source_field: "response.ask.text",
          source_text: "Ask",
          locale_code: "es",
          translated_text: "Preguntar",
          status: "final"
        })

      result = export_and_decode(project)
      entries = result |> conversation_by_title("Localized Responses") |> Map.fetch!("dialogueEntries")
      response_entry = entry_by_storyarn_response_id(entries, "ask")

      assert field_value(response_entry, "Menu Text") == "Ask"
      assert field_value(response_entry, "Dialogue Text") == "Ask"
      assert field_value(response_entry, "Menu Text es") == "Preguntar"
      assert field_value(response_entry, "Dialogue Text es") == "Preguntar"
      assert field(response_entry, "Menu Text es")["type"] == 4
      assert field(response_entry, "Menu Text es")["typeString"] == "CustomFieldType_Localization"
      assert field(response_entry, "Dialogue Text es")["type"] == 4
      assert field(response_entry, "Dialogue Text es")["typeString"] == "CustomFieldType_Localization"
    end

    test "text block variables expose localized initial values", %{project: project} do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      sheet = sheet_fixture(project, %{name: "Quest"})

      block =
        block_fixture(sheet, %{
          type: "text",
          variable_name: "title",
          value: %{"content" => "The Journey"}
        })

      _translated_value =
        localized_text_fixture(project.id, %{
          source_type: "block",
          source_id: block.id,
          source_field: "value.content",
          source_text: "The Journey",
          locale_code: "es",
          translated_text: "El viaje",
          status: "final"
        })

      result = export_and_decode(project)
      variable = Enum.find(result["variables"], &(field_value(&1, "Storyarn Variable Name") == "title"))

      assert field_value(variable, "Initial Value") == "The Journey"
      assert field_value(variable, "Initial Value es") == "El viaje"
      assert field(variable, "Initial Value es")["typeString"] == "CustomFieldType_Localization"
    end

    test "localized voice over assets become localized VoiceOverFile fields", %{project: project, user: user} do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      voice =
        audio_asset_fixture(project, user, %{
          filename: "kael_line_001_es.ogg",
          url: "Assets/Storyarn/Voice/es/kael_line_001_es.ogg",
          key: "projects/storyarn/assets/kael_line_001_es.ogg"
        })

      flow = project |> flow_fixture(%{name: "Localized Voice"}) |> reload_flow()
      dialogue = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello", "responses" => []}})

      dialogue_text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: dialogue.id,
          source_field: "text",
          source_text: "Hello",
          locale_code: "es",
          translated_text: "Hola",
          status: "final"
        })

      {:ok, _dialogue_text} =
        Localization.update_text(dialogue_text, %{vo_asset_id: voice.id, vo_status: "approved"})

      result = export_and_decode(project)
      entries = result |> conversation_by_title("Localized Voice") |> Map.fetch!("dialogueEntries")
      dialogue_entry = entry_by_storyarn_node_id(entries, dialogue.id)

      assert field_value(dialogue_entry, "Dialogue Text es") == "Hola"
      assert field_value(dialogue_entry, "VoiceOverFile es") == "kael_line_001_es"
      assert field(dialogue_entry, "VoiceOverFile es")["type"] == 4
      assert field(dialogue_entry, "VoiceOverFile es")["typeString"] == "CustomFieldType_Localization"
      assert field_value(dialogue_entry, "Storyarn VoiceOver es Asset ID") == to_string(voice.id)
      assert field_value(dialogue_entry, "Storyarn VoiceOver es Filename") == "kael_line_001_es.ogg"
    end

    test "include_localization false omits localized fields", %{project: project} do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      flow = project |> flow_fixture(%{name: "Localization Disabled"}) |> reload_flow()
      dialogue = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello", "responses" => []}})

      _dialogue_text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: dialogue.id,
          source_field: "text",
          source_text: "Hello",
          locale_code: "es",
          translated_text: "Hola",
          status: "final"
        })

      {:ok, opts} =
        ExportOptions.new(%{format: :unity, validate_before_export: false, include_localization: false})

      result = export_and_decode(project, opts)
      entries = result |> conversation_by_title("Localization Disabled") |> Map.fetch!("dialogueEntries")
      dialogue_entry = entry_by_storyarn_node_id(entries, dialogue.id)

      assert field_value(dialogue_entry, "Dialogue Text") == "Hello"
      refute maybe_field(dialogue_entry, "Dialogue Text es")
    end
  end

  describe "pretty print option" do
    setup [:create_project]

    test "pretty_print produces formatted JSON", %{project: project} do
      {:ok, opts} =
        ExportOptions.new(%{format: :unity, validate_before_export: false, pretty_print: true})

      project_data = DataCollector.collect(project.id, opts)
      {:ok, json} = UnityJSON.serialize(project_data, opts)
      assert json =~ "\n"
    end
  end
end
