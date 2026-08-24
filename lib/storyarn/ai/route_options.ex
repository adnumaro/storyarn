defmodule Storyarn.AI.RouteOptions do
  @moduledoc "Issues, binds, resolves and consumes opaque preflight route references."

  import Ecto.Query

  alias Storyarn.AI.Context.ModelLimits
  alias Storyarn.AI.Context.Package
  alias Storyarn.AI.CredentialRef
  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.RouteOption
  alias Storyarn.AI.Task
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  @default_ttl_seconds 300

  @spec issue(ExecutionIntent.t(), Task.t(), ExecutionRoute.t(), nil | map()) ::
          {:ok, map()} | {:error, atom() | Ecto.Changeset.t()}
  def issue(%ExecutionIntent{} = intent, %Task{} = task, %ExecutionRoute{} = route, context \\ nil) do
    token = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    subject = intent.subject || %{}
    expires_at = DateTime.add(TimeHelpers.now(), ttl_seconds(), :second)

    attrs = %{
      token_hash: token_hash(token),
      user_id: intent.scope.user.id,
      actor_id: intent.scope.user.id,
      workspace_id: intent.workspace_id,
      project_id: intent.project_id,
      task_id: task.id,
      task_contract_hash: Task.contract_hash(task),
      input_hash: intent.input_hash,
      subject_type: subject[:type],
      subject_id: subject[:id],
      subject_revision: subject[:revision],
      context_hash: context_hash(context),
      context_manifest: context_manifest(context),
      context_subject: context_subject(context),
      lane: Atom.to_string(route.lane),
      provider: route.provider,
      model: route.model,
      credential_ref: CredentialRef.to_map(route.credential_ref),
      payer: route.payer,
      assignment_source: route.assignment_source,
      consent_basis: route.consent_basis,
      policy_version: route.policy_version,
      price_id: route.price_id,
      price_version: route.price_version,
      price_units: route.price_units,
      provider_configuration: route.provider_configuration,
      expires_at: expires_at
    }

    with :ok <- ModelLimits.validate_context(task, route, intent.input, context),
         {:ok, _option} <- %RouteOption{} |> RouteOption.issue_changeset(attrs) |> Repo.insert() do
      {:ok,
       %{
         requested_route_ref: token,
         lane: route.lane,
         provider: route.provider,
         model: route.model,
         payer: route.payer,
         price_id: route.price_id,
         price_version: route.price_version,
         price_units: route.price_units,
         expires_at: expires_at
       }}
    end
  end

  @spec resolve_locked(ExecutionIntent.t(), Task.t()) ::
          {:ok, RouteOption.t(), ExecutionRoute.t()} | {:error, atom()}
  def resolve_locked(%ExecutionIntent{requested_route_ref: nil}, %Task{}), do: {:error, :route_ref_required}

  def resolve_locked(%ExecutionIntent{} = intent, %Task{} = task) do
    option =
      Repo.one(
        from(option in RouteOption,
          where: option.token_hash == ^token_hash(intent.requested_route_ref),
          lock: "FOR UPDATE"
        )
      )

    with %RouteOption{} <- option,
         :ok <- validate_binding(option, intent, task),
         {:ok, credential_ref} <- CredentialRef.from_map(option.credential_ref) do
      {:ok, option,
       %ExecutionRoute{
         lane: String.to_existing_atom(option.lane),
         provider: option.provider,
         model: option.model,
         credential_ref: credential_ref,
         payer: option.payer,
         assignment_source: option.assignment_source,
         consent_basis: option.consent_basis,
         policy_version: option.policy_version,
         price_id: option.price_id,
         price_version: option.price_version,
         price_units: option.price_units,
         provider_configuration: option.provider_configuration
       }}
    else
      nil -> {:error, :route_ref_invalid}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec consume(RouteOption.t(), pos_integer()) :: {:ok, RouteOption.t()} | {:error, Ecto.Changeset.t()}
  def consume(%RouteOption{} = option, operation_id) do
    option
    |> RouteOption.consume_changeset(operation_id, TimeHelpers.now())
    |> Repo.update()
  end

  @doc """
  Whether `route_ref` is the option that `consume/2` bound to `operation_id`.

  `consume/2` runs inside the operation-creating transaction and only there, so a
  surface whose `execute/1` replayed an existing idempotency key still holds an
  unconsumed option. Scoped to the actor so one actor's reference can never
  answer for another's.

  Only answers within the option's TTL. `delete_expired/1` removes consumed rows
  too — `expires_at` is stamped at issue and never extended — so this reports
  `false` for a real creator once `ExpireAIResultsWorker` has swept. Ask it once,
  at the moment of creation, and keep the answer; it is not a durable record of
  who bought an operation, and nothing here can be, since two sessions of one
  actor are indistinguishable in the database.

  No caller in `lib/` since Slice 7.1a.0 removed the first AI surface. Kept on
  purpose: it is the only reliable answer to "did I buy this operation, or did my
  `execute/1` replay someone else's", which `release_if_unstarted/2` depends on.
  Covered by `test/storyarn/ai/kernel_spend_guarantees_test.exs`.
  """
  @spec created_operation?(map(), String.t(), pos_integer()) :: boolean()
  def created_operation?(%{user: %{id: actor_id}}, route_ref, operation_id)
      when is_binary(route_ref) and is_integer(operation_id) do
    Repo.exists?(
      from(option in RouteOption,
        where:
          option.token_hash == ^token_hash(route_ref) and
            option.actor_id == ^actor_id and
            option.consumed_by_operation_id == ^operation_id
      )
    )
  end

  def created_operation?(_scope, _route_ref, _operation_id), do: false

  @spec delete_expired(DateTime.t()) :: non_neg_integer()
  def delete_expired(now \\ TimeHelpers.now()) do
    {count, _} = Repo.delete_all(from(option in RouteOption, where: option.expires_at <= ^now))

    count
  end

  defp validate_binding(option, intent, task) do
    cond do
      option.consumed_by_operation_id -> {:error, :route_ref_consumed}
      DateTime.compare(option.expires_at, TimeHelpers.now()) != :gt -> {:error, :route_ref_expired}
      option.task_contract_hash != Task.contract_hash(task) -> {:error, :route_ref_stale}
      binding_matches?(option, intent, task) -> :ok
      true -> {:error, :route_ref_mismatch}
    end
  end

  defp binding_matches?(option, intent, task) do
    subject = intent.subject || %{}

    {
      option.actor_id,
      option.workspace_id,
      option.project_id,
      option.task_id,
      option.task_contract_hash,
      option.input_hash,
      option.subject_type,
      option.subject_id,
      option.subject_revision
    } ==
      {
        intent.scope.user.id,
        intent.workspace_id,
        intent.project_id,
        task.id,
        Task.contract_hash(task),
        intent.input_hash,
        subject[:type],
        subject[:id],
        subject[:revision]
      }
  end

  defp token_hash(token), do: :crypto.hash(:sha256, token)

  defp context_hash(nil), do: nil
  defp context_hash(%{package: %Package{hash: hash}}), do: hash

  defp context_manifest(nil), do: nil
  defp context_manifest(%{package: %Package{} = package}), do: Package.provenance(package)

  defp context_subject(nil), do: nil
  defp context_subject(%{subject: subject}), do: subject

  defp ttl_seconds do
    :storyarn
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:ttl_seconds, @default_ttl_seconds)
  end
end
