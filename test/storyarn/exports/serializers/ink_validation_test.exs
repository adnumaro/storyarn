defmodule Storyarn.Exports.Serializers.InkValidationTest do
  @moduledoc """
  Validates that Ink export output compiles with the official Ink compiler (inklecate).

  These tests are ONLY run in CI where inklecate is installed. Locally, run with:

      mix test --only ink_validation

  Requires inklecate in PATH. See `Storyarn.Test.InkCompiler` for build instructions.
  """
  use Storyarn.DataCase, async: true

  alias Storyarn.Exports.{DataCollector, ExportOptions}
  alias Storyarn.Exports.Serializers.Ink
  alias Storyarn.Repo
  alias Storyarn.Test.InkCompiler

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  @moduletag :ink_validation

  # =============================================================================
  # Setup
  # =============================================================================

  defp reload_flow(flow), do: Repo.preload(flow, [:nodes, :connections], force: true)

  defp create_project(_context) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  defp default_opts do
    {:ok, opts} = ExportOptions.new(%{format: :ink, validate_before_export: false})
    opts
  end

  defp export_files(project) do
    opts = default_opts()
    project_data = DataCollector.collect(project.id, opts)
    {:ok, files} = Ink.serialize(project_data, opts)
    files
  end

  defp ink_source(files) do
    {_name, content} = Enum.find(files, fn {name, _} -> String.ends_with?(name, ".ink") end)
    content
  end

  # =============================================================================
  # Single-file validation
  # =============================================================================

  describe "inklecate compilation — single file" do
    setup [:create_project]

    test "empty flow compiles", %{project: project} do
      _flow = flow_fixture(project, %{name: "Empty"})
      source = ink_source(export_files(project))

      assert InkCompiler.valid?(source),
             "inklecate rejected empty flow:\n#{inspect(InkCompiler.validate(source))}"
    end

    test "dialogue flow compiles", %{project: project} do
      flow = flow_fixture(project, %{name: "Dialogue"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Welcome traveler!",
            "speaker_sheet_id" => nil,
            "responses" => []
          }
        })

      connection_fixture(flow, entry, dialogue)

      source = ink_source(export_files(project))

      assert InkCompiler.valid?(source),
             "inklecate rejected dialogue flow:\n#{inspect(InkCompiler.validate(source))}"
    end

    test "dialogue with speaker compiles", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Jaime"})
      flow = flow_fixture(project, %{name: "Speaker"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Hello there!",
            "speaker_sheet_id" => sheet.id,
            "responses" => []
          }
        })

      connection_fixture(flow, entry, dialogue)

      source = ink_source(export_files(project))

      assert InkCompiler.valid?(source),
             "inklecate rejected speaker dialogue:\n#{inspect(InkCompiler.validate(source))}"
    end

    test "dialogue with choices compiles", %{project: project} do
      flow = flow_fixture(project, %{name: "Choices"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "What do you do?",
            "speaker_sheet_id" => nil,
            "responses" => [
              %{"id" => "r1", "text" => "Fight", "condition" => nil, "instruction" => nil},
              %{"id" => "r2", "text" => "Flee", "condition" => nil, "instruction" => nil}
            ]
          }
        })

      connection_fixture(flow, entry, dialogue)

      source = ink_source(export_files(project))

      assert InkCompiler.valid?(source),
             "inklecate rejected choices:\n#{inspect(InkCompiler.validate(source))}"
    end

    test "variable declarations compile", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"number" => 100}
      })

      block_fixture(sheet, %{
        type: "boolean",
        config: %{"label" => "Alive"},
        value: %{"boolean" => true}
      })

      block_fixture(sheet, %{
        type: "text",
        config: %{"label" => "Name"},
        value: %{"text" => "Jaime"}
      })

      _flow = flow_fixture(project, %{name: "Main"})

      source = ink_source(export_files(project))

      assert InkCompiler.valid?(source),
             "inklecate rejected variable declarations:\n#{inspect(InkCompiler.validate(source))}"
    end

    test "condition if/else compiles", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Stats"})

      block_fixture(sheet, %{
        type: "boolean",
        config: %{"label" => "Alive"},
        value: %{"boolean" => true}
      })

      flow = flow_fixture(project, %{name: "Condition"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      condition =
        node_fixture(flow, %{
          type: "condition",
          data: %{
            "condition" =>
              Jason.encode!(%{
                "logic" => "all",
                "rules" => [
                  %{
                    "sheet" => sheet.shortcut,
                    "variable" => "alive",
                    "operator" => "is_true"
                  }
                ]
              }),
            "cases" => [
              %{"id" => "true", "value" => "true", "label" => "True"},
              %{"id" => "false", "value" => "false", "label" => "False"}
            ]
          }
        })

      true_dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Still alive!", "speaker_sheet_id" => nil, "responses" => []}
        })

      false_dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Dead...", "speaker_sheet_id" => nil, "responses" => []}
        })

      connection_fixture(flow, entry, condition)
      connection_fixture(flow, condition, true_dialogue, %{source_pin: "true"})
      connection_fixture(flow, condition, false_dialogue, %{source_pin: "false"})

      source = ink_source(export_files(project))

      assert InkCompiler.valid?(source),
             "inklecate rejected condition:\n#{inspect(InkCompiler.validate(source))}"
    end

    test "instruction set commands compile", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Flags"})

      block_fixture(sheet, %{
        type: "boolean",
        config: %{"label" => "Met"},
        value: %{"boolean" => false}
      })

      flow = flow_fixture(project, %{name: "Instruction"})
      flow = reload_flow(flow)
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

      source = ink_source(export_files(project))

      assert InkCompiler.valid?(source),
             "inklecate rejected instruction:\n#{inspect(InkCompiler.validate(source))}"
    end

    test "jump to hub compiles", %{project: project} do
      flow = flow_fixture(project, %{name: "Jump"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{"label" => "checkpoint"}
        })

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "At the checkpoint!", "speaker_sheet_id" => nil, "responses" => []}
        })

      jump =
        node_fixture(flow, %{
          type: "jump",
          data: %{"hub_id" => hub.id}
        })

      connection_fixture(flow, entry, jump)
      connection_fixture(flow, hub, dialogue)

      source = ink_source(export_files(project))

      assert InkCompiler.valid?(source),
             "inklecate rejected jump/hub:\n#{inspect(InkCompiler.validate(source))}"
    end

    test "scene command compiles", %{project: project} do
      flow = flow_fixture(project, %{name: "Scene"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      scene =
        node_fixture(flow, %{
          type: "scene",
          data: %{"location" => "Tavern"}
        })

      connection_fixture(flow, entry, scene)

      source = ink_source(export_files(project))

      assert InkCompiler.valid?(source),
             "inklecate rejected scene:\n#{inspect(InkCompiler.validate(source))}"
    end

    test "conditional choice compiles", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Gold"},
        value: %{"number" => 100}
      })

      flow = flow_fixture(project, %{name: "CondChoice"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Buy something?",
            "speaker_sheet_id" => nil,
            "responses" => [
              %{
                "id" => "r1",
                "text" => "Buy sword",
                "condition" =>
                  Jason.encode!(%{
                    "logic" => "all",
                    "rules" => [
                      %{
                        "sheet" => sheet.shortcut,
                        "variable" => "gold",
                        "operator" => "greater_than",
                        "value" => "50"
                      }
                    ]
                  }),
                "instruction" => nil
              },
              %{"id" => "r2", "text" => "Leave", "condition" => nil, "instruction" => nil}
            ]
          }
        })

      connection_fixture(flow, entry, dialogue)

      source = ink_source(export_files(project))

      assert InkCompiler.valid?(source),
             "inklecate rejected conditional choice:\n#{inspect(InkCompiler.validate(source))}"
    end

    test "complex chain: dialogue -> instruction -> condition -> exit compiles", %{
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Game"})

      block_fixture(sheet, %{
        type: "boolean",
        config: %{"label" => "Visited"},
        value: %{"boolean" => false}
      })

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Score"},
        value: %{"number" => 0}
      })

      flow = flow_fixture(project, %{name: "Complex"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Welcome!", "speaker_sheet_id" => nil, "responses" => []}
        })

      instruction =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{"sheet" => sheet.shortcut, "variable" => "visited", "operator" => "set_true"},
              %{
                "sheet" => sheet.shortcut,
                "variable" => "score",
                "operator" => "add",
                "value" => "10"
              }
            ]
          }
        })

      condition =
        node_fixture(flow, %{
          type: "condition",
          data: %{
            "condition" =>
              Jason.encode!(%{
                "logic" => "all",
                "rules" => [
                  %{
                    "sheet" => sheet.shortcut,
                    "variable" => "score",
                    "operator" => "greater_than",
                    "value" => "5"
                  }
                ]
              }),
            "cases" => [
              %{"id" => "true", "value" => "true", "label" => "True"},
              %{"id" => "false", "value" => "false", "label" => "False"}
            ]
          }
        })

      win_dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "You win!", "speaker_sheet_id" => nil, "responses" => []}
        })

      lose_dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Try again.", "speaker_sheet_id" => nil, "responses" => []}
        })

      connection_fixture(flow, entry, dialogue)
      connection_fixture(flow, dialogue, instruction)
      connection_fixture(flow, instruction, condition)
      connection_fixture(flow, condition, win_dialogue, %{source_pin: "true"})
      connection_fixture(flow, condition, lose_dialogue, %{source_pin: "false"})

      source = ink_source(export_files(project))

      assert InkCompiler.valid?(source),
             "inklecate rejected complex chain:\n#{inspect(InkCompiler.validate(source))}"
    end
  end

  # =============================================================================
  # Audit bug regression tests
  # =============================================================================

  describe "inklecate compilation — audit bug regressions" do
    setup [:create_project]

    # C1: condition else branch uses "- else:" instead of "- False:"
    test "condition else branch compiles (C1)", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Stats"})

      block_fixture(sheet, %{
        type: "boolean",
        config: %{"label" => "Alive"},
        value: %{"boolean" => true}
      })

      flow = flow_fixture(project, %{name: "ElseBranch"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      condition =
        node_fixture(flow, %{
          type: "condition",
          data: %{
            "condition" =>
              Jason.encode!(%{
                "logic" => "all",
                "rules" => [
                  %{
                    "sheet" => sheet.shortcut,
                    "variable" => "alive",
                    "operator" => "is_true"
                  }
                ]
              }),
            "cases" => [
              %{"id" => "true", "value" => "true", "label" => "True"},
              %{"id" => "false", "value" => "false", "label" => "False"}
            ]
          }
        })

      true_dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Still kicking!", "speaker_sheet_id" => nil, "responses" => []}
        })

      false_dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Game over.", "speaker_sheet_id" => nil, "responses" => []}
        })

      connection_fixture(flow, entry, condition)
      connection_fixture(flow, condition, true_dialogue, %{source_pin: "true"})
      connection_fixture(flow, condition, false_dialogue, %{source_pin: "false"})

      source = ink_source(export_files(project))

      assert InkCompiler.valid?(source),
             "inklecate rejected condition else branch (C1):\n#{inspect(InkCompiler.validate(source))}"
    end

    # C2: subflow tunnel returns use ->-> instead of -> END
    test "subflow tunnel returns correctly (C2)", %{project: project} do
      # Create the target flow (will be called as tunnel)
      target_flow = flow_fixture(project, %{name: "Side Quest"})
      target_flow = reload_flow(target_flow)
      target_entry = Enum.find(target_flow.nodes, &(&1.type == "entry"))

      target_dialogue =
        node_fixture(target_flow, %{
          type: "dialogue",
          data: %{"text" => "Side quest done!", "speaker_sheet_id" => nil, "responses" => []}
        })

      target_exit = node_fixture(target_flow, %{type: "exit", data: %{}})
      connection_fixture(target_flow, target_entry, target_dialogue)
      connection_fixture(target_flow, target_dialogue, target_exit)

      # Create the calling flow with a subflow node
      caller_flow = flow_fixture(project, %{name: "Main Quest"})
      caller_flow = reload_flow(caller_flow)
      caller_entry = Enum.find(caller_flow.nodes, &(&1.type == "entry"))

      subflow_node =
        node_fixture(caller_flow, %{
          type: "subflow",
          data: %{"flow_shortcut" => target_flow.shortcut}
        })

      after_dialogue =
        node_fixture(caller_flow, %{
          type: "dialogue",
          data: %{"text" => "Back from side quest!", "speaker_sheet_id" => nil, "responses" => []}
        })

      connection_fixture(caller_flow, caller_entry, subflow_node)
      connection_fixture(caller_flow, subflow_node, after_dialogue)

      source = ink_source(export_files(project))

      # The target flow's exit should use ->-> (tunnel return)
      assert source =~ "->->"

      assert InkCompiler.valid?(source),
             "inklecate rejected subflow tunnel (C2):\n#{inspect(InkCompiler.validate(source))}"
    end

    # H1: digit-starting flow names get _ prefix
    test "digit-starting flow name compiles (H1)", %{project: project} do
      flow = flow_fixture(project, %{name: "1st Quest"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "The first quest!", "speaker_sheet_id" => nil, "responses" => []}
        })

      connection_fixture(flow, entry, dialogue)

      source = ink_source(export_files(project))

      assert InkCompiler.valid?(source),
             "inklecate rejected digit-starting name (H1):\n#{inspect(InkCompiler.validate(source))}"
    end

    # H2: unsupported operator emits valid expression instead of bare comment
    test "unsupported operator does not break syntax (H2)", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Inventory"})

      block_fixture(sheet, %{
        type: "text",
        config: %{"label" => "Weapon"},
        value: %{"text" => "sword"}
      })

      flow = flow_fixture(project, %{name: "UnsupOp"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      condition =
        node_fixture(flow, %{
          type: "condition",
          data: %{
            "condition" =>
              Jason.encode!(%{
                "logic" => "all",
                "rules" => [
                  %{
                    "sheet" => sheet.shortcut,
                    "variable" => "weapon",
                    "operator" => "contains",
                    "value" => "sw"
                  }
                ]
              }),
            "cases" => [
              %{"id" => "true", "value" => "true", "label" => "True"},
              %{"id" => "false", "value" => "false", "label" => "False"}
            ]
          }
        })

      true_dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Has it!", "speaker_sheet_id" => nil, "responses" => []}
        })

      false_dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Nope.", "speaker_sheet_id" => nil, "responses" => []}
        })

      connection_fixture(flow, entry, condition)
      connection_fixture(flow, condition, true_dialogue, %{source_pin: "true"})
      connection_fixture(flow, condition, false_dialogue, %{source_pin: "false"})

      source = ink_source(export_files(project))

      assert InkCompiler.valid?(source),
             "inklecate rejected unsupported operator (H2):\n#{inspect(InkCompiler.validate(source))}"
    end

    # M3: multi-case condition with 3+ branches compiles
    test "multi-case condition compiles (M3)", %{project: project} do
      sheet = sheet_fixture(project, %{name: "World"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Weather"},
        value: %{"number" => 0}
      })

      flow = flow_fixture(project, %{name: "MultiCase"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      condition =
        node_fixture(flow, %{
          type: "condition",
          data: %{
            "condition" =>
              Jason.encode!(%{
                "logic" => "all",
                "rules" => [
                  %{
                    "sheet" => sheet.shortcut,
                    "variable" => "weather",
                    "operator" => "equals",
                    "value" => "0"
                  }
                ]
              }),
            "cases" => [
              %{"id" => "sunny", "value" => "sunny", "label" => "Sunny"},
              %{"id" => "rainy", "value" => "rainy", "label" => "Rainy"},
              %{"id" => "stormy", "value" => "stormy", "label" => "Stormy"}
            ]
          }
        })

      sunny_dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Nice day!", "speaker_sheet_id" => nil, "responses" => []}
        })

      rainy_dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Bring umbrella.", "speaker_sheet_id" => nil, "responses" => []}
        })

      stormy_dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Stay inside!", "speaker_sheet_id" => nil, "responses" => []}
        })

      connection_fixture(flow, entry, condition)
      connection_fixture(flow, condition, sunny_dialogue, %{source_pin: "sunny"})
      connection_fixture(flow, condition, rainy_dialogue, %{source_pin: "rainy"})
      connection_fixture(flow, condition, stormy_dialogue, %{source_pin: "stormy"})

      source = ink_source(export_files(project))

      assert InkCompiler.valid?(source),
             "inklecate rejected 3-case condition (M3):\n#{inspect(InkCompiler.validate(source))}"
    end

    # B1/B2: Dialogue and choice text with square brackets
    test "dialogue with square brackets compiles (B1)", %{project: project} do
      flow = flow_fixture(project, %{name: "Brackets"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Check [inventory] status",
            "speaker_sheet_id" => nil,
            "responses" => [
              %{"id" => "r1", "text" => "Open [bag]", "condition" => nil, "instruction" => nil}
            ]
          }
        })

      connection_fixture(flow, entry, dialogue)

      source = ink_source(export_files(project))

      assert InkCompiler.valid?(source),
             "inklecate rejected brackets in text (B1):\n#{inspect(InkCompiler.validate(source))}"
    end

    # B3: Empty condition expression
    test "empty condition expression compiles (B3)", %{project: project} do
      flow = flow_fixture(project, %{name: "EmptyCond"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      condition =
        node_fixture(flow, %{
          type: "condition",
          data: %{
            "condition" => "not valid json",
            "cases" => [%{"id" => "true", "value" => "true", "label" => "True"}]
          }
        })

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Fallthrough", "speaker_sheet_id" => nil, "responses" => []}
        })

      connection_fixture(flow, entry, condition)
      connection_fixture(flow, condition, dialogue, %{source_pin: "true"})

      source = ink_source(export_files(project))

      assert InkCompiler.valid?(source),
             "inklecate rejected empty condition (B3):\n#{inspect(InkCompiler.validate(source))}"
    end

    # F3: set_if_unset instruction compiles (no /* */ comments)
    test "set_if_unset instruction compiles (F3)", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"number" => 100}
      })

      flow = flow_fixture(project, %{name: "SetIfUnset"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      instruction =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "sheet" => sheet.shortcut,
                "variable" => "health",
                "operator" => "set_if_unset",
                "value" => "50"
              }
            ]
          }
        })

      connection_fixture(flow, entry, instruction)

      source = ink_source(export_files(project))

      assert InkCompiler.valid?(source),
             "inklecate rejected set_if_unset:\n#{inspect(InkCompiler.validate(source))}"
    end

    # B5: String variable with newline
    test "string variable with newline compiles (B5)", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Config"})

      block_fixture(sheet, %{
        type: "text",
        config: %{"label" => "Greeting"},
        value: %{"text" => "Hello\nWorld"}
      })

      _flow = flow_fixture(project, %{name: "Main"})

      source = ink_source(export_files(project))

      assert InkCompiler.valid?(source),
             "inklecate rejected newline in string var (B5):\n#{inspect(InkCompiler.validate(source))}"
    end
  end
end
