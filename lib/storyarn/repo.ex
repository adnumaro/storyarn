defmodule Storyarn.Repo do
  use Ecto.Repo,
    otp_app: :storyarn,
    adapter: Ecto.Adapters.Postgres

  @repeatable_read_marker {__MODULE__, :repeatable_read}

  @doc """
  Runs `fun` in a real PostgreSQL repeatable-read transaction.

  Postgrex ignores an `:isolation` transaction option, so the isolation level
  must be the first statement after `BEGIN`. SQL sandbox tests already run
  inside an outer transaction and cannot change its isolation level.

  A call nested in a transaction this function opened joins it, since that
  transaction already holds the snapshot. A call nested in any other
  transaction raises `ArgumentError`: PostgreSQL rejects the isolation change
  once the transaction has run a query, and the sandbox would hide that from
  every test.
  """
  @spec repeatable_read((-> result), keyword()) :: {:ok, result} | {:error, term()} when result: term()
  def repeatable_read(fun, opts \\ []) when is_function(fun, 0) and is_list(opts) do
    cond do
      Process.get(@repeatable_read_marker, false) ->
        transaction(fun, opts)

      in_transaction?() ->
        raise ArgumentError,
              "repeatable_read/2 cannot change the isolation of a transaction that is already open; " <>
                "open the outer transaction with repeatable_read/2 or read inside it directly"

      true ->
        transaction(
          fn ->
            set_repeatable_read!()
            Process.put(@repeatable_read_marker, true)

            try do
              fun.()
            after
              Process.delete(@repeatable_read_marker)
            end
          end,
          opts
        )
    end
  end

  defp set_repeatable_read! do
    if !Application.get_env(:storyarn, :sql_sandbox, false) do
      query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
    end

    :ok
  end
end
