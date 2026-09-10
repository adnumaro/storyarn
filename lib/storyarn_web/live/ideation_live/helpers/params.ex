defmodule StoryarnWeb.IdeationLive.Helpers.Params do
  @moduledoc false
  @max_integer 9_007_199_254_740_991

  def positive(value) when is_integer(value) and value > 0 and value <= @max_integer, do: {:ok, value}

  def positive(value) when is_binary(value) and byte_size(value) <= 16 do
    case Integer.parse(value) do
      {number, ""} -> positive(number)
      _ -> {:error, :invalid_parameters}
    end
  end

  def positive(_), do: {:error, :invalid_parameters}
  def optional_id(nil), do: {:ok, nil}
  def optional_id(""), do: {:ok, nil}
  def optional_id(value), do: positive(value)

  def fields(params, keys), do: Map.take(params, Enum.map(keys, &Atom.to_string/1))

  def creation(params) when is_map(params) do
    with {:ok, version} <- positive(params["configuration_version"]),
         {:ok, round} <- creation_round(params) do
      {:ok,
       params
       |> fields([:title, :body, :state, :request_key, :canvas, :connection])
       |> Map.put("configuration_version", version)
       |> Map.merge(round)}
    end
  end

  def creation(_), do: {:error, :invalid_parameters}

  def round_filter("all"), do: {:ok, :all}
  def round_filter(nil), do: {:ok, nil}
  def round_filter(value), do: positive(value)

  defp creation_round(%{"round_id" => nil}), do: {:ok, %{"round_id" => nil}}

  defp creation_round(%{"round_id" => value}) do
    with {:ok, id} <- positive(value), do: {:ok, %{"round_id" => id}}
  end

  defp creation_round(_), do: {:ok, %{}}

  def filter(value, allowed, default) do
    Enum.find(allowed, default, &(Atom.to_string(&1) == value))
  end

  def targets(values) when is_list(values) and length(values) in 1..200 do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, targets} ->
      with true <- is_map(value),
           {:ok, id} <- positive(value["idea_id"]),
           {:ok, revision} <- positive(value["revision"]) do
        {:cont, {:ok, [%{idea_id: id, revision: revision} | targets]}}
      else
        _ -> {:halt, {:error, :invalid_parameters}}
      end
    end)
  end

  def targets(_), do: {:error, :invalid_parameters}
end
