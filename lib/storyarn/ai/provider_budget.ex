defmodule Storyarn.AI.ProviderBudget do
  @moduledoc "Transactional provider-cost ceilings for the managed lane."

  import Ecto.Query

  alias Storyarn.AI.Alerts
  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.Operation
  alias Storyarn.AI.ProviderBudgetReservation
  alias Storyarn.AI.UsageEvent
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @budget_lock_namespace 981_007

  @spec reserve(Operation.t(), ExecutionRoute.t()) :: :ok | {:error, atom()}
  def reserve(%Operation{} = operation, %ExecutionRoute{} = route) do
    Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [@budget_lock_namespace, 1])

    case lock_reservation(operation.id) do
      %ProviderBudgetReservation{status: status} when status in ~w(reserved settled) -> :ok
      nil -> create_reservation(operation, route)
    end
  end

  @spec settle(Operation.t()) :: :ok | {:error, atom()}
  def settle(%Operation{} = operation) do
    Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [@budget_lock_namespace, 1])

    case lock_reservation(operation.id) do
      %ProviderBudgetReservation{status: "settled"} ->
        :ok

      %ProviderBudgetReservation{status: "reserved"} = reservation ->
        actual_cost = actual_cost(operation, reservation)

        reservation
        |> ProviderBudgetReservation.settle_changeset(actual_cost, TimeHelpers.now())
        |> Repo.update!()

        maybe_alert_spike(operation, reservation, actual_cost)
        :ok

      nil ->
        {:error, :provider_budget_reservation_missing}
    end
  end

  defp create_reservation(operation, route) do
    with {:ok, price_snapshot, budget, estimate, currency} <- route_cost_contract(route),
         :ok <- check_caps(operation.workspace_id_snapshot, estimate, currency, budget) do
      %ProviderBudgetReservation{}
      |> ProviderBudgetReservation.create_changeset(%{
        operation_id: operation.id,
        workspace_id: operation.workspace_id_snapshot,
        workspace_id_snapshot: operation.workspace_id_snapshot,
        provider: route.provider,
        model: route.model,
        price_snapshot: price_snapshot,
        estimated_cost: estimate,
        currency: currency,
        status: "reserved"
      })
      |> Repo.insert!()

      :ok
    end
  end

  defp route_cost_contract(%ExecutionRoute{provider_configuration: configuration}) when is_map(configuration) do
    price_snapshot = configuration["provider_price"]
    budget = configuration["budget"]

    with %{} <- price_snapshot,
         %{} <- budget,
         {:ok, estimate} <- decimal(price_snapshot["max_estimated_cost"]),
         currency when is_binary(currency) <- price_snapshot["currency"],
         true <- byte_size(currency) in 1..12 do
      {:ok, price_snapshot, budget, estimate, currency}
    else
      _invalid -> {:error, :provider_cost_configuration_invalid}
    end
  end

  defp route_cost_contract(_route), do: {:error, :provider_cost_configuration_invalid}

  defp check_caps(workspace_id, estimate, currency, budget) do
    today = Date.utc_today()
    day_start = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
    month_start = DateTime.new!(%{today | day: 1}, ~T[00:00:00], "Etc/UTC")

    with {:ok, daily_cap} <- decimal(budget["global_daily"]),
         {:ok, monthly_cap} <- decimal(budget["global_monthly"]),
         {:ok, workspace_cap} <- decimal(budget["workspace_daily"]),
         :ok <-
           below_cap(
             total_since(day_start, currency),
             estimate,
             daily_cap,
             :provider_daily_budget_exhausted
           ),
         :ok <-
           below_cap(
             total_since(month_start, currency),
             estimate,
             monthly_cap,
             :provider_monthly_budget_exhausted
           ) do
      below_cap(
        total_since(day_start, currency, workspace_id),
        estimate,
        workspace_cap,
        :workspace_provider_budget_exhausted
      )
    end
  end

  defp total_since(started_at, currency, workspace_id \\ nil) do
    query =
      from(reservation in ProviderBudgetReservation,
        where: reservation.inserted_at >= ^started_at and reservation.currency == ^currency
      )

    query =
      if workspace_id,
        do: from(reservation in query, where: reservation.workspace_id_snapshot == ^workspace_id),
        else: query

    Repo.one(
      from(reservation in query,
        select:
          fragment(
            "COALESCE(SUM(COALESCE(?, ?)), 0)",
            reservation.actual_cost,
            reservation.estimated_cost
          )
      )
    )
  end

  defp below_cap(current, estimate, cap, error) do
    if Decimal.compare(Decimal.add(current, estimate), cap) in [:lt, :eq], do: :ok, else: {:error, error}
  end

  defp actual_cost(operation, reservation) do
    usage = Repo.get_by(UsageEvent, operation_id: operation.id)

    cond do
      usage && usage.provider_cost && usage.provider_cost_currency == reservation.currency -> usage.provider_cost
      is_nil(operation.external_attempt_started_at) -> Decimal.new(0)
      true -> reservation.estimated_cost
    end
  end

  defp maybe_alert_spike(operation, reservation, actual_cost) do
    if Decimal.compare(actual_cost, reservation.estimated_cost) == :gt do
      Alerts.record(%{
        dedupe_key: "provider-cost-spike:#{operation.id}",
        kind: "provider_cost_spike",
        severity: "warning",
        workspace_id: operation.workspace_id,
        workspace_id_snapshot: operation.workspace_id_snapshot,
        operation_id: operation.id,
        metadata: %{
          "provider" => reservation.provider,
          "model" => reservation.model,
          "currency" => reservation.currency,
          "estimated_cost" => Decimal.to_string(reservation.estimated_cost),
          "actual_cost" => Decimal.to_string(actual_cost)
        }
      })
    end
  end

  defp lock_reservation(operation_id) do
    Repo.one(
      from(reservation in ProviderBudgetReservation,
        where: reservation.operation_id == ^operation_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp decimal(%Decimal{} = value) do
    if Decimal.compare(value, Decimal.new(0)) in [:gt, :eq], do: {:ok, value}, else: {:error, :invalid_decimal}
  end

  defp decimal(value) when is_integer(value) and value >= 0, do: {:ok, Decimal.new(value)}

  defp decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> decimal(decimal)
      _invalid -> {:error, :invalid_decimal}
    end
  end

  defp decimal(_value), do: {:error, :invalid_decimal}
end
