defmodule Storyarn.Architecture.DependencyPolicy do
  @moduledoc false

  @known_kinds ~w(runtime export compile)
  @kind_strength %{"runtime" => 0, "export" => 1, "compile" => 2}
  @infrastructure_boundary :infrastructure
  @web_infrastructure_boundary :web_infrastructure
  @presentation_boundary :presentation_adapters
  @required_classification_roots [
    "lib/storyarn.ex",
    "lib/storyarn/",
    "lib/storyarn_web.ex",
    "lib/storyarn_web/"
  ]

  @type boundary :: atom()
  @type edge :: {String.t(), String.t(), String.t()}
  @type kind_change :: %{
          source: String.t(),
          target: String.t(),
          from: String.t(),
          to: String.t()
        }

  @type reviewed_edges :: %{
          durable_contracts: [edge()],
          migration_exceptions: [edge()]
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

  @spec unclassified_paths(map(), map()) :: [String.t()]
  def unclassified_paths(graph, policy) when is_map(graph) do
    policy = validate_policy!(policy)

    graph
    |> Enum.flat_map(fn {source, dependencies} ->
      [normalize_path!(source) | Enum.map(dependencies, fn {target, _kind} -> normalize_path!(target) end)]
    end)
    |> Enum.filter(fn path ->
      matches_any_root?(path, policy.classification_roots) and boundary_for(path, policy.boundaries) == nil
    end)
    |> Enum.uniq()
    |> Enum.sort()
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

  @spec zero_debt_baseline_violations(map(), map()) :: %{boundary() => [edge()]}
  def zero_debt_baseline_violations(baselines, policy) when is_map(baselines) do
    policy = validate_policy!(policy)

    Enum.reduce(policy.zero_debt_consumers, %{}, fn consumer, violations ->
      edges = baselines |> Map.fetch!(consumer) |> Enum.sort()

      if edges == [] do
        violations
      else
        Map.put(violations, consumer, edges)
      end
    end)
  end

  @spec isolated_context_baseline_violations(map(), map()) :: %{boundary() => [edge()]}
  def isolated_context_baseline_violations(baselines, policy) when is_map(baselines) do
    policy = validate_policy!(policy)
    baseline_edges = baselines |> Map.values() |> Enum.flat_map(&MapSet.to_list/1)

    Enum.reduce(policy.isolated_contexts, %{}, fn context, violations ->
      incoming_edges =
        baseline_edges
        |> Enum.filter(fn {source, target, _kind} ->
          boundary_for(source, policy.boundaries) != context and
            boundary_for(target, policy.boundaries) == context
        end)
        |> Enum.uniq()
        |> Enum.sort()

      if incoming_edges == [] do
        violations
      else
        Map.put(violations, context, incoming_edges)
      end
    end)
  end

  @doc """
  Returns reviewed policy edges that no longer exist in the xref graph.

  Durable contracts and migration exceptions are deliberately checked outside
  the forbidden-dependency baseline: both are exact reviewed edges, so neither
  may survive in policy after the corresponding dependency disappears.
  """
  @spec stale_reviewed_edges(map(), map()) :: reviewed_edges()
  def stale_reviewed_edges(graph, policy) when is_map(graph) do
    policy = validate_policy!(policy)
    actual_edges = graph_edges(graph)

    %{
      durable_contracts: stale_policy_edges(policy.durable_contracts, actual_edges),
      migration_exceptions: stale_policy_edges(policy.migration_exceptions, actual_edges)
    }
  end

  @doc "Returns the number of exact durable and temporary policy edges."
  @spec reviewed_edge_counts(map()) :: %{
          durable_contracts: non_neg_integer(),
          migration_exceptions: non_neg_integer()
        }
  def reviewed_edge_counts(policy) do
    policy = validate_policy!(policy)

    %{
      durable_contracts: count_policy_edges(policy.durable_contracts),
      migration_exceptions: count_policy_edges(policy.migration_exceptions)
    }
  end

  @spec validate_policy!(map()) :: map()
  def validate_policy!(
        %{
          version: 2,
          bounded_contexts: bounded_contexts,
          classification_roots: classification_roots,
          boundaries: boundaries,
          forbidden_dependencies: forbidden,
          zero_debt_consumers: zero_debt_consumers,
          isolated_contexts: isolated_contexts,
          globally_allowed_technical_targets: globally_allowed_technical_targets,
          additional_durable_contract_targets: additional_durable_contract_targets,
          durable_contracts: _durable_contracts,
          migration_exceptions: _migration_exceptions
        } = policy
      ) do
    validate_policy_types!(policy)
    validate_classification_roots!(classification_roots)
    validate_boundaries!(boundaries, classification_roots)
    validate_forbidden_dependencies!(forbidden, boundaries)
    validate_bounded_contexts!(bounded_contexts, boundaries)
    validate_protected_dependency_matrix!(bounded_contexts, forbidden)
    validate_zero_debt_consumers!(zero_debt_consumers, forbidden)
    validate_isolated_contexts!(isolated_contexts, bounded_contexts, zero_debt_consumers)
    validate_globally_allowed_technical_targets!(globally_allowed_technical_targets, boundaries, bounded_contexts)

    validate_additional_durable_contract_targets!(
      additional_durable_contract_targets,
      boundaries,
      bounded_contexts
    )

    validate_path_denials!(Map.get(policy, :path_denials, []))
    validate_directional_allowances!(Map.get(policy, :directional_allowances, []), boundaries)
    validate_reviewed_edges!(policy)
    policy
  end

  def validate_policy!(_policy), do: invalid_policy!()

  defp validate_policy_types!(policy) do
    valid_types? =
      Enum.all?([
        is_list(policy.bounded_contexts),
        is_list(policy.classification_roots),
        is_map(policy.boundaries),
        is_map(policy.forbidden_dependencies),
        is_list(policy.zero_debt_consumers),
        is_list(policy.isolated_contexts),
        is_list(policy.globally_allowed_technical_targets),
        is_list(policy.additional_durable_contract_targets),
        is_list(policy.durable_contracts),
        is_list(policy.migration_exceptions)
      ])

    if valid_types?, do: :ok, else: invalid_policy!()
  end

  defp invalid_policy! do
    raise ArgumentError,
          "architecture policy must define version 2, bounded_contexts, boundaries, " <>
            "classification_roots, forbidden_dependencies, zero_debt_consumers, isolated_contexts, " <>
            "globally_allowed_technical_targets, additional_durable_contract_targets, " <>
            "durable_contracts, and migration_exceptions"
  end

  defp forbidden?(_source, nil, _target, _target_boundary, _kind, _policy), do: false
  defp forbidden?(_source, boundary, _target, boundary, _kind, _policy), do: false
  defp forbidden?(_source, _source_boundary, _target, nil, _kind, _policy), do: false

  defp forbidden?(source, source_boundary, target, target_boundary, kind, policy) do
    target_boundary in Map.get(policy.forbidden_dependencies, source_boundary, []) and
      not matches_any_root?(target, policy.globally_allowed_technical_targets) and
      not directional_allowance?(source, target, kind, Map.get(policy, :directional_allowances, [])) and
      not reviewed_edge?(source, target, kind, policy)
  end

  defp directional_allowance?(source, target, kind, allowances) do
    Enum.any?(allowances, fn allowance ->
      String.starts_with?(source, allowance.source_root) and
        target == allowance.target and kind in allowance.kinds
    end)
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

    forbidden_edge? =
      source_boundary != nil and Map.has_key?(edges, source_boundary) and
        ((path_denied?(source, target, kind, Map.get(policy, :path_denials, [])) and
            not reviewed_edge?(source, target, kind, policy)) or
           forbidden?(source, source_boundary, target, target_boundary, kind, policy))

    if forbidden_edge? do
      Map.update!(edges, source_boundary, &MapSet.put(&1, {source, target, kind}))
    else
      edges
    end
  end

  defp path_denied?(source, target, kind, denials) do
    Enum.any?(denials, fn denial ->
      matches_root?(source, denial.source_root) and
        matches_root?(target, denial.target_root) and
        kind in denial.kinds
    end)
  end

  defp reviewed_edge?(source, target, kind, policy) do
    Enum.any?(policy.durable_contracts ++ policy.migration_exceptions, fn contract ->
      contract.source == source and contract.target == target and kind in contract.kinds
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

  defp validate_boundaries!(boundaries, classification_roots) do
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

    open_roots =
      for {boundary, roots} <- boundaries,
          root <- roots,
          covers_classification_root?(root, classification_roots),
          do: {boundary, root}

    if open_roots != [] do
      raise ArgumentError,
            "architecture boundary roots cannot cover an entire classification root: " <>
              inspect(Enum.sort(open_roots))
    end
  end

  defp covers_classification_root?(root, classification_roots) do
    Enum.any?(classification_roots, fn classification_root ->
      String.ends_with?(classification_root, "/") and matches_root?(classification_root, root)
    end)
  end

  defp validate_classification_roots!(classification_roots) do
    validate_exact_set!(
      MapSet.new(classification_roots),
      MapSet.new(@required_classification_roots),
      "classification roots"
    )

    duplicate_roots = classification_roots -- Enum.uniq(classification_roots)

    if duplicate_roots != [] do
      raise ArgumentError,
            "classification roots must be unique: #{inspect(Enum.uniq(duplicate_roots))}"
    end

    Enum.each(classification_roots, fn root ->
      validate_root!(root)
    end)
  end

  defp validate_forbidden_dependencies!(forbidden, boundaries) do
    boundary_names = boundaries |> Map.keys() |> MapSet.new()

    Enum.each(forbidden, &validate_forbidden_rule!(&1, boundary_names))
  end

  defp validate_bounded_contexts!(bounded_contexts, boundaries) do
    if bounded_contexts == [] do
      raise ArgumentError, "architecture policy must declare at least one bounded context"
    end

    duplicate_contexts = bounded_contexts -- Enum.uniq(bounded_contexts)

    if duplicate_contexts != [] do
      raise ArgumentError,
            "bounded contexts must be unique: #{inspect(Enum.uniq(duplicate_contexts))}"
    end

    boundary_names = boundaries |> Map.keys() |> MapSet.new()
    required_supporting_boundaries = [@infrastructure_boundary, @web_infrastructure_boundary, @presentation_boundary]

    missing_supporting_boundaries =
      Enum.reject(required_supporting_boundaries, &MapSet.member?(boundary_names, &1))

    if missing_supporting_boundaries != [] do
      raise ArgumentError,
            "architecture policy is missing required supporting boundaries: " <>
              inspect(missing_supporting_boundaries)
    end

    Enum.each(bounded_contexts, fn context ->
      if not is_atom(context) or not MapSet.member?(boundary_names, context) do
        raise ArgumentError, "unknown bounded context: #{inspect(context)}"
      end
    end)
  end

  defp validate_protected_dependency_matrix!(bounded_contexts, forbidden) do
    expected_sources =
      bounded_contexts
      |> Kernel.++([@infrastructure_boundary, @web_infrastructure_boundary])
      |> MapSet.new()

    actual_sources = forbidden |> Map.keys() |> MapSet.new()

    validate_exact_set!(
      actual_sources,
      expected_sources,
      "protected dependency sources"
    )

    Enum.each(bounded_contexts, fn context ->
      expected_targets =
        bounded_contexts
        |> List.delete(context)
        |> Kernel.++([@infrastructure_boundary, @presentation_boundary])

      validate_exact_targets!(context, Map.fetch!(forbidden, context), expected_targets)
    end)

    validate_exact_targets!(
      @infrastructure_boundary,
      Map.fetch!(forbidden, @infrastructure_boundary),
      bounded_contexts ++ [@presentation_boundary]
    )

    validate_exact_targets!(
      @web_infrastructure_boundary,
      Map.fetch!(forbidden, @web_infrastructure_boundary),
      bounded_contexts
    )
  end

  defp validate_exact_targets!(source, actual_targets, expected_targets) do
    duplicate_targets = actual_targets -- Enum.uniq(actual_targets)

    if duplicate_targets != [] do
      raise ArgumentError,
            "forbidden targets for #{inspect(source)} must be unique: " <>
              inspect(Enum.uniq(duplicate_targets))
    end

    validate_exact_set!(
      MapSet.new(actual_targets),
      MapSet.new(expected_targets),
      "forbidden targets for #{inspect(source)}"
    )
  end

  defp validate_exact_set!(actual, expected, label) do
    missing = expected |> MapSet.difference(actual) |> Enum.sort()
    unexpected = actual |> MapSet.difference(expected) |> Enum.sort()

    if missing != [] or unexpected != [] do
      raise ArgumentError,
            "#{label} must match the architecture policy; " <>
              "missing: #{inspect(missing)}, unexpected: #{inspect(unexpected)}"
    end
  end

  defp validate_globally_allowed_technical_targets!(targets, boundaries, bounded_contexts) do
    Enum.each(targets, fn target ->
      validate_root!(target)
      target_boundary = boundary_for(target, boundaries)

      cond do
        String.ends_with?(target, "/") ->
          raise ArgumentError,
                "globally allowed technical targets must name one exact file: #{target}"

        is_nil(target_boundary) ->
          raise ArgumentError, "globally allowed technical target is not classified: #{target}"

        target_boundary in bounded_contexts ->
          raise ArgumentError,
                "globally allowed technical target belongs to bounded context " <>
                  "#{inspect(target_boundary)}: #{target}"

        true ->
          :ok
      end
    end)
  end

  defp validate_additional_durable_contract_targets!(contracts, boundaries, bounded_contexts) do
    Enum.each(contracts, fn
      %{target: target, reason: reason} when is_binary(target) and is_binary(reason) and reason != "" ->
        validate_root!(target)
        target_boundary = boundary_for(target, boundaries)

        cond do
          String.ends_with?(target, "/") ->
            raise ArgumentError, "additional durable contract target must name one exact file: #{target}"

          is_nil(target_boundary) ->
            raise ArgumentError, "additional durable contract target is not classified: #{target}"

          target_boundary in bounded_contexts ->
            raise ArgumentError,
                  "additional durable contract target belongs to bounded context " <>
                    "#{inspect(target_boundary)}: #{target}"

          true ->
            :ok
        end

      invalid ->
        raise ArgumentError, "invalid additional durable contract target: #{inspect(invalid)}"
    end)

    targets = Enum.map(contracts, & &1.target)
    duplicates = targets -- Enum.uniq(targets)

    if duplicates != [] do
      raise ArgumentError,
            "additional durable contract targets must be unique: #{inspect(Enum.uniq(duplicates))}"
    end
  end

  defp validate_path_denials!(denials) when is_list(denials) do
    Enum.each(denials, fn
      %{source_root: source_root, target_root: target_root, kinds: kinds, reason: reason}
      when is_binary(reason) and reason != "" and is_list(kinds) and kinds != [] ->
        validate_root!(source_root)
        validate_root!(target_root)
        Enum.each(kinds, &validate_kind!/1)

      denial ->
        raise ArgumentError, "invalid path denial: #{inspect(denial)}"
    end)

    duplicates =
      denials
      |> Enum.map(&{&1.source_root, &1.target_root, Enum.sort(&1.kinds)})
      |> then(&(&1 -- Enum.uniq(&1)))

    if duplicates != [] do
      raise ArgumentError, "path denials must be unique: #{inspect(Enum.uniq(duplicates))}"
    end
  end

  defp validate_path_denials!(denials) do
    raise ArgumentError, "path_denials must be a list, got: #{inspect(denials)}"
  end

  defp validate_directional_allowances!(allowances, boundaries) when is_list(allowances) do
    Enum.each(allowances, &validate_directional_allowance!(&1, boundaries))
  end

  defp validate_directional_allowances!(allowances, _boundaries) do
    raise ArgumentError, "directional_allowances must be a list, got: #{inspect(allowances)}"
  end

  defp validate_directional_allowance!(
         %{source_root: source_root, target: target, kinds: kinds, reason: reason},
         boundaries
       )
       when is_binary(source_root) and is_binary(target) and is_list(kinds) and kinds != [] and is_binary(reason) and
              reason != "" do
    validate_root!(source_root)
    validate_root!(target)
    Enum.each(kinds, &validate_kind!/1)

    if not String.ends_with?(source_root, "/") do
      raise ArgumentError, "directional allowance source_root must end in /: #{source_root}"
    end

    if not String.starts_with?(source_root, "lib/storyarn_web/") do
      raise ArgumentError,
            "directional allowance source_root must stay inside StoryarnWeb: #{source_root}"
    end

    if boundary_for(target, boundaries) != @presentation_boundary do
      raise ArgumentError,
            "directional allowance target must belong to presentation adapters: #{target}"
    end
  end

  defp validate_directional_allowance!(allowance, _boundaries) do
    raise ArgumentError, "invalid directional allowance: #{inspect(allowance)}"
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

  defp validate_zero_debt_consumers!(consumers, forbidden) do
    duplicate_consumers = consumers -- Enum.uniq(consumers)

    if duplicate_consumers != [] do
      raise ArgumentError,
            "zero-debt architecture consumers must be unique: #{inspect(Enum.uniq(duplicate_consumers))}"
    end

    Enum.each(consumers, fn
      consumer when is_atom(consumer) ->
        if !Map.has_key?(forbidden, consumer) do
          raise ArgumentError, "zero-debt architecture consumer is not protected: #{inspect(consumer)}"
        end

      invalid ->
        raise ArgumentError, "invalid zero-debt architecture consumer: #{inspect(invalid)}"
    end)
  end

  defp validate_isolated_contexts!(contexts, bounded_contexts, zero_debt_consumers) do
    duplicate_contexts = contexts -- Enum.uniq(contexts)

    if duplicate_contexts != [] do
      raise ArgumentError,
            "isolated contexts must be unique: #{inspect(Enum.uniq(duplicate_contexts))}"
    end

    Enum.each(contexts, fn context ->
      cond do
        context not in bounded_contexts ->
          raise ArgumentError, "isolated context is not a bounded context: #{inspect(context)}"

        context not in zero_debt_consumers ->
          raise ArgumentError,
                "isolated context must also be a zero-debt consumer: #{inspect(context)}"

        true ->
          :ok
      end
    end)
  end

  defp validate_reviewed_edges!(policy) do
    Enum.each(policy.durable_contracts, fn contract ->
      validate_reviewed_edge!(contract, policy.boundaries)

      if not durable_contract_target?(contract.target, policy) do
        raise ArgumentError,
              "durable contract target must be a bounded-context root facade, a globally allowed " <>
                "technical target, or an additional durable contract target: #{contract.target}"
      end
    end)

    Enum.each(policy.migration_exceptions, fn exception ->
      validate_reviewed_edge!(exception, policy.boundaries)

      if durable_contract_target?(exception.target, policy) do
        raise ArgumentError,
              "migration exception points to a durable contract target; move it to durable_contracts: " <>
                "#{exception.source} -> #{exception.target}"
      end
    end)

    durable_keys = reviewed_edge_keys(policy.durable_contracts)
    migration_keys = reviewed_edge_keys(policy.migration_exceptions)

    validate_unique_reviewed_edges!(durable_keys, "durable contracts")
    validate_unique_reviewed_edges!(migration_keys, "migration exceptions")

    overlaps =
      durable_keys
      |> MapSet.new()
      |> MapSet.intersection(MapSet.new(migration_keys))
      |> Enum.sort()

    if overlaps != [] do
      raise ArgumentError,
            "reviewed dependency edges cannot be both durable contracts and migration exceptions: " <>
              inspect(overlaps)
    end
  end

  defp durable_contract_target?(target, policy) do
    target in root_facade_targets(policy) or target in policy.globally_allowed_technical_targets or
      target in Enum.map(policy.additional_durable_contract_targets, & &1.target)
  end

  defp root_facade_targets(policy) do
    Enum.map(policy.bounded_contexts, &"lib/storyarn/#{&1}.ex")
  end

  defp reviewed_edge_keys(edges) do
    Enum.flat_map(edges, fn edge ->
      Enum.map(edge.kinds, &{edge.source, edge.target, &1})
    end)
  end

  defp validate_unique_reviewed_edges!(keys, label) do
    duplicates = keys -- Enum.uniq(keys)

    if duplicates != [] do
      raise ArgumentError, "#{label} must be unique: #{inspect(Enum.uniq(duplicates))}"
    end
  end

  defp validate_reviewed_edge!(%{source: source, target: target, kinds: kinds, reason: reason}, boundaries)
       when is_binary(source) and is_binary(target) and is_list(kinds) and kinds != [] and is_binary(reason) and
              reason != "" do
    source = normalize_path!(source)
    target = normalize_path!(target)
    source_boundary = boundary_for(source, boundaries)
    target_boundary = boundary_for(target, boundaries)

    if is_nil(source_boundary) or is_nil(target_boundary) do
      raise ArgumentError, "reviewed architecture edges must connect two classified paths"
    end

    if source_boundary == target_boundary do
      raise ArgumentError,
            "reviewed architecture edges must cross a boundary, got #{inspect(source_boundary)}: " <>
              "#{source} -> #{target}"
    end

    Enum.each(kinds, &validate_kind!/1)
  end

  defp validate_reviewed_edge!(invalid, _boundaries) do
    raise ArgumentError, "invalid reviewed architecture edge: #{inspect(invalid)}"
  end

  defp graph_edges(graph) do
    Enum.reduce(graph, MapSet.new(), fn {source, dependencies}, edges ->
      source = normalize_path!(source)

      Enum.reduce(dependencies, edges, fn {target, kind}, source_edges ->
        MapSet.put(source_edges, {source, normalize_path!(target), validate_kind!(kind)})
      end)
    end)
  end

  defp stale_policy_edges(policy_edges, actual_edges) do
    policy_edges
    |> reviewed_edge_keys()
    |> Enum.reject(&MapSet.member?(actual_edges, &1))
    |> Enum.sort()
  end

  defp count_policy_edges(policy_edges) do
    Enum.reduce(policy_edges, 0, &(length(&1.kinds) + &2))
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
