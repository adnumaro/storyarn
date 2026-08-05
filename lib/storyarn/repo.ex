defmodule Storyarn.Repo do
  use Ecto.Repo,
    otp_app: :storyarn,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Runs `fun` in a real PostgreSQL repeatable-read transaction.

  Postgrex ignores an `:isolation` transaction option, so the isolation level
  must be the first statement after `BEGIN`. SQL sandbox tests already run
  inside an outer transaction and cannot change its isolation level.
  """
  @spec repeatable_read((-> result), keyword()) :: {:ok, result} | {:error, term()} when result: term()
  def repeatable_read(fun, opts \\ []) when is_function(fun, 0) and is_list(opts) do
    transaction(
      fn ->
        set_repeatable_read!()
        fun.()
      end,
      opts
    )
  end

  defp set_repeatable_read! do
    if !Application.get_env(:storyarn, :sql_sandbox, false) do
      query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
    end

    :ok
  end
end
