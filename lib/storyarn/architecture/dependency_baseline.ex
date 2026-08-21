defmodule Storyarn.Architecture.DependencyBaseline do
  @moduledoc false

  alias Storyarn.Architecture.DependencyPolicy

  @known_kinds ~w(runtime export compile)

  @type edge :: {String.t(), String.t(), String.t()}

  @spec load_all!(Path.t(), [atom()]) :: %{atom() => MapSet.t(edge())}
  def load_all!(directory, consumers) do
    Map.new(consumers, fn consumer ->
      path = Path.join(directory, "#{consumer}.json")
      {consumer, load!(path, consumer)}
    end)
  end

  @spec load!(Path.t(), atom()) :: MapSet.t(edge())
  def load!(path, expected_consumer) do
    document =
      path
      |> File.read!()
      |> Jason.decode!()

    edges = validate_document!(document, expected_consumer, path)
    tuples = Enum.map(edges, &edge_tuple!/1)

    if tuples != Enum.sort(tuples) do
      raise ArgumentError, "architecture baseline must be sorted: #{path}"
    end

    edge_set = MapSet.new(tuples)

    if MapSet.size(edge_set) != length(tuples) do
      raise ArgumentError, "architecture baseline contains duplicate edges: #{path}"
    end

    edge_set
  rescue
    error in [File.Error, Jason.DecodeError] ->
      reraise ArgumentError,
              [message: "could not load architecture baseline #{path}: #{Exception.message(error)}"],
              __STACKTRACE__
  end

  @spec encode(atom(), MapSet.t(edge())) :: binary()
  def encode(consumer, edges) do
    Jason.encode!(
      %{
        "version" => 1,
        "consumer" => Atom.to_string(consumer),
        "edges" => edges |> Enum.sort() |> Enum.map(&Tuple.to_list/1)
      },
      pretty: true
    ) <> "\n"
  end

  @spec compare_all(map(), map()) :: map()
  def compare_all(actual, expected) do
    Map.new(expected, fn {consumer, expected_edges} ->
      actual_edges = Map.fetch!(actual, consumer)
      {consumer, DependencyPolicy.compare(actual_edges, expected_edges)}
    end)
  end

  defp validate_document!(%{"version" => 1, "consumer" => consumer, "edges" => edges}, expected_consumer, path)
       when is_list(edges) do
    if consumer != Atom.to_string(expected_consumer) do
      raise ArgumentError,
            "architecture baseline consumer mismatch in #{path}: expected #{expected_consumer}, got #{inspect(consumer)}"
    end

    edges
  end

  defp validate_document!(_document, _expected_consumer, path) do
    raise ArgumentError, "invalid architecture baseline document: #{path}"
  end

  defp edge_tuple!([source, target, kind]) when is_binary(source) and is_binary(target) and kind in @known_kinds do
    {source, target, kind}
  end

  defp edge_tuple!(edge), do: raise(ArgumentError, "invalid architecture baseline edge: #{inspect(edge)}")
end
