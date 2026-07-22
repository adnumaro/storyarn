defmodule Storyarn.AI.Allowance do
  @moduledoc "Promotional workspace allowance and append-only managed execution ledger."

  import Ecto.Query

  alias Ecto.Changeset
  alias Storyarn.Accounts.Scope
  alias Storyarn.AI.AllowanceAccount
  alias Storyarn.AI.AllowanceAllocation
  alias Storyarn.AI.AllowanceGrant
  alias Storyarn.AI.AllowanceLedgerEntry
  alias Storyarn.AI.AllowanceReservation
  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.Operation
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace

  @account_lock_namespace 981_006

  @type summary :: %{
          status: String.t(),
          available_units: non_neg_integer(),
          reserved_units: non_neg_integer(),
          committed_units: non_neg_integer()
        }

  @spec summary(Scope.t(), pos_integer()) :: {:ok, summary()} | {:error, :unauthorized}
  def summary(%Scope{} = scope, workspace_id) do
    case Workspaces.get_workspace(scope, workspace_id) do
      {:ok, workspace, _membership} -> {:ok, refresh_and_summarize(workspace.id)}
      _error -> {:error, :unauthorized}
    end
  end

  @doc "Issues an idempotent operator grant; this is intentionally not exposed by the AI facade."
  @spec grant(pos_integer(), pos_integer(), map()) ::
          {:ok, AllowanceGrant.t()} | {:error, atom() | Changeset.t()}
  def grant(workspace_id, actor_id, attrs)
      when is_integer(workspace_id) and workspace_id > 0 and is_integer(actor_id) and actor_id > 0 and is_map(attrs) do
    with {:ok, normalized_attrs} <- normalize_grant_attrs(attrs) do
      Repo.transaction(fn -> grant_locked(workspace_id, actor_id, normalized_attrs) end)
    end
  end

  @doc "Pauses or resumes managed spend for one workspace without changing its grant history."
  @spec set_status(pos_integer(), String.t()) :: {:ok, AllowanceAccount.t()} | {:error, atom()}
  def set_status(workspace_id, status) when status in ~w(active paused) do
    Repo.transaction(fn ->
      lock_account_key!(workspace_id)

      case lock_account(workspace_id) do
        %AllowanceAccount{} = account ->
          account
          |> AllowanceAccount.balance_changeset(%{status: status})
          |> Repo.update!()

        nil ->
          Repo.rollback(:allowance_unavailable)
      end
    end)
  end

  @doc false
  @spec reserve(Operation.t()) :: :ok | {:error, atom()}
  def reserve(%Operation{} = operation) do
    with {:ok, route} <- ExecutionRoute.from_map(operation.execution_route) do
      reserve_route(operation, route)
    end
  end

  @doc false
  @spec commit(Operation.t()) :: :ok | {:error, atom()}
  def commit(%Operation{} = operation), do: settle(operation, "committed")

  @doc false
  @spec release(Operation.t()) :: :ok | {:error, atom()}
  def release(%Operation{} = operation), do: settle(operation, "released")

  @doc "Expires available grant units. Reserved units settle through their operation lifecycle."
  @spec expire_due() :: non_neg_integer()
  def expire_due do
    account_ids =
      Repo.all(
        from(grant in AllowanceGrant,
          where: not is_nil(grant.account_id) and grant.remaining_units > 0 and grant.expires_at <= ^TimeHelpers.now(),
          distinct: grant.account_id,
          select: grant.account_id
        )
      )

    Enum.reduce(account_ids, 0, &expire_account/2)
  end

  defp expire_account(account_id, total) do
    case Repo.transaction(fn -> expire_account_locked(account_id, TimeHelpers.now()) end) do
      {:ok, count} -> total + count
      {:error, _reason} -> total
    end
  end

  defp grant_locked(workspace_id, actor_id, attrs) do
    lock_account_key!(workspace_id)
    workspace = Repo.get(Workspace, workspace_id) || Repo.rollback(:workspace_not_found)
    account = lock_account(workspace_id) || create_account!(workspace_id)
    now = TimeHelpers.now()
    expire_account!(account, now)

    grant_key = Map.get(attrs, :grant_key) || Map.get(attrs, "grant_key")

    case grant_by_key(workspace_id, grant_key) do
      %AllowanceGrant{} = existing ->
        if same_grant?(existing, attrs), do: existing, else: Repo.rollback(:grant_conflict)

      nil ->
        insert_grant!(workspace, account, actor_id, attrs)
    end
  end

  defp insert_grant!(workspace, account, actor_id, attrs) do
    units = value(attrs, :units)

    changeset =
      AllowanceGrant.create_changeset(%AllowanceGrant{}, %{
        account_id: account.id,
        workspace_id: workspace.id,
        workspace_id_snapshot: workspace.id,
        grant_key: value(attrs, :grant_key),
        kind: value(attrs, :kind),
        units: units,
        remaining_units: units,
        expires_at: value(attrs, :expires_at),
        granted_by_id: actor_id,
        actor_id: actor_id,
        metadata: value(attrs, :metadata) || %{}
      })

    grant =
      case Repo.insert(changeset) do
        {:ok, grant} -> grant
        {:error, invalid_changeset} -> Repo.rollback(invalid_changeset)
      end

    update_account!(account, %{available_units: account.available_units + units})

    insert_ledger!(%{
      workspace_id: workspace.id,
      workspace_id_snapshot: workspace.id,
      grant_id: grant.id,
      kind: "grant",
      units: units,
      available_delta: units,
      idempotency_key: "grant:#{grant.grant_key}",
      metadata: %{"grant_kind" => grant.kind}
    })

    grant
  end

  defp reserve_route(operation, %ExecutionRoute{lane: :managed, price_units: units} = route)
       when is_integer(units) and units > 0 do
    lock_account_key!(operation.workspace_id_snapshot)

    case lock_reservation(operation.id) do
      %AllowanceReservation{status: status, units: ^units} when status in ~w(reserved committed) ->
        :ok

      %AllowanceReservation{} ->
        {:error, :allowance_reservation_conflict}

      nil ->
        create_reservation(operation, route)
    end
  end

  defp reserve_route(_operation, _route), do: {:error, :invalid_managed_price}

  defp create_reservation(operation, route) do
    now = TimeHelpers.now()

    with %AllowanceAccount{} = account <- lock_account(operation.workspace_id_snapshot),
         account = expire_account!(account, now),
         :ok <- active_account(account),
         :ok <- sufficient_allowance(account, route.price_units),
         grants = lock_spendable_grants(account.id, now),
         {:ok, allocations} <- allocate(grants, route.price_units) do
      reservation =
        %AllowanceReservation{}
        |> AllowanceReservation.create_changeset(%{
          operation_id: operation.id,
          workspace_id: operation.workspace_id_snapshot,
          workspace_id_snapshot: operation.workspace_id_snapshot,
          price_id: route.price_id,
          price_version: route.price_version,
          units: route.price_units,
          status: "reserved"
        })
        |> Repo.insert!()

      Enum.each(allocations, &insert_allocation!(reservation.id, &1))

      update_account!(account, %{
        available_units: account.available_units - route.price_units,
        reserved_units: account.reserved_units + route.price_units
      })

      insert_ledger!(%{
        workspace_id: operation.workspace_id_snapshot,
        workspace_id_snapshot: operation.workspace_id_snapshot,
        operation_id: operation.id,
        reservation_id: reservation.id,
        kind: "reserve",
        units: route.price_units,
        available_delta: -route.price_units,
        idempotency_key: "operation:#{operation.id}:reserve",
        metadata: %{"price_id" => route.price_id, "price_version" => route.price_version}
      })

      :ok
    else
      nil -> {:error, :allowance_unavailable}
      {:error, reason} -> {:error, reason}
    end
  end

  defp settle(operation, next_status) do
    lock_account_key!(operation.workspace_id_snapshot)

    case lock_reservation(operation.id) do
      %AllowanceReservation{status: ^next_status} -> :ok
      %AllowanceReservation{status: "reserved"} = reservation -> settle_reserved(operation, reservation, next_status)
      %AllowanceReservation{} -> {:error, :allowance_settlement_conflict}
      nil -> {:error, :allowance_reservation_missing}
    end
  end

  defp settle_reserved(operation, reservation, "committed") do
    case lock_account(operation.workspace_id_snapshot) do
      %AllowanceAccount{} = account ->
        update_account!(account, %{
          reserved_units: account.reserved_units - reservation.units,
          committed_units: account.committed_units + reservation.units
        })

        reservation
        |> AllowanceReservation.settle_changeset("committed", TimeHelpers.now())
        |> Repo.update!()

        insert_ledger!(%{
          workspace_id: operation.workspace_id_snapshot,
          workspace_id_snapshot: operation.workspace_id_snapshot,
          operation_id: operation.id,
          reservation_id: reservation.id,
          kind: "commit",
          units: reservation.units,
          available_delta: 0,
          idempotency_key: "operation:#{operation.id}:commit"
        })

        :ok

      nil ->
        {:error, :allowance_unavailable}
    end
  end

  defp settle_reserved(operation, reservation, "released") do
    now = TimeHelpers.now()

    case lock_account(operation.workspace_id_snapshot) do
      %AllowanceAccount{} = account ->
        allocations = lock_allocations(reservation.id)
        restored = Enum.reduce(allocations, 0, &restore_allocation(&1, now, &2))
        expired = reservation.units - restored

        update_account!(account, %{
          available_units: account.available_units + restored,
          reserved_units: account.reserved_units - reservation.units
        })

        reservation
        |> AllowanceReservation.settle_changeset("released", now)
        |> Repo.update!()

        insert_ledger!(%{
          workspace_id: operation.workspace_id_snapshot,
          workspace_id_snapshot: operation.workspace_id_snapshot,
          operation_id: operation.id,
          reservation_id: reservation.id,
          kind: "release",
          units: reservation.units,
          available_delta: restored,
          idempotency_key: "operation:#{operation.id}:release"
        })

        if expired > 0 do
          insert_ledger!(%{
            workspace_id: operation.workspace_id_snapshot,
            workspace_id_snapshot: operation.workspace_id_snapshot,
            operation_id: operation.id,
            reservation_id: reservation.id,
            kind: "expiry",
            units: expired,
            available_delta: 0,
            idempotency_key: "operation:#{operation.id}:reserved-expiry"
          })
        end

        :ok

      nil ->
        {:error, :allowance_unavailable}
    end
  end

  defp lock_account(workspace_id) do
    Repo.one(from(account in AllowanceAccount, where: account.workspace_id == ^workspace_id, lock: "FOR UPDATE"))
  end

  defp create_account!(workspace_id) do
    %AllowanceAccount{}
    |> AllowanceAccount.create_changeset(workspace_id)
    |> Repo.insert!()
  end

  defp grant_by_key(workspace_id, grant_key) when is_binary(grant_key) do
    Repo.one(
      from(grant in AllowanceGrant,
        where: grant.workspace_id_snapshot == ^workspace_id and grant.grant_key == ^grant_key,
        lock: "FOR UPDATE"
      )
    )
  end

  defp grant_by_key(_workspace_id, _grant_key), do: nil

  defp lock_reservation(operation_id) do
    Repo.one(
      from(reservation in AllowanceReservation,
        where: reservation.operation_id == ^operation_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_spendable_grants(account_id, now) do
    Repo.all(
      from(grant in AllowanceGrant,
        where:
          grant.account_id == ^account_id and grant.remaining_units > 0 and
            (is_nil(grant.expires_at) or grant.expires_at > ^now),
        order_by: [asc_nulls_last: grant.expires_at, asc: grant.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp allocate(grants, units) do
    {remaining, allocations} =
      Enum.reduce_while(grants, {units, []}, fn grant, {remaining, allocations} ->
        allocated = min(grant.remaining_units, remaining)

        grant
        |> Changeset.change(remaining_units: grant.remaining_units - allocated)
        |> Repo.update!()

        next = {remaining - allocated, [%{grant_id: grant.id, units: allocated} | allocations]}
        if elem(next, 0) == 0, do: {:halt, next}, else: {:cont, next}
      end)

    if remaining == 0, do: {:ok, Enum.reverse(allocations)}, else: {:error, :allowance_projection_mismatch}
  end

  defp insert_allocation!(reservation_id, %{grant_id: grant_id, units: units}) do
    %AllowanceAllocation{}
    |> AllowanceAllocation.create_changeset(%{
      reservation_id: reservation_id,
      grant_id: grant_id,
      units: units
    })
    |> Repo.insert!()
  end

  defp lock_allocations(reservation_id) do
    Repo.all(
      from(allocation in AllowanceAllocation,
        join: grant in assoc(allocation, :grant),
        where: allocation.reservation_id == ^reservation_id,
        preload: [grant: grant],
        lock: "FOR UPDATE"
      )
    )
  end

  defp restore_allocation(allocation, now, restored_total) do
    restored = if grant_active?(allocation.grant, now), do: allocation.units, else: 0

    if restored > 0 do
      allocation.grant
      |> Changeset.change(remaining_units: allocation.grant.remaining_units + restored)
      |> Repo.update!()
    end

    allocation
    |> AllowanceAllocation.restore_changeset(restored)
    |> Repo.update!()

    restored_total + restored
  end

  defp grant_active?(%AllowanceGrant{expires_at: nil}, _now), do: true
  defp grant_active?(%AllowanceGrant{expires_at: expires_at}, now), do: DateTime.after?(expires_at, now)

  defp expire_account!(account, now) do
    expire_account_locked(account.id, now)
    Repo.get!(AllowanceAccount, account.id)
  end

  defp expire_account_locked(account_id, now) do
    account = Repo.one!(from(account in AllowanceAccount, where: account.id == ^account_id, lock: "FOR UPDATE"))

    grants =
      Repo.all(
        from(grant in AllowanceGrant,
          where:
            grant.account_id == ^account_id and grant.remaining_units > 0 and
              not is_nil(grant.expires_at) and grant.expires_at <= ^now,
          lock: "FOR UPDATE"
        )
      )

    expired_units = Enum.reduce(grants, 0, &expire_grant(&1, &2))

    if expired_units > 0 do
      update_account!(account, %{available_units: account.available_units - expired_units})
    end

    length(grants)
  end

  defp expire_grant(grant, total) do
    units = grant.remaining_units

    grant
    |> Changeset.change(remaining_units: 0)
    |> Repo.update!()

    insert_ledger!(%{
      workspace_id: grant.workspace_id,
      workspace_id_snapshot: grant.workspace_id_snapshot,
      grant_id: grant.id,
      kind: "expiry",
      units: units,
      available_delta: -units,
      idempotency_key: "grant:#{grant.id}:expiry"
    })

    total + units
  end

  defp update_account!(account, attrs) do
    account
    |> AllowanceAccount.balance_changeset(attrs)
    |> Repo.update!()
  end

  defp insert_ledger!(attrs) do
    %AllowanceLedgerEntry{}
    |> AllowanceLedgerEntry.changeset(attrs)
    |> Repo.insert!()
  end

  defp active_account(%AllowanceAccount{status: "active"}), do: :ok
  defp active_account(%AllowanceAccount{}), do: {:error, :allowance_paused}

  defp sufficient_allowance(%AllowanceAccount{available_units: available}, units) when available >= units, do: :ok
  defp sufficient_allowance(%AllowanceAccount{}, _units), do: {:error, :allowance_exhausted}

  defp refresh_and_summarize(workspace_id) do
    {:ok, summary} =
      Repo.transaction(fn ->
        lock_account_key!(workspace_id)

        case lock_account(workspace_id) do
          nil -> empty_summary()
          account -> account |> expire_account!(TimeHelpers.now()) |> account_summary()
        end
      end)

    summary
  end

  defp account_summary(account) do
    %{
      status: account.status,
      available_units: account.available_units,
      reserved_units: account.reserved_units,
      committed_units: account.committed_units
    }
  end

  defp empty_summary do
    %{status: "unavailable", available_units: 0, reserved_units: 0, committed_units: 0}
  end

  defp same_grant?(grant, attrs) do
    grant.kind == value(attrs, :kind) and grant.units == value(attrs, :units) and
      grant.expires_at == value(attrs, :expires_at)
  end

  defp normalize_grant_attrs(attrs) do
    case value(attrs, :expires_at) do
      nil -> {:ok, Map.put(attrs, :expires_at, nil)}
      %DateTime{} = datetime -> {:ok, Map.put(attrs, :expires_at, DateTime.truncate(datetime, :second))}
      _invalid -> {:error, :invalid_grant_expiry}
    end
  end

  defp value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

  defp lock_account_key!(workspace_id) do
    Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [@account_lock_namespace, workspace_id])
  end
end
