defmodule Storyarn.AI.Tasks.FlowFindingExplanationTest do
  use Storyarn.DataCase

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.AI.Context.SubjectRef
  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.Operation
  alias Storyarn.AI.Task
  alias Storyarn.AI.TaskRegistry
  alias Storyarn.AI.Tasks.FlowFindingExplanation
  alias Storyarn.Flows

  setup do
    user = user_fixture()
    scope = Storyarn.Accounts.Scope.for_user(user)
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = flow_fixture(project)

    entry = flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
    stuck = node_fixture(flow, %{type: "dialogue"})
    connection_fixture(flow, entry, stuck)

    {:ok, analysis} = Flows.analyze_flow_structure(project.id, flow.id)
    [finding] = Enum.filter(analysis.findings, &(&1.rule_id == "no_outgoing_connection"))

    %{user: user, scope: scope, project: project, flow: flow, finding: finding, stuck: stuck}
  end

  defp intent(context, overrides \\ %{}) do
    %{scope: scope, project: project, flow: flow, finding: finding} = context

    attrs =
      Map.merge(
        %{
          workspace_id: project.workspace_id,
          project_id: project.id,
          task_id: FlowFindingExplanation.task_id(),
          input: FlowFindingExplanation.input(finding, "en"),
          subject: FlowFindingExplanation.subject(flow.id, finding)
        },
        overrides
      )

    {:ok, intent} = ExecutionIntent.new(scope, attrs)
    intent
  end

  defp operation(context, overrides \\ %{}) do
    %{project: project, flow: flow, finding: finding} = context

    struct(
      Operation,
      Map.merge(
        %{
          workspace_id_snapshot: project.workspace_id,
          project_id_snapshot: project.id,
          subject_type: "flow_finding",
          subject_id: flow.id,
          subject_revision: Flows.encode_structural_finding_identity(finding)
        },
        overrides
      )
    )
  end

  describe "registration" do
    test "registers as a validated task with the expected contract" do
      assert {:ok, task} = TaskRegistry.fetch("flows.explain_finding")

      assert task.module == FlowFindingExplanation
      assert task.capability == :tasks
      assert task.data_scope == :entity
      assert task.allowed_lanes == [:managed]
      assert task.execution_mode == :background
      assert task.result_visibility == :actor_private
      assert task.result_destination == %{type: :panel, id: "flow_analysis"}
      assert task.result_ttl_seconds == 1_800
      assert task.managed_price.units == 1
      refute task.personal_byok_allowed?
      refute task.bulk_allowed?
      refute task.scheduled_allowed?
      assert TaskRegistry.command_id?("flows.explain_finding")
    end

    test "the operational switch can disable it without unregistering" do
      original = Application.get_env(:storyarn, FlowFindingExplanation, [])
      Application.put_env(:storyarn, FlowFindingExplanation, Keyword.put(original, :enabled, false))
      on_exit(fn -> Application.put_env(:storyarn, FlowFindingExplanation, original) end)

      assert {:error, :task_disabled} = TaskRegistry.fetch("flows.explain_finding")
      assert {:ok, _task} = TaskRegistry.get("flows.explain_finding")
    end

    test "the model may not return ids, and the schema is closed" do
      %{provider_options: options} = FlowFindingExplanation.definition()

      assert options.response_schema["additionalProperties"] == false

      assert Enum.sort(options.response_schema["required"]) ==
               ~w(implications suggested_checks summary why_it_triggers)

      refute Map.has_key?(options.response_schema["properties"], "finding_id")
      refute Map.has_key?(options.response_schema["properties"], "severity")
    end
  end

  describe "validate_input/1" do
    test "accepts exactly the request payload", context do
      assert :ok = FlowFindingExplanation.validate_input(FlowFindingExplanation.input(context.finding, "en"))
      assert :ok = FlowFindingExplanation.validate_input(FlowFindingExplanation.input(context.finding, "es"))
    end

    test "rejects extra, missing, or hostile fields", context do
      valid = FlowFindingExplanation.input(context.finding, "en")

      for invalid <- [
            Map.put(valid, "extra", true),
            Map.delete(valid, "finding_key"),
            Map.put(valid, "locale", "fr"),
            Map.put(valid, "evidence_fingerprint", "not-a-fingerprint"),
            Map.put(valid, "rule_version", "1"),
            Map.put(valid, "finding_key", ""),
            %{},
            ["array"],
            "string"
          ] do
        assert {:error, :invalid_explanation_input} = FlowFindingExplanation.validate_input(invalid)
      end
    end
  end

  describe "validate_output/1" do
    @valid_output %{
      "summary" => "The dialogue node has no outgoing connection.",
      "why_it_triggers" => "Every non-terminal node needs an outgoing edge.",
      "implications" => ["Players reaching it cannot continue."],
      "suggested_checks" => ["Check whether an exit node is missing."]
    }

    test "accepts the bounded narrative" do
      assert :ok = FlowFindingExplanation.validate_output(@valid_output)
      assert :ok = FlowFindingExplanation.validate_output(%{@valid_output | "implications" => []})
    end

    test "rejects ids, extra keys, empty text and oversized fields" do
      for invalid <- [
            Map.put(@valid_output, "finding_id", "sf1_abc"),
            Map.delete(@valid_output, "summary"),
            %{@valid_output | "summary" => ""},
            %{@valid_output | "summary" => String.duplicate("a", 801)},
            %{@valid_output | "implications" => "not a list"},
            %{@valid_output | "implications" => [""]},
            %{@valid_output | "implications" => List.duplicate("x", 6)},
            %{@valid_output | "suggested_checks" => [String.duplicate("a", 301)]},
            "string",
            nil
          ] do
        assert {:error, :invalid_explanation_output} = FlowFindingExplanation.validate_output(invalid)
      end
    end
  end

  describe "context_subject/1" do
    test "builds the Slice-6 subject from an intent", context do
      assert {:ok, %SubjectRef{} = ref} = FlowFindingExplanation.context_subject(intent(context))

      assert ref.kind == :structural_finding
      assert ref.project_id == context.project.id
      assert ref.subject_id == context.finding.finding_id
      assert ref.finding["finding_key"] == context.finding.finding_key
      assert %{type: "flow_node", id: _id} = hd(ref.evidence)
    end

    test "builds the same subject from the durable operation", context do
      assert {:ok, from_intent} = FlowFindingExplanation.context_subject(intent(context))
      assert {:ok, from_operation} = FlowFindingExplanation.context_subject(operation(context))

      assert from_intent == from_operation
    end

    test "a stale or forged revision never reaches the context builder", context do
      forged =
        Flows.encode_structural_finding_identity(%{
          finding_key: context.finding.finding_key,
          rule_version: context.finding.rule_version,
          evidence_fingerprint: String.duplicate("a", 64)
        })

      assert {:error, :stale_finding} =
               FlowFindingExplanation.context_subject(
                 intent(context, %{subject: %{type: "flow_finding", id: context.flow.id, revision: forged}})
               )

      assert {:error, :invalid_context_subject} =
               FlowFindingExplanation.context_subject(
                 intent(context, %{subject: %{type: "flow_finding", id: context.flow.id, revision: "garbage"}})
               )
    end

    test "an unknown rule id is rejected as a missing finding, not a stale one", context do
      # `finding_key` is "<rule_id>:<flow_id>:<target_type>:<target_id>", so a rule
      # the frozen catalog never had is well-formed but resolves to nothing. It
      # must fail as :unknown_finding — distinct from :stale_finding, which means
      # the rule DID fire and its evidence moved.
      "no_outgoing_connection:" <> target = context.finding.finding_key

      unknown_rule =
        Flows.encode_structural_finding_identity(%{
          finding_key: "rule_that_never_existed:" <> target,
          rule_version: context.finding.rule_version,
          evidence_fingerprint: context.finding.evidence_fingerprint
        })

      assert {:error, :unknown_finding} =
               FlowFindingExplanation.context_subject(
                 intent(context, %{subject: %{type: "flow_finding", id: context.flow.id, revision: unknown_rule}})
               )
    end

    test "the idempotency key separates locales", context do
      # The locale is part of the validated input, so a key that ignored it would
      # map two different requests onto one operation: reopening under a second
      # locale would replay the first language, and executing would blow up with
      # :idempotency_conflict when same_intent?/2 compared the input hashes.
      en = FlowFindingExplanation.idempotency_key(1, context.finding, "en", 0)
      es = FlowFindingExplanation.idempotency_key(1, context.finding, "es", 0)

      refute en == es
      assert en == FlowFindingExplanation.idempotency_key(1, context.finding, "en", 0)
      refute en == FlowFindingExplanation.idempotency_key(1, context.finding, "en", 1)
      refute en == FlowFindingExplanation.idempotency_key(2, context.finding, "en", 0)
    end

    test "a foreign flow id cannot borrow this project's authorization", context do
      other_project = project_fixture(user_fixture())
      other_flow = flow_fixture(other_project)

      assert {:error, :not_found} =
               FlowFindingExplanation.context_subject(
                 intent(context, %{
                   subject: %{
                     type: "flow_finding",
                     id: other_flow.id,
                     revision: Flows.encode_structural_finding_identity(context.finding)
                   }
                 })
               )
    end
  end

  describe "subject_current?/1" do
    test "is true while the exact occurrence stands", context do
      assert FlowFindingExplanation.subject_current?(operation(context))
    end

    test "is false once the flow changes under it", context do
      node_fixture(context.flow, %{type: "dialogue"})

      refute FlowFindingExplanation.subject_current?(operation(context))
    end

    test "is false for a resolved finding", context do
      exit_node = context.flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "exit"))
      connection_fixture(context.flow, context.stuck, exit_node)

      refute FlowFindingExplanation.subject_current?(operation(context))
    end

    test "is false for a malformed subject", context do
      refute FlowFindingExplanation.subject_current?(operation(context, %{subject_revision: "garbage"}))
      refute FlowFindingExplanation.subject_current?(operation(context, %{subject_type: "flow"}))
      refute FlowFindingExplanation.subject_current?(%Operation{})
    end
  end

  describe "authorize_subject/3" do
    test "accepts a flow of the intent's project", context do
      assert :ok = FlowFindingExplanation.authorize_subject(context.scope, intent(context), :execute)
    end

    test "rejects a flow the project does not own", context do
      other_flow = flow_fixture(project_fixture(user_fixture()))

      assert {:error, :unknown_flow} =
               FlowFindingExplanation.authorize_subject(
                 context.scope,
                 intent(context, %{
                   subject: %{
                     type: "flow_finding",
                     id: other_flow.id,
                     revision: Flows.encode_structural_finding_identity(context.finding)
                   }
                 }),
                 :execute
               )
    end

    test "rejects a deleted flow", context do
      {:ok, _deleted} = Flows.delete_flow(context.flow)

      assert {:error, :unknown_flow} =
               FlowFindingExplanation.authorize_subject(context.scope, intent(context), :execute)
    end
  end

  describe "task-level wiring" do
    test "the registry routes every optional callback to this module", context do
      {:ok, task} = TaskRegistry.fetch("flows.explain_finding")

      assert :ok = Task.validate_input(task, FlowFindingExplanation.input(context.finding, "en"))
      assert {:ok, %SubjectRef{}} = Task.context_subject(task, intent(context))
      assert Task.subject_current?(task, operation(context))
      assert :ok = Task.authorize_subject(task, context.scope, intent(context), :execute)
    end
  end
end
