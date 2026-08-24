defmodule Storyarn.AI.KernelSpendGuaranteesTest do
  @moduledoc """
  Kernel-level coverage for the spend guarantees Slice 7.2a's review rounds
  produced.

  These functions used to be exercised only through the flow-finding explanation
  panel. Slice 7.1a.0 removed that surface, and its 38 tests with it, which would
  have left the hardening itself untested — so the coverage moved down here,
  against a fixture task, exactly as that slice's contract required.

  What each guarantee is for:

    * `release_if_unstarted/2` — a surface that walks away from an operation must
      be able to give it up while giving it up is still free, and must never
      cancel a started provider attempt (that bills the unit anyway and destroys
      the output). The decision belongs under the row lock, not to a status read;
    * `created_operation?/3` — `execute/1` REPLAYS a spent idempotency key, so two
      surfaces can both come back holding one operation. Only the one whose
      purchase created it may release it, and the consumed route option is the
      only reliable proof of which that is;
    * `get_by_idempotency_key/3` and `operations_by_idempotency_keys/3` — a key is
      spent permanently by the first operation that uses it, so a surface has to
      resolve which attempt to act on rather than assume one;
    * `record_view/2` — records that the actor saw a result, deliberately without
      touching `user_disposition`, whose `IS NULL` precondition keeps dismiss,
      apply and expiry-abandonment reachable.
  """

  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.AI
  alias Storyarn.AI.Operation
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias StoryarnTest.AI.ContractTask

  setup do
    original_config = Application.get_env(:storyarn, ContractTask, [])
    # Background, so an operation can be observed before anything runs it.
    Application.put_env(:storyarn, ContractTask, scenario: :success, execution_mode: :background)

    user = user_fixture()
    scope = user_scope_fixture(user)
    workspace = workspace_fixture(user)
    project = project_fixture(user, %{workspace: workspace})

    FunWithFlags.enable(:ai_integrations, for_actor: user)
    assert {:ok, _policy} = AI.update_workspace_policy(scope, workspace.id, ["managed"])

    on_exit(fn ->
      Application.put_env(:storyarn, ContractTask, original_config)
      FunWithFlags.disable(:ai_integrations, for_actor: user)
    end)

    %{user: user, scope: scope, workspace: workspace, project: project}
  end

  describe "release_if_unstarted/2" do
    test "releases a queued operation", ctx do
      {operation, _route_ref} = execute!(ctx, "queued release")

      assert operation.execution_status == "queued"
      assert {:ok, :released} = AI.release_if_unstarted(ctx.scope, operation.id)
      assert Repo.get!(Operation, operation.id).execution_status == "cancelled"
    end

    test "releases a running operation whose provider attempt has not started", ctx do
      {operation, _route_ref} = execute!(ctx, "running release")

      # The window between claim and the provider call: the worker owns the row,
      # yet nothing has been spent, so releasing is still free.
      {1, _} = Repo.update_all(Operation, set: [execution_status: "running", started_at: TimeHelpers.now()])

      assert {:ok, :released} = AI.release_if_unstarted(ctx.scope, operation.id)
      assert Repo.get!(Operation, operation.id).execution_status == "cancelled"
    end

    test "reports a started attempt and leaves it strictly alone", ctx do
      {operation, _route_ref} = execute!(ctx, "started")

      now = TimeHelpers.now()

      {1, _} =
        Repo.update_all(Operation,
          set: [execution_status: "running", started_at: now, external_attempt_started_at: now]
        )

      assert {:ok, :started} = AI.release_if_unstarted(ctx.scope, operation.id)

      reloaded = Repo.get!(Operation, operation.id)
      assert reloaded.execution_status == "running"
      # NOT a cancellation request: that bills the unit and deletes the output.
      assert is_nil(reloaded.cancellation_requested_at)
    end

    test "is scoped to the actor", ctx do
      {operation, _route_ref} = execute!(ctx, "other actor")
      other = user_scope_fixture(user_fixture())

      assert {:error, :not_found} = AI.release_if_unstarted(other, operation.id)
      assert Repo.get!(Operation, operation.id).execution_status == "queued"
    end
  end

  describe "created_operation?/3" do
    test "is true for the route reference that created the operation", ctx do
      {operation, route_ref} = execute!(ctx, "creator")

      assert AI.created_operation?(ctx.scope, route_ref, operation.id)
    end

    test "is false for a surface whose execute REPLAYED the same key", ctx do
      # Two preflights, one key: the second execute replays the first operation
      # rather than creating one, so its own route option stays unconsumed. That
      # is what distinguishes a buyer from a surface that merely attached.
      first_ref = route_ref!(ctx, "replay")
      second_ref = route_ref!(ctx, "replay")

      assert {:ok, bought} = AI.execute(execution_intent!(ctx, "replay", first_ref, "shared-key"))
      assert {:ok, replayed} = AI.execute(execution_intent!(ctx, "replay", second_ref, "shared-key"))

      assert replayed.id == bought.id
      assert Repo.aggregate(Operation, :count) == 1

      assert AI.created_operation?(ctx.scope, first_ref, bought.id)
      refute AI.created_operation?(ctx.scope, second_ref, bought.id)
    end

    test "is false for another actor's reference and for junk", ctx do
      {operation, route_ref} = execute!(ctx, "scoping")
      other = user_scope_fixture(user_fixture())

      refute AI.created_operation?(other, route_ref, operation.id)
      refute AI.created_operation?(ctx.scope, "not-a-real-reference", operation.id)
    end
  end

  describe "idempotency-key lookups" do
    test "a readable result is recovered by the key that produced it", ctx do
      {operation, _route_ref} = execute!(ctx, "readable")
      drain!()

      assert {:ok, output, found} =
               AI.get_replayable_result(ctx.scope, "contract.echo", "readable-key")

      assert found.id == operation.id
      assert is_map(output)
    end

    test "a spent key with no readable result reports the operation, not the result", ctx do
      {operation, _route_ref} = execute!(ctx, "dead end")

      operation
      |> Ecto.Changeset.change(execution_status: "cancelled", error_classification: "user_cancelled")
      |> Repo.update!()

      # The distinction the attempt resolver depends on: the key is spent, so it
      # can never produce anything again, and a caller must be able to tell that
      # from "still coming".
      assert {:error, _reason} = AI.get_replayable_result(ctx.scope, "contract.echo", "dead end-key")

      assert %{"dead end-key" => %{execution_status: "cancelled"}} =
               AI.get_operations_by_keys(ctx.scope, "contract.echo", ["dead end-key"])
    end

    test "unspent keys are absent from the bulk lookup", ctx do
      {_operation, _route_ref} = execute!(ctx, "spent")

      found = AI.get_operations_by_keys(ctx.scope, "contract.echo", ["spent-key", "never-used-key"])

      assert Map.has_key?(found, "spent-key")
      refute Map.has_key?(found, "never-used-key")
    end

    test "both lookups are scoped to the actor", ctx do
      {_operation, _route_ref} = execute!(ctx, "private")
      drain!()
      other = user_scope_fixture(user_fixture())

      assert {:error, _reason} = AI.get_replayable_result(other, "contract.echo", "private-key")
      assert AI.get_operations_by_keys(other, "contract.echo", ["private-key"]) == %{}
    end
  end

  describe "record_view/2" do
    test "stamps viewed_at without touching the disposition", ctx do
      {operation, _route_ref} = execute!(ctx, "viewed")
      drain!()

      assert :ok = AI.record_result_view(ctx.scope, operation.id)

      reloaded = Repo.get!(Operation, operation.id)
      assert reloaded.viewed_at
      # Load-bearing: `user_disposition` staying nil is what keeps dismiss, apply
      # and expiry-abandonment reachable.
      assert is_nil(reloaded.user_disposition)
    end

    test "is idempotent and never fails the caller", ctx do
      {operation, _route_ref} = execute!(ctx, "twice")
      drain!()

      assert :ok = AI.record_result_view(ctx.scope, operation.id)
      first = Repo.get!(Operation, operation.id).viewed_at

      assert :ok = AI.record_result_view(ctx.scope, operation.id)
      assert Repo.get!(Operation, operation.id).viewed_at == first
    end

    test "another actor cannot stamp a view", ctx do
      {operation, _route_ref} = execute!(ctx, "not yours")
      drain!()
      other = user_scope_fixture(user_fixture())

      assert :ok = AI.record_result_view(other, operation.id)
      assert is_nil(Repo.get!(Operation, operation.id).viewed_at)
    end
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp drain!, do: Oban.drain_queue(queue: :ai, with_safety: false)

  defp execute!(ctx, text) do
    route_ref = route_ref!(ctx, text)
    assert {:ok, operation} = AI.execute(execution_intent!(ctx, text, route_ref, "#{text}-key"))
    {operation, route_ref}
  end

  defp route_ref!(ctx, text) do
    assert {:ok, %{route_options: [%{requested_route_ref: route_ref}]}} =
             AI.preflight(intent!(ctx, text))

    route_ref
  end

  defp intent!(ctx, text) do
    assert {:ok, intent} =
             AI.new_intent(ctx.scope, %{
               workspace_id: ctx.workspace.id,
               project_id: ctx.project.id,
               task_id: "contract.echo",
               input: %{"text" => text}
             })

    intent
  end

  defp execution_intent!(ctx, text, route_ref, idempotency_key) do
    assert {:ok, intent} =
             AI.new_intent(ctx.scope, %{
               workspace_id: ctx.workspace.id,
               project_id: ctx.project.id,
               task_id: "contract.echo",
               input: %{"text" => text},
               requested_route_ref: route_ref,
               idempotency_key: idempotency_key
             })

    intent
  end
end
