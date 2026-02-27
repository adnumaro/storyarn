defmodule Storyarn.Exports.Serializers.YarnValidationTest do
  @moduledoc """
  Validates that Yarn export output compiles with the official Yarn Spinner compiler (ysc).

  These tests are ONLY run in CI where ysc is installed. Locally, run with:

      mix test --only ysc_validation

  Requires ysc in PATH. Install via:
      dotnet tool install --global YarnSpinner.Console
  """
  use Storyarn.DataCase, async: true

  alias Storyarn.Exports.{DataCollector, ExportOptions}
  alias Storyarn.Exports.Serializers.Yarn
  alias Storyarn.Repo
  alias Storyarn.Test.YarnCompiler

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  @moduletag :ysc_validation

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
    {:ok, opts} = ExportOptions.new(%{format: :yarn, validate_before_export: false})
    opts
  end

  defp export_files(project) do
    opts = default_opts()
    project_data = DataCollector.collect(project.id, opts)
    {:ok, files} = Yarn.serialize(project_data, opts)
    files
  end

  defp yarn_source(files) do
    {_name, content} = Enum.find(files, fn {name, _} -> String.ends_with?(name, ".yarn") end)
    content
  end

  # =============================================================================
  # Single-file validation
  # =============================================================================

  describe "ysc compilation — single file" do
    setup [:create_project]

    test "empty flow compiles", %{project: project} do
      _flow = flow_fixture(project, %{name: "Empty"})
      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected empty flow:\n#{inspect(YarnCompiler.validate(source))}"
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

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected dialogue flow:\n#{inspect(YarnCompiler.validate(source))}"
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

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected speaker dialogue:\n#{inspect(YarnCompiler.validate(source))}"
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

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected choices:\n#{inspect(YarnCompiler.validate(source))}"
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

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected variable declarations:\n#{inspect(YarnCompiler.validate(source))}"
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

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected condition:\n#{inspect(YarnCompiler.validate(source))}"
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

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected instruction:\n#{inspect(YarnCompiler.validate(source))}"
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

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected jump/hub:\n#{inspect(YarnCompiler.validate(source))}"
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

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected scene:\n#{inspect(YarnCompiler.validate(source))}"
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

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected conditional choice:\n#{inspect(YarnCompiler.validate(source))}"
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

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected complex chain:\n#{inspect(YarnCompiler.validate(source))}"
    end
  end

  # =============================================================================
  # Audit bug regression tests
  # These tests expose known bugs from the Yarn export audit.
  # Each should FAIL until the corresponding bug is fixed.
  # =============================================================================

  describe "ysc compilation — audit bugs" do
    setup [:create_project]

    # C1: null does not exist in Yarn Spinner v2
    test "is_nil condition compiles (C1 — null not valid in Yarn v2)", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Inventory"})

      block_fixture(sheet, %{
        type: "text",
        config: %{"label" => "Weapon"},
        value: %{"text" => ""}
      })

      flow = flow_fixture(project, %{name: "NilCheck"})
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
                    "operator" => "is_nil"
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
          data: %{"text" => "No weapon!", "speaker_sheet_id" => nil, "responses" => []}
        })

      false_dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Armed.", "speaker_sheet_id" => nil, "responses" => []}
        })

      connection_fixture(flow, entry, condition)
      connection_fixture(flow, condition, true_dialogue, %{source_pin: "true"})
      connection_fixture(flow, condition, false_dialogue, %{source_pin: "false"})

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected is_nil condition (C1):\n#{inspect(YarnCompiler.validate(source))}"
    end

    # C1: set_if_unset also uses null
    test "set_if_unset instruction compiles (C1 — null not valid in Yarn v2)", %{
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Config"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Difficulty"},
        value: %{"number" => 1}
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
                "variable" => "difficulty",
                "operator" => "set_if_unset",
                "value" => "3"
              }
            ]
          }
        })

      connection_fixture(flow, entry, instruction)

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected set_if_unset (C1):\n#{inspect(YarnCompiler.validate(source))}"
    end

    # C2: duplicate variable declarations across multiple flows in single-file mode
    test "multiple flows with shared variables compile (C2 — duplicate declares)", %{
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Player"})

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

      # Create 3 flows (<=5 = single-file mode) — all share the same variables
      for name <- ["Intro", "Battle", "Ending"] do
        flow = flow_fixture(project, %{name: name})
        flow = reload_flow(flow)
        entry = Enum.find(flow.nodes, &(&1.type == "entry"))

        dialogue =
          node_fixture(flow, %{
            type: "dialogue",
            data: %{"text" => "#{name} scene.", "speaker_sheet_id" => nil, "responses" => []}
          })

        connection_fixture(flow, entry, dialogue)
      end

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected duplicate declarations (C2):\n#{inspect(YarnCompiler.validate(source))}"
    end

    # H1: node titles starting with digits are invalid in Yarn
    test "flow with digit-starting name compiles (H1 — titles must start with letter)", %{
      project: project
    } do
      flow = flow_fixture(project, %{name: "1st Quest"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "The first quest!", "speaker_sheet_id" => nil, "responses" => []}
        })

      connection_fixture(flow, entry, dialogue)

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected digit-starting title (H1):\n#{inspect(YarnCompiler.validate(source))}"
    end

    # M1: multi-case conditions (3+ branches) produce multiple <<else>> blocks
    test "condition with 3 cases compiles (M1 — multiple else blocks invalid)", %{
      project: project
    } do
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

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected 3-case condition (M1):\n#{inspect(YarnCompiler.validate(source))}"
    end
  end

  # =============================================================================
  # Escape validation (F2)
  # =============================================================================

  describe "ysc compilation — escape characters" do
    setup [:create_project]

    test "dialogue with special characters compiles (F2)", %{project: project} do
      flow = flow_fixture(project, %{name: "EscapeTest"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Item #3 in [chest] costs {gold}",
            "speaker_sheet_id" => nil,
            "responses" => []
          }
        })

      connection_fixture(flow, entry, dialogue)

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected escaped dialogue (F2):\n#{inspect(YarnCompiler.validate(source))}"
    end

    test "choice with special characters compiles (F2)", %{project: project} do
      flow = flow_fixture(project, %{name: "EscapeChoice"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "What do you do?",
            "speaker_sheet_id" => nil,
            "responses" => [
              %{
                "id" => "r1",
                "text" => "Pick up item #1",
                "condition" => nil,
                "instruction" => nil
              },
              %{
                "id" => "r2",
                "text" => "Open [chest]",
                "condition" => nil,
                "instruction" => nil
              }
            ]
          }
        })

      connection_fixture(flow, entry, dialogue)

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected escaped choices (F2):\n#{inspect(YarnCompiler.validate(source))}"
    end
  end

  # =============================================================================
  # Instruction operator validation (T1)
  # =============================================================================

  describe "ysc compilation — instruction operators" do
    setup [:create_project]

    test "add instruction compiles", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Stats"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Score"},
        value: %{"number" => 0}
      })

      flow = flow_fixture(project, %{name: "AddInst"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      instruction =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "sheet" => sheet.shortcut,
                "variable" => "score",
                "operator" => "add",
                "value" => "10"
              }
            ]
          }
        })

      connection_fixture(flow, entry, instruction)

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected add instruction:\n#{inspect(YarnCompiler.validate(source))}"
    end

    test "subtract instruction compiles", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Stats"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"number" => 100}
      })

      flow = flow_fixture(project, %{name: "SubInst"})
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
                "operator" => "subtract",
                "value" => "25"
              }
            ]
          }
        })

      connection_fixture(flow, entry, instruction)

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected subtract instruction:\n#{inspect(YarnCompiler.validate(source))}"
    end

    test "toggle instruction compiles", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Flags"})

      block_fixture(sheet, %{
        type: "boolean",
        config: %{"label" => "Active"},
        value: %{"boolean" => false}
      })

      flow = flow_fixture(project, %{name: "ToggleInst"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      instruction =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "sheet" => sheet.shortcut,
                "variable" => "active",
                "operator" => "toggle"
              }
            ]
          }
        })

      connection_fixture(flow, entry, instruction)

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected toggle instruction:\n#{inspect(YarnCompiler.validate(source))}"
    end

    test "clear instruction compiles", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Text"})

      block_fixture(sheet, %{
        type: "text",
        config: %{"label" => "Note"},
        value: %{"text" => "hello"}
      })

      flow = flow_fixture(project, %{name: "ClearInst"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      instruction =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "sheet" => sheet.shortcut,
                "variable" => "note",
                "operator" => "clear"
              }
            ]
          }
        })

      connection_fixture(flow, entry, instruction)

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected clear instruction:\n#{inspect(YarnCompiler.validate(source))}"
    end

    test "variable-to-variable assignment compiles", %{project: project} do
      sheet_a = sheet_fixture(project, %{name: "Source"})

      block_fixture(sheet_a, %{
        type: "number",
        config: %{"label" => "Max Health"},
        value: %{"number" => 100}
      })

      sheet_b = sheet_fixture(project, %{name: "Target"})

      block_fixture(sheet_b, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"number" => 0}
      })

      flow = flow_fixture(project, %{name: "VarToVar"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      instruction =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "sheet" => sheet_b.shortcut,
                "variable" => "health",
                "operator" => "set",
                "value" => "max_health",
                "value_type" => "variable_ref",
                "value_sheet" => sheet_a.shortcut
              }
            ]
          }
        })

      connection_fixture(flow, entry, instruction)

      source = yarn_source(export_files(project))

      assert YarnCompiler.valid?(source),
             "ysc rejected var-to-var assignment:\n#{inspect(YarnCompiler.validate(source))}"
    end
  end

  # =============================================================================
  # Multi-file validation
  # =============================================================================

  describe "ysc compilation — multi-file" do
    setup [:create_project]

    test "multi-file export compiles together", %{project: project} do
      for i <- 1..6 do
        flow = flow_fixture(project, %{name: "Flow #{i}"})
        flow = reload_flow(flow)
        entry = Enum.find(flow.nodes, &(&1.type == "entry"))

        dialogue =
          node_fixture(flow, %{
            type: "dialogue",
            data: %{
              "text" => "This is flow #{i}.",
              "speaker_sheet_id" => nil,
              "responses" => []
            }
          })

        connection_fixture(flow, entry, dialogue)
      end

      files = export_files(project)

      assert YarnCompiler.validate_multi(files) == :ok,
             "ysc rejected multi-file export:\n#{inspect(YarnCompiler.validate_multi(files))}"
    end

    test "multi-file with cross-flow jumps compiles", %{project: project} do
      flow_a = flow_fixture(project, %{name: "Flow A"})
      flow_b = flow_fixture(project, %{name: "Flow B"})

      flow_a = reload_flow(flow_a)
      entry_a = Enum.find(flow_a.nodes, &(&1.type == "entry"))

      # Flow A jumps to Flow B via subflow node
      subflow =
        node_fixture(flow_a, %{
          type: "subflow",
          data: %{"flow_shortcut" => flow_b.shortcut}
        })

      connection_fixture(flow_a, entry_a, subflow)

      # Flow B has content
      flow_b = reload_flow(flow_b)
      entry_b = Enum.find(flow_b.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow_b, %{
          type: "dialogue",
          data: %{"text" => "Arrived at B!", "speaker_sheet_id" => nil, "responses" => []}
        })

      connection_fixture(flow_b, entry_b, dialogue)

      # Need 6+ flows for multi-file mode
      for i <- 3..6 do
        flow_fixture(project, %{name: "Filler #{i}"})
      end

      files = export_files(project)

      assert YarnCompiler.validate_multi(files) == :ok,
             "ysc rejected cross-flow jump:\n#{inspect(YarnCompiler.validate_multi(files))}"
    end
  end
end
