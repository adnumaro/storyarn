defmodule Storyarn.Ideation.Ideas.Rules.Connections do
  @moduledoc false
  import Storyarn.Ideation.Ideas.Rules.Input, only: [valid_id: 1]

  alias Storyarn.Ideation.Ideas.Rules.Input

  def normalize(attrs) when is_map(attrs) do
    with {:ok, key} <- Input.request_key(attrs),
         {:ok, changes} <- changes(Input.get(attrs, :changes)),
         {:ok, versions} <- versions(Input.get(attrs, :versions)),
         source_ids = changes |> Enum.map(& &1.source_id) |> Enum.uniq() |> Enum.sort(),
         true <- Enum.sort(Map.keys(versions)) == source_ids do
      {:ok, %{request_key: key, changes: changes, versions: versions}}
    else
      false -> {:error, :invalid_connections}
      {:error, _} = error -> error
    end
  end

  def normalize(_), do: {:error, :invalid_connections}

  def creation(nil), do: {:ok, []}

  def creation(attrs) when is_map(attrs) do
    case Input.get(attrs, :source_ids) do
      ids when is_list(ids) and length(ids) in 1..100 ->
        if Enum.all?(ids, &valid_id(&1)) and length(Enum.uniq(ids)) == length(ids),
          do: {:ok, Enum.sort(ids)},
          else: {:error, :invalid_connections}

      _ ->
        {:error, :invalid_connections}
    end
  end

  def creation(_), do: {:error, :invalid_connections}

  defp changes(entries) when is_list(entries) and length(entries) in 1..100 do
    with {:ok, changes} <- traverse(entries, &change/1),
         true <- length(Enum.uniq_by(changes, &{&1.source_id, &1.target_id})) == length(changes) do
      {:ok, Enum.sort_by(changes, &{&1.source_id, &1.target_id})}
    else
      _ -> {:error, :invalid_connections}
    end
  end

  defp changes(_), do: {:error, :invalid_connections}

  defp change(attrs) when is_map(attrs) do
    source = Input.get(attrs, :source_id)
    target = Input.get(attrs, :target_id)
    connected = Input.get(attrs, :connected)
    direction = Input.get(attrs, :direction)
    explicit_direction? = Map.has_key?(attrs, :direction) or Map.has_key?(attrs, "direction")

    if valid_id(source) and valid_id(target) and source != target and is_boolean(connected) and
         (not explicit_direction? or direction in ~w(none forward backward both)) do
      change = %{source_id: source, target_id: target, connected: connected}
      {:ok, if(explicit_direction?, do: Map.put(change, :direction, direction), else: change)}
    else
      {:error, :invalid_connections}
    end
  end

  defp change(_), do: {:error, :invalid_connections}

  defp versions(entries) when is_list(entries) and length(entries) in 1..100 do
    with {:ok, pairs} <- traverse(entries, &version/1),
         versions = Map.new(pairs),
         true <- map_size(versions) == length(entries) do
      {:ok, versions}
    else
      _ -> {:error, :invalid_connections}
    end
  end

  defp versions(_), do: {:error, :invalid_connections}

  defp version(attrs) when is_map(attrs) do
    id = Input.get(attrs, :id)
    value = Input.get(attrs, :version)

    if valid_id(id) and is_integer(value) and value >= 0 and value < 2_147_483_647,
      do: {:ok, {id, value}},
      else: {:error, :invalid_connections}
  end

  defp version(_), do: {:error, :invalid_connections}

  defp traverse(entries, function) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, result} ->
      case function.(entry) do
        {:ok, value} -> {:cont, {:ok, [value | result]}}
        error -> {:halt, error}
      end
    end)
  end
end
