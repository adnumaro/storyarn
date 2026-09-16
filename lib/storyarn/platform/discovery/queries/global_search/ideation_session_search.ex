defmodule Storyarn.Platform.GlobalSearch.IdeationSessionSearch do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Platform.GlobalSearch.Persistence.IdeationSessionRecord
  alias Storyarn.Platform.Shared.SearchHelpers
  alias Storyarn.Repo

  @default_limit 50

  @spec search_in_projects([integer()], String.t(), keyword()) :: [IdeationSessionRecord.t()]
  def search_in_projects(project_ids, query, opts \\ []) when is_list(project_ids) and is_binary(query) do
    limit = normalize_limit(Keyword.get(opts, :limit, @default_limit))
    query = String.trim(query)

    if project_ids == [] or query == "" do
      []
    else
      pattern = "%#{SearchHelpers.sanitize_like_query(query)}%"

      Repo.all(
        from(session in IdeationSessionRecord,
          where: session.project_id in ^project_ids and is_nil(session.deleted_at),
          where: ilike(session.name, ^pattern),
          order_by: [asc: session.name, asc: session.id],
          limit: ^limit
        ),
        log: false
      )
    end
  end

  defp normalize_limit(limit) when is_integer(limit), do: max(limit, 1)
  defp normalize_limit(_limit), do: @default_limit
end
