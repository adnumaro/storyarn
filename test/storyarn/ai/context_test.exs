defmodule Storyarn.AI.ContextTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.AI.CanonicalJSON
  alias Storyarn.AI.Context
  alias Storyarn.AI.Context.Entity
  alias Storyarn.AI.Context.Finalizer
  alias Storyarn.AI.Context.Package
  alias Storyarn.AI.Context.Policy
  alias Storyarn.AI.Context.SubjectRef
  alias Storyarn.AI.Operation
  alias Storyarn.AI.Task
  alias Storyarn.Flows
  alias Storyarn.Sheets.Block
  alias StoryarnTest.AI.ContextTask
  alias StoryarnTest.AI.ContextWithoutStalenessTask

  setup do
    scope = user_scope_fixture()
    project = project_fixture(scope.user)

    %{scope: scope, project: project}
  end

  describe "build_context/3" do
    test "builds dialogue context deterministically and always retains the selected response", %{
      scope: scope,
      project: project
    } do
      speaker = sheet_fixture(project, %{name: "Ariadna"})
      _summary = block_fixture(speaker, %{config: %{"label" => "Summary"}, value: %{"content" => "Cartógrafa"}})

      flow = flow_fixture(project, %{name: "Arrival"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => speaker.id,
            "text" => "¿Dónde estamos?",
            "responses" => [
              %{"id" => "a", "text" => "Primera"},
              %{"id" => "z", "text" => "Seleccionada"}
            ]
          }
        })

      task =
        task(%{
          scope: :dialogue,
          max_depth: 0,
          max_fan_out: 1,
          max_entities: 10,
          max_bytes: 16_384,
          tokenizer: nil,
          fields: %{speaker_blocks: ["Summary"]}
        })

      {:ok, ref} =
        SubjectRef.dialogue(project.workspace_id, project.id, node.id, response_id: "z")

      assert {:ok, first} = Context.build_context(scope, task, ref)
      assert {:ok, second} = Context.build_context(scope, task, ref)
      assert first.hash == second.hash
      assert first.payload == second.payload
      assert first.manifest == second.manifest
      assert first.warnings == ["optional_context_truncated"]

      assert Enum.any?(first.payload["entities"], fn entity ->
               entity["type"] == "dialogue_response" and entity["id"] == "z"
             end)

      assert Enum.any?(first.manifest.excluded, &(&1["id"] == "a" and &1["reason"] == "fan_out_limit"))
    end

    test "bounds the response exclusion manifest while preserving the omitted count", %{
      scope: scope,
      project: project
    } do
      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Choose",
            "responses" =>
              Enum.map(1..8, fn index ->
                %{"id" => "response-#{index}", "text" => "Response #{index}"}
              end)
          }
        })

      task =
        task(%{
          scope: :dialogue,
          max_depth: 0,
          max_fan_out: 1,
          max_entities: 3,
          max_bytes: 16_384,
          tokenizer: nil,
          fields: %{}
        })

      {:ok, ref} = SubjectRef.dialogue(project.workspace_id, project.id, node.id)

      assert {:ok, package} = Context.build_context(scope, task, ref)
      assert length(package.manifest.excluded) == 4
      assert Package.excluded_count(package) == 7

      assert Enum.any?(package.manifest.excluded, fn item ->
               item["type"] == "dialogue_response_overflow" and item["omitted_count"] == 4
             end)
    end

    test "discloses speaker block fan-out overflow", %{scope: scope, project: project} do
      speaker = sheet_fixture(project, %{name: "Ariadna"})

      first =
        block_fixture(speaker, %{
          config: %{"label" => "Summary"},
          value: %{"content" => "First"}
        })

      second =
        block_fixture(speaker, %{
          config: %{"label" => "Biography"},
          value: %{"content" => "Second"}
        })

      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker_sheet_id" => speaker.id, "text" => "Hello"}
        })

      task =
        task(%{
          scope: :dialogue,
          max_depth: 0,
          max_fan_out: 1,
          max_entities: 10,
          max_bytes: 16_384,
          tokenizer: nil,
          fields: %{speaker_blocks: ["Summary", "Biography"]}
        })

      {:ok, ref} = SubjectRef.dialogue(project.workspace_id, project.id, node.id)

      assert {:ok, package} = Context.build_context(scope, task, ref)
      assert "optional_context_truncated" in package.warnings

      included_block_ids =
        for %{"type" => "sheet_block", "id" => id} <- package.payload["entities"], do: id

      assert included_block_ids == [first.id]

      assert Enum.any?(
               package.manifest.excluded,
               &(&1["type"] == "sheet_block" and &1["id"] == second.id and
                   &1["reason"] == "fan_out_limit")
             )
    end

    test "enforces project permission isolation before loading context", %{project: project} do
      flow = flow_fixture(project)
      node = node_fixture(flow)
      foreign_scope = user_scope_fixture()
      task = flow_task()

      {:ok, ref} = SubjectRef.flow_neighborhood(project.workspace_id, project.id, node.id)

      assert {:error, :unauthorized_context} = Context.build_context(foreign_scope, task, ref)
    end

    test "bounds flow depth and fan-out with a stable exclusion manifest", %{
      scope: scope,
      project: project
    } do
      flow = flow_fixture(project)
      selected = node_fixture(flow, %{data: %{"text" => "Selected"}})
      first = node_fixture(flow, %{data: %{"text" => "First"}})
      second = node_fixture(flow, %{data: %{"text" => "Second"}})
      third = node_fixture(flow, %{data: %{"text" => "Third"}})
      _connection_a = connection_fixture(flow, selected, first)
      _connection_b = connection_fixture(flow, selected, second)
      _connection_c = connection_fixture(flow, first, third)

      task =
        task(%{
          scope: :flow_neighborhood,
          max_depth: 1,
          max_fan_out: 1,
          max_entities: 8,
          max_bytes: 16_384,
          tokenizer: nil,
          fields: %{}
        })

      {:ok, ref} = SubjectRef.flow_neighborhood(project.workspace_id, project.id, selected.id)

      assert {:ok, package} = Context.build_context(scope, task, ref)
      assert "depth_limit_reached" in package.warnings
      assert "optional_context_truncated" in package.warnings
      assert Enum.any?(package.manifest.excluded, &(&1["reason"] == "fan_out_limit"))
      assert length(package.manifest.included) <= task.context_policy.max_entities
      assert package.serialized_bytes <= task.context_policy.max_bytes

      included_keys = MapSet.new(package.manifest.included, &{&1["type"], &1["id"]})
      excluded_keys = MapSet.new(package.manifest.excluded, &{&1["type"], &1["id"]})
      assert MapSet.disjoint?(included_keys, excluded_keys)

      node_ids =
        package.payload["entities"]
        |> Enum.filter(&(&1["type"] == "flow_node"))
        |> Enum.map(& &1["id"])

      assert selected.id in node_ids
      assert length(node_ids) == 2
    end

    test "continues breadth-first traversal when the parent edge already consumed a prior level", %{
      scope: scope,
      project: project
    } do
      flow = flow_fixture(project)
      selected = node_fixture(flow, %{data: %{"text" => "Selected"}})
      first = node_fixture(flow, %{data: %{"text" => "First"}})
      second = node_fixture(flow, %{data: %{"text" => "Second"}})
      first_connection = connection_fixture(flow, selected, first)
      second_connection = connection_fixture(flow, first, second)

      task =
        task(%{
          scope: :flow_neighborhood,
          max_depth: 2,
          max_fan_out: 1,
          max_entities: 10,
          max_bytes: 16_384,
          tokenizer: nil,
          fields: %{}
        })

      {:ok, ref} = SubjectRef.flow_neighborhood(project.workspace_id, project.id, selected.id)

      assert {:ok, package} = Context.build_context(scope, task, ref)

      node_ids =
        for %{"type" => "flow_node", "id" => id} <- package.payload["entities"], do: id

      connection_ids =
        for %{"type" => "flow_connection", "id" => id} <- package.payload["entities"], do: id

      assert Enum.sort(node_ids) == Enum.sort([selected.id, first.id, second.id])
      assert Enum.sort(connection_ids) == Enum.sort([first_connection.id, second_connection.id])
      refute Enum.any?(package.manifest.excluded, &(&1["reason"] == "fan_out_limit"))
    end

    test "records every bounded fan-out overflow instead of only the first", %{
      scope: scope,
      project: project
    } do
      flow = flow_fixture(project)
      selected = node_fixture(flow)

      connections =
        for _index <- 1..4 do
          neighbor = node_fixture(flow)
          connection_fixture(flow, selected, neighbor)
        end

      task =
        task(%{
          scope: :flow_neighborhood,
          max_depth: 1,
          max_fan_out: 1,
          max_entities: 20,
          max_bytes: 16_384,
          tokenizer: nil,
          fields: %{}
        })

      {:ok, ref} = SubjectRef.flow_neighborhood(project.workspace_id, project.id, selected.id)

      assert {:ok, package} = Context.build_context(scope, task, ref)

      included_connection_ids =
        for %{"type" => "flow_connection", "id" => id} <- package.payload["entities"], do: id

      excluded_connection_ids =
        for %{"type" => "flow_connection", "id" => id, "reason" => "fan_out_limit"} <-
              package.manifest.excluded,
            do: id

      [included | overflow] = connections
      assert included_connection_ids == [included.id]
      assert Enum.sort(excluded_connection_ids) == Enum.sort(Enum.map(overflow, & &1.id))
    end

    test "disclosure and telemetry count entities represented by bounded overflow summaries", %{
      scope: scope,
      project: project
    } do
      flow = flow_fixture(project)
      selected = node_fixture(flow)

      for _index <- 1..8 do
        neighbor = node_fixture(flow)
        _connection = connection_fixture(flow, selected, neighbor)
      end

      task =
        task(%{
          scope: :flow_neighborhood,
          max_depth: 1,
          max_fan_out: 1,
          max_entities: 4,
          max_bytes: 16_384,
          tokenizer: nil,
          fields: %{}
        })

      handler_id = "context-overflow-count-#{System.unique_integer([:positive])}"
      caller = self()

      :ok =
        :telemetry.attach(
          handler_id,
          [:ai, :context, :build],
          fn _event, measurements, _metadata, test_pid ->
            send(test_pid, {:context_overflow_telemetry, measurements})
          end,
          caller
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, ref} = SubjectRef.flow_neighborhood(project.workspace_id, project.id, selected.id)

      assert {:ok, package} = Context.build_context(scope, task, ref)
      assert length(package.manifest.excluded) == 5
      assert Package.excluded_count(package) == 7
      assert Package.disclosure(package).excluded_count == 7
      assert_receive {:context_overflow_telemetry, %{excluded_count: 7}}
    end

    test "enforces the entity budget inside dense flow traversal", %{
      project: project
    } do
      flow = flow_fixture(project)
      selected = node_fixture(flow)

      for _index <- 1..6 do
        neighbor = node_fixture(flow)
        _connection = connection_fixture(flow, selected, neighbor)
      end

      assert {:ok, neighborhood} =
               Flows.get_context_neighborhood(project.id, selected.id, 1, 10, 4)

      loaded_count = 1 + map_size(neighborhood.nodes) + map_size(neighborhood.connections)
      assert loaded_count <= 4
      assert Enum.any?(neighborhood.excluded, &(&1["reason"] == "entity_limit"))
    end

    test "rejects required sheet context that exceeds entity or byte caps", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project)
      first = block_fixture(sheet, %{value: %{"content" => String.duplicate("á", 120)}})
      second = block_fixture(sheet, %{value: %{"content" => "required"}})

      entity_limited =
        sheet_task(%{
          max_entities: 2,
          max_bytes: 16_384
        })

      {:ok, ref} =
        SubjectRef.sheet(project.workspace_id, project.id, sheet.id, block_ids: [first.id, second.id])

      assert {:error, :context_too_large} = Context.build_context(scope, entity_limited, ref)

      byte_limited = sheet_task(%{max_entities: 10, max_bytes: 180})
      assert {:error, :context_too_large} = Context.build_context(scope, byte_limited, ref)
    end

    test "discloses soft-deleted explicit blocks without leaking their content", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project)
      active = block_fixture(sheet, %{value: %{"content" => "visible"}})
      deleted = block_fixture(sheet, %{value: %{"content" => "must not leak"}})
      Repo.update!(Block.delete_changeset(deleted))

      {:ok, ref} =
        SubjectRef.sheet(project.workspace_id, project.id, sheet.id, block_ids: [active.id, deleted.id])

      assert {:ok, package} = Context.build_context(scope, sheet_task(), ref)
      assert package.warnings == ["stale_reference"]
      assert Enum.any?(package.manifest.excluded, &(&1["id"] == deleted.id))
      refute inspect(package.payload) =~ "must not leak"
    end

    test "detects a source revision change through the stable context hash", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project)
      block = block_fixture(sheet, %{value: %{"content" => "before"}})
      task = sheet_task()

      {:ok, ref} =
        SubjectRef.sheet(project.workspace_id, project.id, sheet.id, block_ids: [block.id])

      assert {:ok, package} = Context.build_context(scope, task, ref)

      block
      |> Block.update_changeset(%{value: %{"content" => "after"}})
      |> Repo.update!()

      assert {:error, :stale_context} = Context.current?(scope, task, ref, package.hash)
    end

    test "a warning-only context change invalidates the stable hash", %{
      scope: scope,
      project: project
    } do
      flow = flow_fixture(project)
      selected = node_fixture(flow)

      task =
        task(%{
          scope: :flow_neighborhood,
          max_depth: 0,
          max_fan_out: 5,
          max_entities: 10,
          max_bytes: 16_384,
          tokenizer: nil,
          fields: %{}
        })

      {:ok, ref} = SubjectRef.flow_neighborhood(project.workspace_id, project.id, selected.id)

      assert {:ok, before_package} = Context.build_context(scope, task, ref)
      assert before_package.warnings == []

      neighbor = node_fixture(flow)
      _connection = connection_fixture(flow, selected, neighbor)

      assert {:ok, after_package} = Context.build_context(scope, task, ref)
      assert after_package.warnings == ["depth_limit_reached"]
      assert before_package.payload == after_package.payload
      assert before_package.manifest == after_package.manifest
      refute before_package.hash == after_package.hash
      assert {:error, :stale_context} = Context.current?(scope, task, ref, before_package.hash)
    end

    test "reports exact UTF-8 bytes and an optional tokenizer count", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "日本語とespañol"})
      block = block_fixture(sheet, %{value: %{"content" => "こんにちは 👋🏽 — acción"}})

      task =
        sheet_task(%{
          tokenizer: StoryarnTest.AI.GraphemeTokenizer,
          max_bytes: 16_384
        })

      {:ok, ref} =
        SubjectRef.sheet(project.workspace_id, project.id, sheet.id, block_ids: [block.id])

      assert {:ok, package} = Context.build_context(scope, task, ref)
      assert {:ok, encoded} = CanonicalJSON.encode(package.payload)
      assert package.serialized_bytes == byte_size(encoded)
      assert package.token_count == length(String.graphemes(encoded))
    end

    test "loads only the selected bounded sheet set even in a larger project", %{
      scope: scope,
      project: project
    } do
      selected = sheet_fixture(project, %{name: "Selected"})
      selected_block = block_fixture(selected, %{value: %{"content" => "selected-only"}})

      for index <- 1..30 do
        unrelated = sheet_fixture(project, %{name: "Unrelated #{index}"})
        _block = block_fixture(unrelated, %{value: %{"content" => "unrelated-#{index}"}})
      end

      {:ok, ref} =
        SubjectRef.sheet(project.workspace_id, project.id, selected.id, block_ids: [selected_block.id])

      assert {:ok, package} = Context.build_context(scope, sheet_task(), ref)
      assert length(package.manifest.included) == 2
      assert inspect(package.payload) =~ "selected-only"
      refute inspect(package.payload) =~ "unrelated-"

      refute File.read!("lib/storyarn/ai/context.ex") =~ "DataCollector"
    end

    test "loads direct sheet and flow references in bounded batches without crossing projects", %{
      scope: scope,
      project: project
    } do
      source = sheet_fixture(project, %{name: "Source"})
      local_sheet = sheet_fixture(project, %{name: "Local target"})
      local_flow = flow_fixture(project, %{name: "Local flow"})

      sheet_reference =
        block_fixture(source, %{
          type: "reference",
          config: %{"label" => "Sheet", "allowed_types" => ["sheet", "flow"]},
          value: %{"target_type" => "sheet", "target_id" => local_sheet.id}
        })

      flow_reference =
        block_fixture(source, %{
          type: "reference",
          config: %{"label" => "Flow", "allowed_types" => ["sheet", "flow"]},
          value: %{"target_type" => "flow", "target_id" => local_flow.id}
        })

      foreign_scope = user_scope_fixture()
      foreign_project = project_fixture(foreign_scope.user)
      foreign_sheet = sheet_fixture(foreign_project, %{name: "Must stay private"})

      stale_reference =
        block_fixture(source, %{
          type: "reference",
          config: %{"label" => "Stale", "allowed_types" => ["sheet", "flow"]},
          value: %{"target_type" => "sheet", "target_id" => local_sheet.id}
        })

      stale_reference
      |> Block.value_changeset(%{value: %{"target_type" => "sheet", "target_id" => foreign_sheet.id}})
      |> Repo.update!()

      {:ok, ref} =
        SubjectRef.sheet(project.workspace_id, project.id, source.id,
          block_ids: [sheet_reference.id, flow_reference.id, stale_reference.id]
        )

      assert {:ok, package} = Context.build_context(scope, sheet_task(), ref)
      assert Enum.any?(package.manifest.included, &(&1["type"] == "sheet" and &1["id"] == local_sheet.id))
      assert Enum.any?(package.manifest.included, &(&1["type"] == "flow" and &1["id"] == local_flow.id))

      assert Enum.any?(
               package.manifest.excluded,
               &(&1["type"] == "sheet" and &1["id"] == foreign_sheet.id and
                   &1["reason"] == "stale_reference")
             )

      refute inspect(package.payload) =~ "Must stay private"
    end

    test "a sheet self-reference reuses the selected sheet entity", %{
      scope: scope,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Self reference"})

      reference =
        block_fixture(sheet, %{
          type: "reference",
          config: %{"label" => "Self", "allowed_types" => ["sheet"]},
          value: %{"target_type" => "sheet", "target_id" => sheet.id}
        })

      {:ok, ref} =
        SubjectRef.sheet(project.workspace_id, project.id, sheet.id, block_ids: [reference.id])

      assert {:ok, package} = Context.build_context(scope, sheet_task(), ref)

      included_sheet_ids =
        for %{"type" => "sheet", "id" => id} <- package.payload["entities"], do: id

      assert included_sheet_ids == [sheet.id]
      assert length(package.manifest.included) == 2
    end

    test "builds a structural finding only when all required evidence fits", %{
      scope: scope,
      project: project
    } do
      flow = flow_fixture(project)
      first_node = node_fixture(flow, %{data: %{"text" => "Loaded from the project"}})
      second_node = node_fixture(flow)

      task =
        task(%{
          scope: :structural_finding,
          max_depth: 0,
          max_fan_out: 1,
          max_entities: 3,
          max_bytes: 8_192,
          tokenizer: nil,
          fields: %{}
        })

      {:ok, ref} =
        SubjectRef.structural_finding(
          project.workspace_id,
          project.id,
          "orphan-node",
          %{"severity" => "warning"},
          [%{"type" => "flow_node", "id" => first_node.id}]
        )

      assert {:ok, package} = Context.build_context(scope, task, ref)
      assert length(package.manifest.included) == 2
      assert hd(package.payload["entities"])["type"] == "structural_finding"

      assert Enum.any?(package.payload["entities"], fn entity ->
               entity["type"] == "flow_node" and entity["id"] == first_node.id and
                 entity["content"]["data"]["text"] == "Loaded from the project"
             end)

      {:ok, oversized_ref} =
        SubjectRef.structural_finding(
          project.workspace_id,
          project.id,
          "orphan-node",
          %{"severity" => "warning"},
          [
            %{"type" => "flow_node", "id" => first_node.id},
            %{"type" => "flow_node", "id" => second_node.id}
          ]
        )

      assert {:error, :context_too_large} = Context.build_context(scope, task, oversized_ref)
    end

    test "rejects duplicate structural evidence identities", %{project: project} do
      evidence = [
        %{"type" => "flow_node", "id" => 42},
        %{"type" => "flow_node", "id" => 42}
      ]

      assert {:error, :invalid_context_subject} =
               SubjectRef.structural_finding(
                 project.workspace_id,
                 project.id,
                 "duplicate-evidence",
                 %{"severity" => "warning"},
                 evidence
               )

      assert {:error, :invalid_context_subject} =
               SubjectRef.structural_finding(
                 project.workspace_id,
                 project.id,
                 "invalid-evidence",
                 %{"severity" => "warning"},
                 [:invalid]
               )

      assert {:error, :invalid_context_subject} =
               SubjectRef.structural_finding(
                 project.workspace_id,
                 project.id,
                 "caller-content",
                 %{"severity" => "warning"},
                 [%{"type" => "flow_node", "id" => 42, "content" => %{"secret" => true}}]
               )
    end

    test "structural evidence cannot cross project boundaries", %{scope: scope, project: project} do
      foreign_project = project_fixture(scope.user)
      foreign_flow = flow_fixture(foreign_project)
      foreign_node = node_fixture(foreign_flow, %{data: %{"text" => "Must stay private"}})

      {:ok, ref} =
        SubjectRef.structural_finding(
          project.workspace_id,
          project.id,
          "foreign-node",
          %{"severity" => "warning"},
          [%{"type" => "flow_node", "id" => foreign_node.id}]
        )

      assert {:error, :context_missing} =
               Context.build_context(
                 scope,
                 task(%{
                   scope: :structural_finding,
                   max_depth: 0,
                   max_fan_out: 1,
                   max_entities: 3,
                   max_bytes: 8_192,
                   tokenizer: nil,
                   fields: %{}
                 }),
                 ref
               )
    end

    test "rejects task policies that could request project-scale context" do
      refute Policy.valid?(%{
               scope: :flow_neighborhood,
               max_depth: 13,
               max_fan_out: 50,
               max_entities: 500,
               max_bytes: 524_288,
               tokenizer: nil,
               fields: %{}
             })
    end

    test "requires a durable staleness callback for non-persistable structural context" do
      assert {:error, errors} =
               Task.new(ContextWithoutStalenessTask, ContextWithoutStalenessTask.definition())

      assert :missing_context_staleness_check in errors
    end

    test "structural staleness callbacks fail closed unless they return exactly true", %{
      scope: scope
    } do
      task =
        task(%{
          scope: :structural_finding,
          max_depth: 0,
          max_fan_out: 1,
          max_entities: 3,
          max_bytes: 8_192,
          tokenizer: nil,
          fields: %{}
        })

      operation = %Operation{
        context_hash: String.duplicate("0", 64),
        context_manifest: %{},
        context_subject: nil
      }

      key = {ContextTask, :subject_current?}

      try do
        for callback_result <- [false, nil, :unknown, {:error, :unavailable}] do
          Process.put(key, callback_result)
          refute Task.subject_current?(task, operation)
          assert {:error, :stale_context} = Context.operation_current?(scope, task, operation)
        end

        Process.put(key, true)
        assert Task.subject_current?(task, operation)
        assert :ok = Context.operation_current?(scope, task, operation)
      after
        Process.delete(key)
      end
    end

    test "final serialization and hash are invariant to builder entity order" do
      assert {:ok, policy} =
               Policy.new(%{
                 scope: :sheet,
                 max_depth: 0,
                 max_fan_out: 5,
                 max_entities: 5,
                 max_bytes: 4_096,
                 tokenizer: nil,
                 fields: %{}
               })

      assert {:ok, sheet} =
               Entity.new("sheet", 2, %{"name" => "B"}, required: true, priority: 1)

      assert {:ok, block} =
               Entity.new("sheet_block", 7, %{"value" => "A"}, priority: 3)

      excluded = [
        %{"type" => "sheet_block", "id" => 9, "reason" => "stale_reference"},
        %{"type" => "sheet_block", "id" => 8, "reason" => "entity_limit"}
      ]

      assert {:ok, first} =
               Finalizer.finalize(policy, "context-v1", [block, sheet], excluded, ["stale_reference"])

      assert {:ok, second} =
               Finalizer.finalize(policy, "context-v1", [sheet, block], Enum.reverse(excluded), ["stale_reference"])

      assert first.payload == second.payload
      assert first.manifest == second.manifest
      assert first.hash == second.hash
      assert first.serialized_bytes == second.serialized_bytes
    end

    test "finalization rejects duplicate entity identities" do
      assert {:ok, policy} =
               Policy.new(%{
                 scope: :sheet,
                 max_depth: 0,
                 max_fan_out: 5,
                 max_entities: 5,
                 max_bytes: 4_096,
                 tokenizer: nil,
                 fields: %{}
               })

      assert {:ok, selected} =
               Entity.new("sheet", 7, %{"name" => "Selected"}, required: true, priority: 1)

      assert {:ok, duplicate} =
               Entity.new("sheet", 7, %{"name" => "Duplicate"}, required: true, priority: 2)

      assert {:error, :invalid_context_entities} =
               Finalizer.finalize(policy, "context-v1", [selected, duplicate])
    end

    test "emits only content-free context telemetry", %{scope: scope, project: project} do
      sheet = sheet_fixture(project, %{name: "Private draft"})
      block = block_fixture(sheet, %{value: %{"content" => "never emit this content"}})
      task = sheet_task()
      handler_id = "context-build-#{System.unique_integer([:positive])}"
      caller = self()

      :ok =
        :telemetry.attach(
          handler_id,
          [:ai, :context, :build],
          fn event, measurements, metadata, {test_pid, source_pid} ->
            if self() == source_pid do
              send(test_pid, {:context_telemetry, event, measurements, metadata})
            end
          end,
          {caller, caller}
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, ref} =
        SubjectRef.sheet(project.workspace_id, project.id, sheet.id, block_ids: [block.id])

      assert {:ok, package} = Context.build_context(scope, task, ref)

      assert_receive {:context_telemetry, [:ai, :context, :build], measurements, metadata}
      assert measurements.serialized_bytes == package.serialized_bytes
      assert measurements.included_count == 2
      assert measurements.excluded_count == 0
      assert measurements.truncated == 0

      assert metadata == %{
               task_id: task.id,
               status: "ok",
               context_version: task.context_version,
               context_scope: "sheet",
               builder_version: package.version,
               context_hash: package.hash
             }

      refute inspect({measurements, metadata}) =~ "Private draft"
      refute inspect({measurements, metadata}) =~ "never emit this content"
    end
  end

  defp flow_task do
    task(%{
      scope: :flow_neighborhood,
      max_depth: 2,
      max_fan_out: 5,
      max_entities: 20,
      max_bytes: 16_384,
      tokenizer: nil,
      fields: %{}
    })
  end

  defp sheet_task(overrides \\ %{}) do
    policy =
      Map.merge(
        %{
          scope: :sheet,
          max_depth: 0,
          max_fan_out: 10,
          max_entities: 20,
          max_bytes: 16_384,
          tokenizer: nil,
          fields: %{}
        },
        overrides
      )

    task(policy)
  end

  defp task(policy) do
    attrs = Map.put(ContextTask.definition(), :context_policy, policy)
    assert {:ok, task} = Task.new(ContextTask, attrs)
    task
  end
end
