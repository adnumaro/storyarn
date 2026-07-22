defmodule Storyarn.Exports.SizeGuardTest do
  use Storyarn.DataCase, async: false

  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Exports
  alias Storyarn.Exports.DataCollector
  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Exports.SizeGuard
  alias Storyarn.Exports.Validator.ValidationResult
  alias Storyarn.Flows
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Repo

  setup do
    previous_env = Application.get_env(:storyarn, SizeGuard)
    previous_max_bytes = Application.get_env(:storyarn, :max_sync_export_bytes)

    on_exit(fn ->
      if previous_env do
        Application.put_env(:storyarn, SizeGuard, previous_env)
      else
        Application.delete_env(:storyarn, SizeGuard)
      end

      if previous_max_bytes do
        Application.put_env(:storyarn, :max_sync_export_bytes, previous_max_bytes)
      else
        Application.delete_env(:storyarn, :max_sync_export_bytes)
      end
    end)

    :ok
  end

  describe "export size guard" do
    test "rejects exports that exceed configured in-memory limits" do
      project = project_fixture()
      _flow = flow_fixture(project)

      Application.put_env(:storyarn, SizeGuard, limits: %{flows: 0})

      assert {:error, {:export_too_large, details}} =
               Exports.export_project(project, %{
                 format: :storyarn,
                 validate_before_export: false
               })

      assert details.violations == %{flows: %{count: 1, limit: 0}}
      assert details.counts.flows == 1
    end

    test "does not count excluded sections against configured limits" do
      project = project_fixture()
      _flow = flow_fixture(project)

      Application.put_env(:storyarn, SizeGuard, limits: %{flows: 0, nodes: 0})

      assert {:ok, json} =
               Exports.export_project(project, %{
                 format: :storyarn,
                 include_flows: false,
                 validate_before_export: false
               })

      decoded = Jason.decode!(json)
      refute Map.has_key?(decoded, "flows")
    end

    test "does not load excluded flows during validated exports" do
      project = project_fixture()
      flow = flow_fixture(project)
      entry = flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
      Repo.delete!(entry)

      Application.put_env(:storyarn, SizeGuard, limits: %{flows: 0, nodes: 0})

      assert {:ok, json} =
               Exports.export_project(project, %{
                 format: :storyarn,
                 include_flows: false
               })

      decoded = Jason.decode!(json)
      refute Map.has_key?(decoded, "flows")
    end

    test "guards manual export validation before loading oversized data" do
      project = project_fixture()
      _flow = flow_fixture(project)

      Application.put_env(:storyarn, SizeGuard, limits: %{flows: 0})

      assert %ValidationResult{status: :errors, errors: [error]} =
               Exports.validate_project(project.id, %ExportOptions{format: :storyarn})

      assert error.rule == :export_too_large
      assert error.violations == %{flows: %{count: 1, limit: 0}}
    end

    test "rejects oversized source fields before collection and serialization" do
      project = project_fixture(nil, %{description: String.duplicate("large", 200)})

      Application.put_env(:storyarn, :max_sync_export_bytes, 512)
      Application.put_env(:storyarn, SizeGuard, serialization_expansion_factor: 1)

      assert {:error, {:export_too_large, details}} =
               Exports.export_project(project, %{
                 format: :storyarn,
                 validate_before_export: false
               })

      assert details.violations.source_bytes.bytes > 512

      assert details.violations.source_bytes.estimated_output_bytes ==
               details.violations.source_bytes.bytes

      assert details.violations.source_bytes.limit == 512
      assert details.source_bytes.project > 512
      assert details.source_bytes.truncated?
    end

    test "fails closed when the source-byte query budget is exhausted" do
      project = project_fixture()

      Application.put_env(:storyarn, SizeGuard, source_byte_query_timeout_ms: 0)

      assert {:error, {:export_too_large, details}} =
               Exports.export_project(project, %{
                 format: :storyarn,
                 validate_before_export: false
               })

      assert details.violations.source_bytes.reason == :query_timeout
      assert details.violations.source_bytes.timeout_ms == 0
    end
  end

  describe "entity counting" do
    test "counts nested sheet rows and respects selected sheet filters" do
      project = project_fixture()
      selected_sheet = sheet_fixture(project)
      skipped_sheet = sheet_fixture(project)

      selected_table = table_block_fixture(selected_sheet)
      _selected_row = table_row_fixture(selected_table)
      _selected_column = table_column_fixture(selected_table)

      skipped_table = table_block_fixture(skipped_sheet)
      _skipped_row = table_row_fixture(skipped_table)
      _skipped_column = table_column_fixture(skipped_table)

      {:ok, opts} =
        ExportOptions.new(%{
          format: :storyarn,
          sheet_ids: [selected_sheet.id],
          validate_before_export: false
        })

      counts = DataCollector.count_entities(project.id, opts)

      assert counts.sheets == 1
      assert counts.sheet_blocks == 1
      assert counts.table_rows == 2
      assert counts.table_columns == 2
    end

    test "estimates selected source bytes without loading excluded flows" do
      project = project_fixture()
      flow = flow_fixture(project, %{description: String.duplicate("flow", 500)})
      {:ok, _sequence} = Flows.create_sequence(flow.id, %{"name" => "Opening sequence"})

      {:ok, included_opts} =
        ExportOptions.new(%{
          format: :storyarn,
          validate_before_export: false
        })

      {:ok, excluded_opts} =
        ExportOptions.new(%{
          format: :storyarn,
          include_flows: false,
          validate_before_export: false
        })

      assert {:ok, included} = DataCollector.estimate_source_bytes(project.id, included_opts)
      assert {:ok, excluded} = DataCollector.estimate_source_bytes(project.id, excluded_opts)

      assert included.flows > 0
      assert included.nodes > 0
      assert included.sequence_configs > 0
      assert excluded.flows == 0
      assert excluded.nodes == 0
      assert excluded.sequence_configs == 0
      assert included.total_bytes > excluded.total_bytes
    end

    test "stops measuring once the configured source-byte cap is exceeded" do
      project = project_fixture(nil, %{description: String.duplicate("large", 200)})
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, validate_before_export: false})

      assert {:ok, bytes} =
               DataCollector.estimate_source_bytes(project.id, opts, max_bytes: 512)

      assert bytes.project == 513
      assert bytes.total_bytes == 513
      assert bytes.truncated?
      assert bytes.sheets == 0
    end

    test "uses the engine export localization scope for byte estimates" do
      project = project_fixture()
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})

      included_flow = flow_fixture(project)
      included_node = node_fixture(included_flow)
      skipped_flow = flow_fixture(project)
      skipped_node = node_fixture(skipped_flow)
      oversized_text = String.duplicate("archived or out of scope", 200)

      _included =
        localized_text_fixture(project.id, %{
          source_id: included_node.id,
          source_text: "Included"
        })

      archived =
        localized_text_fixture(project.id, %{
          source_id: included_node.id,
          source_field: "stage_directions",
          source_text: oversized_text
        })

      Repo.update_all(
        from(text in LocalizedText, where: text.id == ^archived.id),
        set: [archived_at: DateTime.utc_now(:second), archive_reason: "source_field_removed"]
      )

      _out_of_scope =
        localized_text_fixture(project.id, %{
          source_id: skipped_node.id,
          source_text: oversized_text
        })

      {:ok, engine_opts} =
        ExportOptions.new(%{
          format: :ink,
          flow_ids: [included_flow.id],
          include_sheets: false,
          validate_before_export: false
        })

      {:ok, backup_opts} =
        ExportOptions.new(%{
          format: :storyarn,
          flow_ids: [included_flow.id],
          include_sheets: false,
          validate_before_export: false
        })

      assert {:ok, engine_bytes} = DataCollector.estimate_source_bytes(project.id, engine_opts)
      assert {:ok, backup_bytes} = DataCollector.estimate_source_bytes(project.id, backup_opts)

      assert engine_bytes.localized_texts > 0
      assert backup_bytes.localized_texts > engine_bytes.localized_texts + byte_size(oversized_text)
    end
  end
end
