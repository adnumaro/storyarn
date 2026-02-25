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
end
