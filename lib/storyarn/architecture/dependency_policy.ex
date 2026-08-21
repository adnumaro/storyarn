defmodule Storyarn.Architecture.DependencyPolicy do
  @moduledoc false

  @known_kinds ~w(runtime export compile)
  @kind_strength %{"runtime" => 0, "export" => 1, "compile" => 2}

  @type boundary :: atom()
  @type edge :: {String.t(), String.t(), String.t()}
  @type kind_change :: %{
          source: String.t(),
          target: String.t(),
          from: String.t(),
          to: String.t()
        }

  @spec load!(Path.t()) :: map()
  def load!(path) do
    {policy, _binding} = Code.eval_file(path)
    validate_policy!(policy)
  end

  @spec decode_graph!(binary()) :: map()
  def decode_graph!(json) do
    case Jason.decode(json) do
      {:ok, graph} when is_map(graph) -> graph
      {:ok, _other} -> raise ArgumentError, "xref graph must be a JSON object"
      {:error, error} -> raise ArgumentError, "invalid xref JSON: #{Exception.message(error)}"
    end
  end

  @spec forbidden_edges(map(), map()) :: %{boundary() => MapSet.t(edge())}
  def forbidden_edges(graph, policy) do
    policy = validate_policy!(policy)

    empty =
      policy.forbidden_dependencies
      |> Map.keys()
      |> Map.new(&{&1, MapSet.new()})

    Enum.reduce(graph, empty, &collect_source_edges(&1, &2, policy))
  end

  @spec compare(MapSet.t(edge()), MapSet.t(edge())) :: %{
          new: [edge()],
          stale: [edge()],
          strengthened: [kind_change()],
          weakened: [kind_change()]
        }
  def compare(actual, expected) do
    actual_by_pair = edges_by_pair(actual)
    expected_by_pair = edges_by_pair(expected)

    common_pairs =
      actual_by_pair
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.intersection(expected_by_pair |> Map.keys() |> MapSet.new())

    changes =
      common_pairs
      |> Enum.flat_map(fn pair ->
        actual_kind = Map.fetch!(actual_by_pair, pair)
        expected_kind = Map.fetch!(expected_by_pair, pair)

        if actual_kind == expected_kind do
          []
        else
          {source, target} = pair

          [
            %{
              source: source,
              target: target,
              from: expected_kind,
              to: actual_kind
            }
          ]
        end
      end)
      |> Enum.sort_by(&{&1.source, &1.target})

    %{
      new: edges_with_new_pairs(actual, expected_by_pair),
      stale: edges_with_new_pairs(expected, actual_by_pair),
      strengthened: Enum.filter(changes, &stronger?(&1.to, &1.from)),
      weakened: Enum.reject(changes, &stronger?(&1.to, &1.from))
    }
  end

  @spec clean?(map()) :: boolean()
  def clean?(comparison) do
    Enum.all?([:new, :stale, :strengthened, :weakened], &(Map.fetch!(comparison, &1) == []))
  end

  @spec validate_policy!(map()) :: map()
  def validate_policy!(
        %{
          version: 1,
          boundaries: boundaries,
          forbidden_dependencies: forbidden,
          always_allowed_targets: allowed_targets,
          exceptions: exceptions
        } = policy
      )
      when is_map(boundaries) and is_map(forbidden) and is_list(allowed_targets) and is_list(exceptions) do
    validate_boundaries!(boundaries)
    validate_forbidden_dependencies!(forbidden, boundaries)
    Enum.each(allowed_targets, &validate_root!/1)
    Enum.each(exceptions, &validate_exception!(&1, boundaries))
    policy
  end

  def validate_policy!(_policy) do
    raise ArgumentError,
          "architecture policy must define version 1, boundaries, forbidden_dependencies, " <>
            "always_allowed_targets, and exceptions"
  end

  defp forbidden?(_source, nil, _target, _target_boundary, _kind, _policy), do: false
  defp forbidden?(_source, boundary, _target, boundary, _kind, _policy), do: false
  defp forbidden?(_source, _source_boundary, _target, nil, _kind, _policy), do: false

  defp forbidden?(source, source_boundary, target, target_boundary, kind, policy) do
    target_boundary in Map.get(policy.forbidden_dependencies, source_boundary, []) and
      not matches_any_root?(target, policy.always_allowed_targets) and
      not exception?(source, target, kind, policy.exceptions)
  end

  defp collect_source_edges({source, dependencies}, acc, policy) do
    source = normalize_path!(source)
    source_boundary = boundary_for(source, policy.boundaries)

    Enum.reduce(dependencies, acc, fn dependency, edges ->
      collect_dependency_edge(dependency, edges, source, source_boundary, policy)
    end)
  end

  defp collect_dependency_edge({target, kind}, edges, source, source_boundary, policy) do
    target = normalize_path!(target)
    kind = validate_kind!(kind)
    target_boundary = boundary_for(target, policy.boundaries)

    if forbidden?(source, source_boundary, target, target_boundary, kind, policy) do
      Map.update!(edges, source_boundary, &MapSet.put(&1, {source, target, kind}))
    else
      edges
    end
  end

  defp exception?(source, target, kind, exceptions) do
    Enum.any?(exceptions, fn exception ->
      exception.source == source and exception.target == target and kind in exception.kinds
    end)
  end

  defp boundary_for(path, boundaries) do
    boundaries
    |> Enum.flat_map(fn {boundary, roots} -> Enum.map(roots, &{boundary, &1}) end)
    |> Enum.filter(fn {_boundary, root} -> matches_root?(path, root) end)
    |> Enum.max_by(fn {_boundary, root} -> String.length(root) end, fn -> nil end)
    |> case do
      nil -> nil
      {boundary, _root} -> boundary
    end
  end

  defp matches_any_root?(path, roots), do: Enum.any?(roots, &matches_root?(path, &1))

  defp matches_root?(path, root) do
    if String.ends_with?(root, "/") do
      String.starts_with?(path, root)
    else
      path == root
    end
  end

  defp edges_by_pair(edges) do
    Map.new(edges, fn {source, target, kind} -> {{source, target}, kind} end)
  end

  defp edges_with_new_pairs(edges, other_by_pair) do
    edges
    |> Enum.reject(fn {source, target, _kind} -> Map.has_key?(other_by_pair, {source, target}) end)
    |> Enum.sort()
  end

  defp stronger?(kind, other_kind) do
    Map.fetch!(@kind_strength, kind) > Map.fetch!(@kind_strength, other_kind)
  end

  defp validate_boundaries!(boundaries) do
    Enum.each(boundaries, fn
      {name, roots} when is_atom(name) and is_list(roots) and roots != [] ->
        Enum.each(roots, &validate_root!/1)

      invalid ->
        raise ArgumentError, "invalid architecture boundary: #{inspect(invalid)}"
    end)

    duplicate_roots =
      boundaries
      |> Enum.flat_map(fn {name, roots} -> Enum.map(roots, &{&1, name}) end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.filter(fn {_root, owners} -> length(owners) > 1 end)

    if duplicate_roots != [] do
      raise ArgumentError, "architecture roots must have one owner: #{inspect(duplicate_roots)}"
    end
  end

  defp validate_forbidden_dependencies!(forbidden, boundaries) do
    boundary_names = boundaries |> Map.keys() |> MapSet.new()

    Enum.each(forbidden, &validate_forbidden_rule!(&1, boundary_names))
  end

  defp validate_forbidden_rule!({source, targets}, boundary_names) when is_atom(source) and is_list(targets) do
    if !MapSet.member?(boundary_names, source) do
      raise ArgumentError, "unknown source boundary: #{inspect(source)}"
    end

    Enum.each(targets, &validate_forbidden_target!(&1, source, boundary_names))
  end

  defp validate_forbidden_rule!(invalid, _boundary_names) do
    raise ArgumentError, "invalid forbidden dependency rule: #{inspect(invalid)}"
  end

  defp validate_forbidden_target!(target, source, boundary_names) do
    if !MapSet.member?(boundary_names, target) do
      raise ArgumentError, "unknown target boundary: #{inspect(target)}"
    end

    if target == source do
      raise ArgumentError, "same-boundary dependencies cannot be forbidden: #{source}"
    end
  end

  defp validate_exception!(%{source: source, target: target, kinds: kinds, reason: reason}, boundaries)
       when is_binary(source) and is_binary(target) and is_list(kinds) and kinds != [] and is_binary(reason) and
              reason != "" do
    source = normalize_path!(source)
    target = normalize_path!(target)

    if is_nil(boundary_for(source, boundaries)) or is_nil(boundary_for(target, boundaries)) do
      raise ArgumentError, "architecture exceptions must connect two classified paths"
    end

    Enum.each(kinds, &validate_kind!/1)
  end

  defp validate_exception!(invalid, _boundaries) do
    raise ArgumentError, "invalid architecture exception: #{inspect(invalid)}"
  end

  defp validate_root!(root) when is_binary(root) and root != "" do
    normalized = normalize_path!(root)

    if Path.type(normalized) == :absolute or String.contains?(normalized, "..") do
      raise ArgumentError, "architecture roots must be repository-relative: #{inspect(root)}"
    end

    :ok
  end

  defp validate_root!(root), do: raise(ArgumentError, "invalid architecture root: #{inspect(root)}")

  defp normalize_path!(path) when is_binary(path) do
    String.replace(path, "\\", "/")
  end

  defp normalize_path!(path), do: raise(ArgumentError, "invalid xref path: #{inspect(path)}")

  defp validate_kind!(kind) when kind in @known_kinds, do: kind
  defp validate_kind!(kind), do: raise(ArgumentError, "unknown xref dependency kind: #{inspect(kind)}")
end
