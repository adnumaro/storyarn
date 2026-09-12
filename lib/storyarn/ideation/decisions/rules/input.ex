defmodule Storyarn.Ideation.Decisions.Rules.Input do
  @moduledoc false
  alias Storyarn.Platform.Kernel.MapAccess

  defguard valid_id(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807
  defguard valid_version(version) when is_integer(version) and version in 1..100
  def get(attrs, key), do: MapAccess.get_flexible(attrs, key)

  def command(attrs) when is_map(attrs) do
    with {:ok, title} <- text(get(attrs, :title), 160),
         {:ok, conclusion} <- text(get(attrs, :conclusion), 4000),
         {:ok, reason} <- text(get(attrs, :reason), 4000),
         responsible when valid_id(responsible) <- get(attrs, :responsible_id),
         {:ok, sources} <- selections(get(attrs, :sources), true),
         {:ok, key} <- request_key(get(attrs, :request_key)) do
      {:ok, %{title: title, conclusion: conclusion, reason: reason, responsible_id: responsible, sources: sources}, key}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_decision}
    end
  end

  def command(_), do: {:error, :invalid_decision}

  def request_key(value) do
    case Ecto.UUID.cast(value) do
      {:ok, key} -> {:ok, key}
      _ -> {:error, :invalid_request_key}
    end
  end

  def selections(items, expected? \\ false)

  def selections(items, expected?) when is_list(items) and length(items) in 1..20 do
    normalized = Enum.map(items, &selection(&1, expected?))

    if Enum.all?(normalized, &is_map/1) and length(Enum.uniq_by(normalized, &{&1.type, &1.id})) == length(items),
      do: {:ok, Enum.sort_by(normalized, &{&1.type, &1.id})},
      else: {:error, :invalid_decision_sources}
  end

  def selections(_, _), do: {:error, :invalid_decision_sources}

  defp selection(item, expected?) when is_map(item) do
    type = get(item, :type)
    id = get(item, :id)
    version = get(item, :version)
    identity = get(item, :identity)

    if type in ~w(idea group) and valid_id(id) and
         (not expected? or (is_integer(version) and version > 0 and match?({:ok, _}, Ecto.UUID.cast(identity)))) do
      %{type: type, id: id, version: if(expected?, do: version), identity: if(expected?, do: identity)}
    end
  end

  defp selection(_, _), do: nil

  def page(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: page_values(opts), else: {:error, :invalid_pagination}
  end

  def page(_), do: {:error, :invalid_pagination}

  defp page_values(opts) do
    limit = Keyword.get(opts, :limit, 20)
    before_id = Keyword.get(opts, :before_id)
    search = Keyword.get(opts, :search, "")
    type = Keyword.get(opts, :type, "idea")

    if is_integer(limit) and limit in 1..50 and (is_nil(before_id) or valid_id(before_id)) and
         valid_search?(search) and type in ~w(idea group) do
      {:ok, %{limit: limit, before_id: before_id, search: String.downcase(String.trim(search)), type: type}}
    else
      {:error, :invalid_pagination}
    end
  end

  defp valid_search?(search) when is_binary(search) and byte_size(search) <= 800 do
    String.valid?(search) and String.length(search) <= 200
  end

  defp valid_search?(_), do: false

  def fingerprint(operation, session_identity, decision_identity, version, attrs) do
    attrs =
      if Map.has_key?(attrs, :sources),
        do: Map.update!(attrs, :sources, &Enum.sort(Enum.map(&1, fn source -> Map.delete(source, :id) end))),
        else: attrs

    :crypto.hash(
      :sha256,
      :erlang.term_to_binary({:ideation_decision_v1, operation, session_identity, decision_identity, version, attrs})
    )
  end

  defp text(value, max) when is_binary(value) and byte_size(value) <= max * 4 do
    if String.valid?(value) and String.length(value) <= max and String.trim(value) != "",
      do: {:ok, String.trim(value)},
      else: {:error, :invalid_decision}
  end

  defp text(_, _), do: {:error, :invalid_decision}
end
