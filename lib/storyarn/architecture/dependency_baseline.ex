defmodule Storyarn.Architecture.DependencyBaseline do
  @moduledoc false

  alias Storyarn.Architecture.DependencyPolicy

  @known_kinds ~w(runtime export compile)

  @type edge :: {String.t(), String.t(), String.t()}

  @spec load_all!(Path.t(), [atom()]) :: %{atom() => MapSet.t(edge())}
  def load_all!(directory, consumers) do
    validate_file_set!(directory, consumers)

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

    validate_unique_pairs!(tuples, path)

    edge_set
  rescue
    error in [File.Error, Jason.DecodeError] ->
      reraise ArgumentError,
              [message: "could not load architecture baseline #{path}: #{Exception.message(error)}"],
              __STACKTRACE__
  end

  @spec encode(atom(), MapSet.t(edge())) :: binary()
  def encode(consumer, edges) do
    sorted_edges = Enum.sort(edges)
    validate_unique_pairs!(sorted_edges, "#{consumer} baseline")

    Jason.encode!(
      %{
        "version" => 1,
        "consumer" => Atom.to_string(consumer),
        "edges" => Enum.map(sorted_edges, &Tuple.to_list/1)
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

  defp validate_file_set!(directory, consumers) do
    expected_files = MapSet.new(consumers, &"#{&1}.json")

    actual_files =
      directory
      |> Path.join("*.json")
      |> Path.wildcard()
      |> MapSet.new(&Path.basename/1)

    missing = expected_files |> MapSet.difference(actual_files) |> Enum.sort()
    unexpected = actual_files |> MapSet.difference(expected_files) |> Enum.sort()

    if missing != [] or unexpected != [] do
      raise ArgumentError,
            "architecture baseline file set mismatch in #{directory}; " <>
              "missing: #{inspect(missing)}, unexpected: #{inspect(unexpected)}"
    end
  end

  defp validate_unique_pairs!(tuples, path) do
    duplicate_pairs =
      tuples
      |> Enum.group_by(fn {source, target, _kind} -> {source, target} end)
      |> Enum.filter(fn {_pair, edges} -> length(edges) > 1 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    if duplicate_pairs != [] do
      raise ArgumentError,
            "architecture baseline contains multiple dependency kinds for the same source-target pair " <>
              "in #{path}: #{inspect(duplicate_pairs)}"
    end
  end

  defp validate_document!(%{"version" => 1, "consumer" => consumer, "edges" => edges}, expected_consumer, path)
       when is_list(edges) do
    if consumer != Atom.to_string(expected_consumer) do
      raise ArgumentError,
            "architecture baseline consumer mismatch in #{path}: " <>
              "expected #{expected_consumer}, got #{inspect(consumer)}"
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
