defmodule Storyarn.AI.Integrations.Queries.Integrations do
  @moduledoc "Read-only actor-scoped integration lookups."

  import Ecto.Query

  alias Storyarn.AI.Integration
  alias Storyarn.AI.Provider
  alias Storyarn.Repo

  @type actor :: %{required(:id) => integer(), optional(atom()) => term()}

  @spec list_active(actor() | integer()) :: [Integration.t()]
  def list_active(%{id: user_id}), do: list_active(user_id)

  def list_active(user_id) when is_integer(user_id) do
    Repo.all(
      from(integration in Integration,
        where: integration.user_id == ^user_id and is_nil(integration.revoked_at),
        order_by: [asc: integration.provider]
      )
    )
  end

  @spec get_active(actor() | integer(), Provider.id() | String.t()) :: Integration.t() | nil
  def get_active(user_or_id, provider) do
    user_id = user_id_of(user_or_id)
    provider = to_string(provider)

    Repo.one(
      from(integration in Integration,
        where:
          integration.user_id == ^user_id and integration.provider == ^provider and
            is_nil(integration.revoked_at)
      )
    )
  end

  defp user_id_of(%{id: id}), do: id
  defp user_id_of(id) when is_integer(id), do: id
end
