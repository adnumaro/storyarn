defmodule Storyarn.Ideation.References.Input do
  @moduledoc false
  alias Storyarn.Platform.Kernel.MapAccess

  @types ~w(sheet flow scene asset localization)
  @relations ~w(origin reference affects result work)
  defguard valid_id(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807
  defguard valid_version(version) when is_integer(version) and version > 0 and version < 2_147_483_647
  def types, do: @types
  def relations, do: @relations
  def get(attrs, key), do: MapAccess.get_flexible(attrs, key)

  def create(attrs) when is_map(attrs) do
    type = get(attrs, :target_type)
    id = get(attrs, :target_id)
    relation = get(attrs, :relation) || "reference"

    with true <- type in @types and valid_id(id) and relation in @relations,
         {:ok, key} <- request_key(get(attrs, :request_key)) do
      {:ok, %{target_type: type, target_id: id, relation: relation, request_key: key}}
    else
      _ -> {:error, :invalid_reference}
    end
  end

  def create(_), do: {:error, :invalid_reference}

  def request_key(value) do
    case Ecto.UUID.cast(value) do
      {:ok, key} -> {:ok, key}
      _ -> {:error, :invalid_request_key}
    end
  end

  def page(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: page_options(opts), else: {:error, :invalid_pagination}
  end

  def page(_), do: {:error, :invalid_pagination}

  defp page_options(opts) do
    limit = Keyword.get(opts, :limit, 20)
    before_id = Keyword.get(opts, :before_id)

    if is_integer(limit) and limit in 1..50 and (is_nil(before_id) or valid_id(before_id)),
      do: {:ok, %{limit: limit, before_id: before_id}},
      else: {:error, :invalid_pagination}
  end

  def fingerprint(operation, idea_id, id, version, attrs) do
    :crypto.hash(:sha256, :erlang.term_to_binary({:ideation_reference_v1, operation, idea_id, id, version, attrs}))
  end
end
