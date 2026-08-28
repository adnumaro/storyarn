defmodule Storyarn.Flows.Versioning.Queries.History do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Versioning.EntityVersionRecord
  alias Storyarn.Repo

  @entity_type "flow"

  @type version :: EntityVersionRecord.t()

  @spec list_versions(integer(), keyword()) :: [version()]
  def list_versions(flow_id, opts \\ []) when is_integer(flow_id) do
    list_versions(@entity_type, flow_id, opts)
  end

  def list_versions(@entity_type, flow_id, opts) when is_integer(flow_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    Repo.all(
      from(version in EntityVersionRecord,
        where: version.entity_type == @entity_type and version.entity_id == ^flow_id,
        order_by: [desc: version.version_number],
        limit: ^limit,
        offset: ^offset,
        preload: [:created_by]
      )
    )
  end

  def list_versions(_entity_type, _entity_id, _opts), do: []

  @spec get_version(integer(), integer()) :: version() | nil
  def get_version(flow_id, version_number), do: get_version(@entity_type, flow_id, version_number)

  def get_version(@entity_type, flow_id, version_number) when is_integer(flow_id) and is_integer(version_number) do
    Repo.get_by(EntityVersionRecord,
      entity_type: @entity_type,
      entity_id: flow_id,
      version_number: version_number
    )
  end

  def get_version(_entity_type, _entity_id, _version_number), do: nil

  @spec get_latest_version(integer()) :: version() | nil
  def get_latest_version(flow_id), do: get_latest_version(@entity_type, flow_id)

  def get_latest_version(@entity_type, flow_id) when is_integer(flow_id) do
    Repo.one(
      from(version in EntityVersionRecord,
        where: version.entity_type == @entity_type and version.entity_id == ^flow_id,
        order_by: [desc: version.version_number],
        limit: 1
      )
    )
  end

  def get_latest_version(_entity_type, _entity_id), do: nil

  @spec count_versions(integer()) :: non_neg_integer()
  def count_versions(flow_id), do: count_versions(@entity_type, flow_id)

  def count_versions(@entity_type, flow_id) when is_integer(flow_id) do
    Repo.one(
      from(version in EntityVersionRecord,
        where: version.entity_type == @entity_type and version.entity_id == ^flow_id,
        select: count(version.id)
      )
    )
  end

  def count_versions(_entity_type, _entity_id), do: 0

  @spec get_adjacent_version_numbers(integer(), integer()) ::
          {integer() | nil, integer() | nil}
  def get_adjacent_version_numbers(flow_id, current_number),
    do: get_adjacent_version_numbers(@entity_type, flow_id, current_number)

  def get_adjacent_version_numbers(@entity_type, flow_id, current_number)
      when is_integer(flow_id) and is_integer(current_number) do
    previous =
      Repo.one(
        from(version in EntityVersionRecord,
          where:
            version.entity_type == @entity_type and version.entity_id == ^flow_id and
              version.version_number < ^current_number,
          order_by: [desc: version.version_number],
          limit: 1,
          select: version.version_number
        )
      )

    following =
      Repo.one(
        from(version in EntityVersionRecord,
          where:
            version.entity_type == @entity_type and version.entity_id == ^flow_id and
              version.version_number > ^current_number,
          order_by: [asc: version.version_number],
          limit: 1,
          select: version.version_number
        )
      )

    {previous, following}
  end

  def get_adjacent_version_numbers(_entity_type, _entity_id, _current_number), do: {nil, nil}

  @spec count_versions_since(integer(), DateTime.t()) :: non_neg_integer()
  def count_versions_since(flow_id, %DateTime{} = since), do: count_versions_since(@entity_type, flow_id, since)

  def count_versions_since(@entity_type, flow_id, %DateTime{} = since) when is_integer(flow_id) do
    Repo.aggregate(
      from(version in EntityVersionRecord,
        where:
          version.entity_type == @entity_type and version.entity_id == ^flow_id and
            version.inserted_at > ^since
      ),
      :count
    )
  end

  def count_versions_since(_entity_type, _entity_id, _since), do: 0

  def next_version_number(flow_id) do
    (Repo.one(
       from(version in EntityVersionRecord,
         where: version.entity_type == @entity_type and version.entity_id == ^flow_id,
         select: max(version.version_number)
       )
     ) || 0) + 1
  end
end
