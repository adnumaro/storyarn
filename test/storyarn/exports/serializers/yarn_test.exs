defmodule Storyarn.Exports.Serializers.YarnTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Exports.{DataCollector, ExportOptions}
  alias Storyarn.Exports.Serializers.Yarn

  alias Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

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

  defp export_yarn(project, opts \\ nil) do
    opts = opts || default_opts()
    project_data = DataCollector.collect(project.id, opts)
    {:ok, files} = Yarn.serialize(project_data, opts)
    files
  end

  defp yarn_source(files) do
    {_name, content} = Enum.find(files, fn {name, _} -> String.ends_with?(name, ".yarn") end)
    content
  end

  defp metadata(files) do
    {_name, content} = Enum.find(files, fn {name, _} -> name == "metadata.json" end)
    Jason.decode!(content)
  end

  # =============================================================================
  # Behaviour callbacks
  # =============================================================================

  describe "behaviour callbacks" do
    test "content_type returns text/plain" do
      assert Yarn.content_type() == "text/plain"
    end

    test "file_extension returns yarn" do
      assert Yarn.file_extension() == "yarn"
    end

    test "format_label returns human-readable name" do
      assert Yarn.format_label() == "Yarn Spinner (.yarn)"
    end

    test "supported_sections lists flows and sheets" do
      sections = Yarn.supported_sections()
      assert :flows in sections
      assert :sheets in sections
    end

    test "serialize_to_file returns not_implemented" do
      assert {:error, :not_implemented} = Yarn.serialize_to_file(nil, "", nil, [])
    end
  end

  # =============================================================================
  # Empty project
  # =============================================================================

  describe "empty project export" do
    setup [:create_project]

    test "produces yarn file and metadata", %{project: project} do
      files = export_yarn(project)
      assert length(files) == 2
      assert Enum.any?(files, fn {name, _} -> String.ends_with?(name, ".yarn") end)
      assert Enum.any?(files, fn {name, _} -> name == "metadata.json" end)
    end

    test "metadata has required fields", %{project: project} do
      meta = metadata(export_yarn(project))
      assert meta["storyarn_yarn_metadata"] == "1.0.0"
      assert is_binary(meta["project"])
    end
  end

  # =============================================================================
  # Variable declarations
  # =============================================================================

  describe "variable declarations" do
    setup [:create_project]

    test "declares variables with correct syntax", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"number" => 100}
      })

      # Need at least one flow for declarations to appear
      _flow = flow_fixture(project, %{name: "Main"})

      source = yarn_source(export_yarn(project))
      assert source =~ "<<declare $"
      assert source =~ "= 100>>"
    end

    test "declares boolean variable", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Flags"})

      block_fixture(sheet, %{
        type: "boolean",
        config: %{"label" => "Met Hero"},
        value: %{"boolean" => false}
      })

      # Need at least one flow for declarations to appear
      _flow = flow_fixture(project, %{name: "Main"})

      source = yarn_source(export_yarn(project))
      assert source =~ "<<declare $"
      assert source =~ "= false>>"
    end
  end

  # =============================================================================
  # Yarn node format
  # =============================================================================

  describe "yarn node format" do
    setup [:create_project]

    test "flow becomes yarn node with title/tags/body", %{project: project} do
      _flow = flow_fixture(project, %{name: "Tavern Intro"})

      source = yarn_source(export_yarn(project))
      assert source =~ "title:"
      assert source =~ "tags:"
      assert source =~ "---"
      assert source =~ "==="
    end

    test "dialogue includes line tag", %{project: project} do
      flow = flow_fixture(project, %{name: "Test Flow"})
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

      source = yarn_source(export_yarn(project))
      assert source =~ "Welcome traveler!"
      assert source =~ "#line:"
    end

    test "dialogue with speaker includes speaker prefix", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Jaime"})
      flow = flow_fixture(project, %{name: "Speaker Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Hello!",
            "speaker_sheet_id" => sheet.id,
            "responses" => []
          }
        })

      connection_fixture(flow, entry, dialogue)

      source = yarn_source(export_yarn(project))
      assert source =~ "Jaime: Hello!"
    end

    test "responses become choices with arrows", %{project: project} do
      flow = flow_fixture(project, %{name: "Choice Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "What now?",
            "speaker_sheet_id" => nil,
            "responses" => [
              %{"id" => "r1", "text" => "Fight", "condition" => nil, "instruction" => nil},
              %{"id" => "r2", "text" => "Flee", "condition" => nil, "instruction" => nil}
            ]
          }
        })

      connection_fixture(flow, entry, dialogue)

      source = yarn_source(export_yarn(project))
      assert source =~ "-> Fight"
      assert source =~ "-> Flee"
    end
  end

  # =============================================================================
  # Special character escaping (F2)
  # =============================================================================

  describe "special character escaping" do
    setup [:create_project]

    test "dialogue text with hashtag escapes it", %{project: project} do
      flow = flow_fixture(project, %{name: "Escape Hash"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Check item #3",
            "speaker_sheet_id" => nil,
            "responses" => []
          }
        })

      connection_fixture(flow, entry, dialogue)

      source = yarn_source(export_yarn(project))
      assert source =~ "Check item \\#3"
    end

    test "dialogue text with brackets escapes them", %{project: project} do
      flow = flow_fixture(project, %{name: "Escape Brackets"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Check [inventory]",
            "speaker_sheet_id" => nil,
            "responses" => []
          }
        })

      connection_fixture(flow, entry, dialogue)

      source = yarn_source(export_yarn(project))
      assert source =~ "Check \\[inventory\\]"
    end

    test "dialogue text with curly braces escapes them", %{project: project} do
      flow = flow_fixture(project, %{name: "Escape Braces"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Use {potion}",
            "speaker_sheet_id" => nil,
            "responses" => []
          }
        })

      connection_fixture(flow, entry, dialogue)

      source = yarn_source(export_yarn(project))
      assert source =~ "Use \\{potion\\}"
    end

    test "response text with special chars escapes them", %{project: project} do
      flow = flow_fixture(project, %{name: "Escape Choice"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "What now?",
            "speaker_sheet_id" => nil,
            "responses" => [
              %{"id" => "r1", "text" => "Option #1", "condition" => nil, "instruction" => nil}
            ]
          }
        })

      connection_fixture(flow, entry, dialogue)

      source = yarn_source(export_yarn(project))
      assert source =~ "-> Option \\#1"
    end

    test "dialogue with backslash escapes it", %{project: project} do
      flow = flow_fixture(project, %{name: "Escape Backslash"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "path\\to\\file",
            "speaker_sheet_id" => nil,
            "responses" => []
          }
        })

      connection_fixture(flow, entry, dialogue)

      source = yarn_source(export_yarn(project))
      assert source =~ "path\\\\to\\\\file"
    end
  end

  # =============================================================================
  # Condition nodes
  # =============================================================================

  describe "condition nodes" do
    setup [:create_project]

    test "condition produces if/endif block", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"number" => 100}
      })

      flow = flow_fixture(project, %{name: "Cond Flow"})
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
                    "variable" => "health",
                    "operator" => "greater_than",
                    "value" => "50"
                  }
                ]
              }),
            "cases" => [
              %{"id" => "true", "value" => "true", "label" => "True"},
              %{"id" => "false", "value" => "false", "label" => "False"}
            ]
          }
        })

      connection_fixture(flow, entry, condition)

      source = yarn_source(export_yarn(project))
      assert source =~ "<<if"
      assert source =~ "<<endif>>"
    end
  end

  # =============================================================================
  # Jump and Hub
  # =============================================================================

  describe "jump and hub nodes" do
    setup [:create_project]

    test "jump produces jump command", %{project: project} do
      flow = flow_fixture(project, %{name: "Jump Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{"label" => "checkpoint"}
        })

      jump =
        node_fixture(flow, %{
          type: "jump",
          data: %{"hub_id" => hub.id}
        })

      connection_fixture(flow, entry, jump)

      source = yarn_source(export_yarn(project))
      assert source =~ "<<jump"
    end
  end

  # =============================================================================
  # Metadata
  # =============================================================================

  describe "metadata sidecar" do
    setup [:create_project]

    test "includes characters", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      meta = metadata(export_yarn(project))
      assert is_map(meta["characters"])
      assert meta["characters"][sheet.shortcut]["name"] == "Hero"
    end

    test "includes variable mapping", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Str"},
        value: %{"number" => 10}
      })

      meta = metadata(export_yarn(project))
      assert is_map(meta["variable_mapping"])
    end

    test "includes flow mapping", %{project: project} do
      flow = flow_fixture(project, %{name: "Main Quest"})

      meta = metadata(export_yarn(project))
      assert is_map(meta["flow_mapping"])
      key = flow.shortcut || flow.name
      assert meta["flow_mapping"][key]
    end
  end

  # =============================================================================
  # Error paths
  # =============================================================================

  describe "error paths" do
    setup [:create_project]

    test "handles flow with only entry node", %{project: project} do
      _flow = flow_fixture(project, %{name: "Empty Flow"})
      files = export_yarn(project)
      source = yarn_source(files)
      assert is_binary(source)
      assert source =~ "title:"
    end

    test "handles dialogue with nil data fields", %{project: project} do
      flow = flow_fixture(project, %{name: "Nil Data"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => nil,
            "speaker_sheet_id" => nil,
            "responses" => []
          }
        })

      connection_fixture(flow, entry, dialogue)

      files = export_yarn(project)
      assert is_list(files)
    end

    test "handles condition with empty expression", %{project: project} do
      flow = flow_fixture(project, %{name: "Empty Cond"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      condition =
        node_fixture(flow, %{
          type: "condition",
          data: %{
            "condition" => "",
            "cases" => [
              %{"id" => "true", "value" => "true", "label" => "True"},
              %{"id" => "false", "value" => "false", "label" => "False"}
            ]
          }
        })

      connection_fixture(flow, entry, condition)

      files = export_yarn(project)
      assert is_list(files)
    end
  end

  # =============================================================================
  # Multi-file mode
  # =============================================================================

  describe "multi-file mode" do
    setup [:create_project]

    test "single file for <= 5 flows", %{project: project} do
      for i <- 1..3 do
        flow_fixture(project, %{name: "Flow #{i}"})
      end

      files = export_yarn(project)
      yarn_files = Enum.filter(files, fn {name, _} -> String.ends_with?(name, ".yarn") end)
      assert length(yarn_files) == 1
    end

    test "multi-file for > 5 flows", %{project: project} do
      for i <- 1..6 do
        flow_fixture(project, %{name: "Flow #{i}"})
      end

      files = export_yarn(project)
      yarn_files = Enum.filter(files, fn {name, _} -> String.ends_with?(name, ".yarn") end)
      assert length(yarn_files) == 6
    end
  end

  # =============================================================================
  # Scene node rendering
  # =============================================================================

  describe "scene nodes" do
    setup [:create_project]

    test "scene node renders scene command", %{project: project} do
      flow = flow_fixture(project, %{name: "Scene Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      scene =
        node_fixture(flow, %{
          type: "scene",
          data: %{"location" => "Tavern Interior"}
        })

      connection_fixture(flow, entry, scene)

      source = yarn_source(export_yarn(project))
      assert source =~ "<<scene Tavern Interior>>"
    end

    test "scene node falls back to slug_line", %{project: project} do
      flow = flow_fixture(project, %{name: "Scene Slug Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      scene =
        node_fixture(flow, %{
          type: "scene",
          data: %{"slug_line" => "INT. CASTLE - NIGHT"}
        })

      connection_fixture(flow, entry, scene)

      source = yarn_source(export_yarn(project))
      assert source =~ "<<scene INT. CASTLE - NIGHT>>"
    end

    test "scene node with empty data renders empty scene", %{project: project} do
      flow = flow_fixture(project, %{name: "Empty Scene Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      scene = node_fixture(flow, %{type: "scene", data: %{}})
      connection_fixture(flow, entry, scene)

      source = yarn_source(export_yarn(project))
      assert source =~ "<<scene >>"
    end
  end

  # =============================================================================
  # Subflow node rendering
  # =============================================================================

  describe "subflow nodes" do
    setup [:create_project]

    test "subflow renders jump command", %{project: project} do
      flow = flow_fixture(project, %{name: "Subflow Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      subflow =
        node_fixture(flow, %{
          type: "subflow",
          data: %{"flow_shortcut" => "side_quest.rescue"}
        })

      connection_fixture(flow, entry, subflow)

      source = yarn_source(export_yarn(project))
      assert source =~ "<<jump side_quest_rescue>>"
    end

    test "subflow without shortcut uses fallback id", %{project: project} do
      flow = flow_fixture(project, %{name: "Subflow Fallback"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      subflow = node_fixture(flow, %{type: "subflow", data: %{}})
      connection_fixture(flow, entry, subflow)

      source = yarn_source(export_yarn(project))
      assert source =~ "<<jump subflow_"
    end
  end

  # =============================================================================
  # Instruction nodes
  # =============================================================================

  describe "instruction nodes" do
    setup [:create_project]

    test "instruction with assignments produces set command", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Flags"})

      block_fixture(sheet, %{
        type: "boolean",
        config: %{"label" => "Met"},
        value: %{"boolean" => false}
      })

      flow = flow_fixture(project, %{name: "Inst Flow"})
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

      source = yarn_source(export_yarn(project))
      assert source =~ "<<set"
    end

    test "instruction with empty assignments produces no output", %{project: project} do
      flow = flow_fixture(project, %{name: "Empty Inst Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      instruction =
        node_fixture(flow, %{
          type: "instruction",
          data: %{"assignments" => []}
        })

      exit_node = node_fixture(flow, %{type: "exit", data: %{}})

      connection_fixture(flow, entry, instruction)
      connection_fixture(flow, instruction, exit_node)

      source = yarn_source(export_yarn(project))
      # Should still produce valid yarn node
      assert source =~ "title:"
    end

    test "instruction with nil data produces no output", %{project: project} do
      flow = flow_fixture(project, %{name: "Nil Inst Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      instruction = node_fixture(flow, %{type: "instruction", data: %{}})
      connection_fixture(flow, entry, instruction)

      source = yarn_source(export_yarn(project))
      assert source =~ "title:"
    end
  end

  # =============================================================================
  # Exit node
  # =============================================================================

  describe "exit nodes" do
    setup [:create_project]

    test "exit node produces no output in Yarn", %{project: project} do
      flow = flow_fixture(project, %{name: "Exit Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))
      exit_node = node_fixture(flow, %{type: "exit", data: %{}})
      connection_fixture(flow, entry, exit_node)

      source = yarn_source(export_yarn(project))
      # Yarn exit produces no special command (empty list)
      assert source =~ "title:"
      refute source =~ "-> END"
    end
  end

  # =============================================================================
  # Condition branching detail
  # =============================================================================

  describe "condition branching" do
    setup [:create_project]

    test "condition with true and false branches renders if/else/endif", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Stats"})

      block_fixture(sheet, %{
        type: "boolean",
        config: %{"label" => "Alive"},
        value: %{"boolean" => true}
      })

      flow = flow_fixture(project, %{name: "Branch Flow"})
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

      source = yarn_source(export_yarn(project))
      assert source =~ "<<if"
      assert source =~ "<<else>>"
      assert source =~ "<<endif>>"
      assert source =~ "Still alive!"
      assert source =~ "Dead..."
    end

    test "condition with nil condition renders if true", %{project: project} do
      flow = flow_fixture(project, %{name: "Nil Cond Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      condition =
        node_fixture(flow, %{
          type: "condition",
          data: %{
            "condition" => nil,
            "cases" => [
              %{"id" => "true", "value" => "true", "label" => "True"}
            ]
          }
        })

      connection_fixture(flow, entry, condition)

      source = yarn_source(export_yarn(project))
      assert source =~ "<<if true>>"
      assert source =~ "<<endif>>"
    end
  end

  # =============================================================================
  # Variable declaration edge cases
  # =============================================================================

  describe "variable declaration edge cases" do
    setup [:create_project]

    test "string variable is declared with quotes", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Config"})

      block_fixture(sheet, %{
        type: "text",
        config: %{"label" => "Title"},
        value: %{"text" => "My Story"}
      })

      _flow = flow_fixture(project, %{name: "Main"})

      source = yarn_source(export_yarn(project))
      assert source =~ "<<declare $"
      assert source =~ ~s("My Story")
    end

    test "select variable is declared as string", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Char"})

      block_fixture(sheet, %{
        type: "select",
        config: %{
          "label" => "Class",
          "options" => [
            %{"value" => "warrior", "label" => "Warrior"},
            %{"value" => "mage", "label" => "Mage"}
          ]
        },
        value: %{"select" => "warrior"}
      })

      _flow = flow_fixture(project, %{name: "Main"})

      source = yarn_source(export_yarn(project))
      assert source =~ "<<declare $"
      assert source =~ ~s("warrior")
    end

    test "constant blocks are excluded", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Constants"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Max HP"},
        value: %{"number" => 999},
        is_constant: true
      })

      _flow = flow_fixture(project, %{name: "Main"})

      source = yarn_source(export_yarn(project))
      refute source =~ "<<declare $"
    end

    test "empty project with no variables produces no declare section", %{project: project} do
      _flow = flow_fixture(project, %{name: "Main"})
      source = yarn_source(export_yarn(project))
      refute source =~ "<<declare"
    end
  end

  # =============================================================================
  # Jump nodes
  # =============================================================================

  describe "jump nodes detail" do
    setup [:create_project]

    test "jump to external flow renders jump", %{project: project} do
      flow = flow_fixture(project, %{name: "Jump Ext Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      jump =
        node_fixture(flow, %{
          type: "jump",
          data: %{"target_flow_shortcut" => "act2.beginning"}
        })

      connection_fixture(flow, entry, jump)

      source = yarn_source(export_yarn(project))
      assert source =~ "<<jump act2_beginning>>"
    end
  end

  # =============================================================================
  # Dialogue with HTML
  # =============================================================================

  describe "dialogue HTML stripping" do
    setup [:create_project]

    test "strips HTML tags from dialogue text", %{project: project} do
      flow = flow_fixture(project, %{name: "HTML Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "<p>Hello <em>world</em>!</p>",
            "speaker_sheet_id" => nil,
            "responses" => []
          }
        })

      connection_fixture(flow, entry, dialogue)

      source = yarn_source(export_yarn(project))
      assert source =~ "Hello world!"
      refute source =~ "<p>"
      refute source =~ "<em>"
    end
  end

  # =============================================================================
  # Metadata detail
  # =============================================================================

  describe "metadata sidecar detail" do
    setup [:create_project]

    test "variable mapping uses $ prefix", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Strength"},
        value: %{"number" => 10}
      })

      meta = metadata(export_yarn(project))
      mapping = meta["variable_mapping"]

      # All values should have $ prefix
      Enum.each(mapping, fn {_key, val} ->
        assert String.starts_with?(val, "$")
      end)
    end

    test "characters include yarn_name field", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      meta = metadata(export_yarn(project))
      char = meta["characters"][sheet.shortcut]
      assert char["yarn_name"] == "Hero"
    end

    test "metadata includes project name", %{project: project} do
      meta = metadata(export_yarn(project))
      assert meta["project"] == project.name
    end

    test "metadata includes required_functions when string ops used", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Text"})

      block_fixture(sheet, %{
        type: "text",
        config: %{"label" => "Desc"},
        value: %{"text" => "hello"}
      })

      flow = flow_fixture(project, %{name: "String Ops"})
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
                    "variable" => "desc",
                    "operator" => "contains",
                    "value" => "test"
                  }
                ]
              }),
            "cases" => [
              %{"id" => "true", "value" => "true", "label" => "True"},
              %{"id" => "false", "value" => "false", "label" => "False"}
            ]
          }
        })

      connection_fixture(flow, entry, condition)

      meta = metadata(export_yarn(project))
      assert "string_contains" in meta["required_functions"]
    end

    test "metadata omits required_functions when no string ops", %{project: project} do
      _flow = flow_fixture(project, %{name: "No String Ops"})
      meta = metadata(export_yarn(project))
      refute Map.has_key?(meta, "required_functions")
    end
  end

  # =============================================================================
  # Flow naming and format
  # =============================================================================

  describe "flow naming" do
    setup [:create_project]

    test "flow comment uses flow name in yarn node", %{project: project} do
      _flow = flow_fixture(project, %{name: "Tavern Scene"})

      source = yarn_source(export_yarn(project))
      assert source =~ "title:"
    end

    test "multi-file uses flow shortcut as filename", %{project: project} do
      for i <- 1..6 do
        flow_fixture(project, %{name: "Flow #{i}"})
      end

      files = export_yarn(project)
      yarn_files = Enum.filter(files, fn {name, _} -> String.ends_with?(name, ".yarn") end)

      Enum.each(yarn_files, fn {name, _} ->
        assert String.ends_with?(name, ".yarn")
      end)
    end
  end

  # =============================================================================
  # Complex multi-node flow
  # =============================================================================

  describe "complex flow chains" do
    setup [:create_project]

    test "entry -> dialogue -> instruction -> exit chain", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Flags"})

      block_fixture(sheet, %{
        type: "boolean",
        config: %{"label" => "Visited"},
        value: %{"boolean" => false}
      })

      flow = flow_fixture(project, %{name: "Chain Flow"})
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
              %{"sheet" => sheet.shortcut, "variable" => "visited", "operator" => "set_true"}
            ]
          }
        })

      connection_fixture(flow, entry, dialogue)
      connection_fixture(flow, dialogue, instruction)

      source = yarn_source(export_yarn(project))
      assert source =~ "Welcome!"
      assert source =~ "<<set"
    end

    test "entry -> scene -> dialogue chain", %{project: project} do
      flow = flow_fixture(project, %{name: "Scene Chain Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      scene =
        node_fixture(flow, %{
          type: "scene",
          data: %{"location" => "Dark Forest"}
        })

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "The forest is dark.", "speaker_sheet_id" => nil, "responses" => []}
        })

      connection_fixture(flow, entry, scene)
      connection_fixture(flow, scene, dialogue)

      source = yarn_source(export_yarn(project))
      assert source =~ "<<scene Dark Forest>>"
      assert source =~ "The forest is dark."
    end

    test "hub referenced by jump creates separate yarn node", %{project: project} do
      flow = flow_fixture(project, %{name: "Hub Jump Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{"label" => "checkpoint"}
        })

      jump =
        node_fixture(flow, %{
          type: "jump",
          data: %{"hub_id" => hub.id}
        })

      dialogue_after_hub =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "At the checkpoint!", "speaker_sheet_id" => nil, "responses" => []}
        })

      connection_fixture(flow, entry, jump)
      connection_fixture(flow, hub, dialogue_after_hub)

      source = yarn_source(export_yarn(project))
      assert source =~ "<<jump checkpoint>>"
    end

    test "dialogue with choices having conditions renders if guards", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Gold"},
        value: %{"number" => 100}
      })

      flow = flow_fixture(project, %{name: "Guard Flow"})
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

      source = yarn_source(export_yarn(project))
      assert source =~ "-> Buy sword"
      assert source =~ "-> Leave"
      # The conditional choice should have <<if>> guard before #line: tag
      assert source =~ "<<if"
      assert source =~ ~r/-> Buy sword <<if .+>> #line:/
    end
  end
end
