defmodule Storyarn.AI.RouteOptions do
  @moduledoc "Issues, binds, resolves and consumes opaque preflight route references."

  import Ecto.Query

  alias Storyarn.AI.CredentialRef
  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.RouteOption
  alias Storyarn.AI.Task
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @default_ttl_seconds 300

  @spec issue(ExecutionIntent.t(), Task.t(), ExecutionRoute.t()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def issue(%ExecutionIntent{} = intent, %Task{} = task, %ExecutionRoute{} = route) do
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
      input_hash: intent.input_hash,
      subject_type: subject[:type],
      subject_id: subject[:id],
      subject_revision: subject[:revision],
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
      expires_at: expires_at
    }

    case %RouteOption{} |> RouteOption.issue_changeset(attrs) |> Repo.insert() do
      {:ok, _option} ->
        {:ok,
         %{
           requested_route_ref: token,
           lane: route.lane,
           provider: route.provider,
           model: route.model,
           payer: route.payer,
           price_id: route.price_id,
           price_version: route.price_version,
           expires_at: expires_at
         }}

      {:error, changeset} ->
        {:error, changeset}
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
         price_version: option.price_version
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

  @spec delete_expired(DateTime.t()) :: non_neg_integer()
  def delete_expired(now \\ TimeHelpers.now()) do
    {count, _} = Repo.delete_all(from(option in RouteOption, where: option.expires_at <= ^now))

    count
  end

  defp validate_binding(option, intent, task) do
    cond do
      option.consumed_by_operation_id -> {:error, :route_ref_consumed}
      DateTime.compare(option.expires_at, TimeHelpers.now()) != :gt -> {:error, :route_ref_expired}
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
        intent.input_hash,
        subject[:type],
        subject[:id],
        subject[:revision]
      }
  end

  defp token_hash(token), do: :crypto.hash(:sha256, token)

  defp ttl_seconds do
    :storyarn
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:ttl_seconds, @default_ttl_seconds)
  end
end
