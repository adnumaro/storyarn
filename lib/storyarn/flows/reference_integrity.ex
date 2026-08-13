defmodule Storyarn.Flows.ReferenceIntegrity do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Assets.Asset
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.NodeConnectionRules
  alias Storyarn.Flows.NodeCreate
  alias Storyarn.References.AvatarIntegrity
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.References.RichTextMentions
  alias Storyarn.Repo

  @project_lock_modes [:key_share, :share, :update]

  @doc """
  Locks a project, an active flow and an active node in a stable order.

  The supplied structs are only identity hints. Callers must persist the
  returned rows so a stale or forged struct cannot bypass project/flow scope.
  """
  def lock_active_node_for_write(node, project_lock_mode \\ :update)

  def lock_active_node_for_write(%FlowNode{id: node_id, flow_id: flow_id}, project_lock_mode)
      when is_integer(node_id) and is_integer(flow_id) and project_lock_mode in @project_lock_modes do
    ensure_transaction!()

    with {:ok, project_id} <- flow_project_id(flow_id),
         {:ok, project} <- lock_project(project_id, project_lock_mode),
         {:ok, flow} <- lock_active_flow(flow_id, project_id),
         {:ok, node} <- lock_active_node(node_id, flow_id) do
      {:ok, %{project: project, project_id: project_id, flow: flow, node: node}}
    end
  end

  def lock_active_node_for_write(node_id, project_lock_mode)
      when is_integer(node_id) and project_lock_mode in @project_lock_modes do
    ensure_transaction!()

    case Repo.one(from(node in FlowNode, where: node.id == ^node_id, select: node.flow_id)) do
      nil ->
        {:error, :node_not_found}

      flow_id ->
        lock_active_node_for_write(
          %FlowNode{id: node_id, flow_id: flow_id},
          project_lock_mode
        )
    end
  end

  def lock_active_node_for_write(_node, _project_lock_mode), do: {:error, :node_not_found}

  @doc """
  Locks a project and an active flow in a stable order.

  The struct's `project_id` is part of the identity check, preventing a caller
  from pairing a real flow ID with an unrelated project.
  """
  def lock_active_flow_for_write(flow, project_lock_mode \\ :update)

  def lock_active_flow_for_write(%Flow{id: flow_id, project_id: project_id}, project_lock_mode)
      when is_integer(flow_id) and is_integer(project_id) and project_lock_mode in @project_lock_modes do
    ensure_transaction!()

    with {:ok, project} <- lock_project(project_id, project_lock_mode),
         {:ok, flow} <- lock_active_flow(flow_id, project_id) do
      {:ok, %{project: project, project_id: project_id, flow: flow}}
    end
  end

  def lock_active_flow_for_write(flow_id, project_lock_mode)
      when is_integer(flow_id) and project_lock_mode in @project_lock_modes do
    ensure_transaction!()

    with {:ok, project_id} <- flow_project_id(flow_id),
         {:ok, project} <- lock_project(project_id, project_lock_mode),
         {:ok, flow} <- lock_active_flow(flow_id, project_id) do
      {:ok, %{project: project, project_id: project_id, flow: flow}}
    end
  end

  def lock_active_flow_for_write(_flow, _project_lock_mode), do: {:error, :flow_not_found}

  @doc """
  Validates and locks a node parent.

  A parent must be an active sequence in the same flow. Reparenting a
  sequence below itself or one of its descendants is rejected.
  """
  def lock_node_parent(flow_id, parent_id, source_node_id \\ nil)

  def lock_node_parent(_flow_id, parent_id, _source_node_id) when parent_id in [nil, ""], do: {:ok, nil}

  def lock_node_parent(flow_id, parent_id, source_node_id) when is_integer(flow_id) do
    ensure_transaction!()

    with {:ok, normalized_parent_id} <- normalize_id(parent_id, :parent_id),
         :ok <- reject_self_parent(normalized_parent_id, source_node_id),
         %FlowNode{} = parent <-
           Repo.one(
             from(node in FlowNode,
               where:
                 node.id == ^normalized_parent_id and node.flow_id == ^flow_id and
                   node.type == "sequence" and is_nil(node.deleted_at),
               lock: "FOR SHARE"
             )
           ),
         :ok <- reject_node_parent_cycle(parent, source_node_id) do
      {:ok, parent.id}
    else
      nil -> {:error, {:invalid_node_parent, parent_id}}
      {:error, _reason} = error -> error
    end
  end

  def lock_node_parent(_flow_id, parent_id, _source_node_id), do: {:error, {:invalid_node_parent, parent_id}}

  @doc """
  Normalizes and locks every project-scoped reference stored in node JSON.

  Speaker validation is independent from avatar validation, so removing an
  avatar cannot leave an unchecked speaker ID behind.
  """
  def lock_and_normalize_node_references(project_id, source_flow_id, node_type, data)
      when is_integer(project_id) and is_integer(source_flow_id) and is_map(data) do
    ensure_transaction!()
    data = stringify_keys(data)

    with :ok <- validate_referenced_flow_contract(node_type, data),
         {:ok, exit_target} <- normalize_exit_target(node_type, data),
         {:ok, mention_specs} <- mention_reference_specs(data),
         specs = node_reference_specs(data, exit_target) ++ mention_specs,
         {:ok, normalized_ids} <-
           ProjectReferenceIntegrity.lock_active_references(project_id, specs) do
      normalized_by_context = normalized_ids_by_context(specs, normalized_ids)
      normalized_data = apply_normalized_node_ids(data, normalized_by_context)

      normalized_data =
        apply_normalized_exit_target(
          normalized_data,
          exit_target,
          normalized_by_context[:exit_target_id]
        )

      finish_node_reference_normalization(
        project_id,
        source_flow_id,
        node_type,
        normalized_data
      )
    end
  end

  def lock_and_normalize_node_references(_project_id, _source_flow_id, _node_type, data),
    do: {:error, {:invalid_node_data, data}}

  @doc false
  @spec lock_and_normalize_node_reference_batch(
          integer(),
          [{term(), integer(), String.t(), map()}]
        ) :: {:ok, %{optional(term()) => map()}} | {:error, term()}
  def lock_and_normalize_node_reference_batch(project_id, candidates)
      when is_integer(project_id) and is_list(candidates) do
    ensure_transaction!()

    with {:ok, prepared} <- prepare_node_reference_batch(candidates),
         specs = Enum.flat_map(prepared, & &1.specs),
         {:ok, normalized_ids} <-
           ProjectReferenceIntegrity.lock_active_references(project_id, specs) do
      finish_node_reference_batch(project_id, prepared, normalized_ids)
    end
  end

  def lock_and_normalize_node_reference_batch(_project_id, candidates),
    do: {:error, {:invalid_node_reference_batch, candidates}}

  @doc """
  Validates an active same-project flow parent and prevents hierarchy cycles.
  """
  def lock_flow_parent(project_id, source_flow_id, parent_id) do
    ensure_transaction!()

    with {:ok, [normalized_parent_id]} <-
           ProjectReferenceIntegrity.lock_active_references(project_id, [
             {:flow, :parent_id, parent_id}
           ]),
         :ok <- reject_flow_parent_cycle(source_flow_id, normalized_parent_id) do
      {:ok, normalized_parent_id}
    end
  end

  @doc "Locks an optional active same-project scene reference."
  def lock_flow_scene(project_id, scene_id) do
    ensure_transaction!()

    with {:ok, [normalized_scene_id]} <-
           ProjectReferenceIntegrity.lock_active_references(project_id, [
             {:scene, :scene_id, scene_id}
           ]) do
      {:ok, normalized_scene_id}
    end
  end

  @doc """
  Returns the effective output pins for a locked node.

  Subflow pins are derived from the active exit nodes of the referenced flow,
  not from presentation-only JSON fields added while serializing the canvas.
  The referenced flow and its exits are share-locked so connection validation
  and node reconciliation cannot race an exit mutation.
  """
  @spec lock_effective_output_pins(integer(), FlowNode.t()) ::
          {:ok, [String.t()]} | {:error, term()}
  def lock_effective_output_pins(project_id, %FlowNode{type: "subflow", data: data})
      when is_integer(project_id) and is_map(data) do
    ensure_transaction!()
    referenced_flow_id = data["referenced_flow_id"] || data[:referenced_flow_id]

    if referenced_flow_id in [nil, ""] do
      {:ok, []}
    else
      with {:ok, normalized_flow_id} <-
             normalize_required_reference_id(referenced_flow_id, :referenced_flow_id),
           %Flow{} <-
             Repo.one(
               from(flow in Flow,
                 where:
                   flow.id == ^normalized_flow_id and flow.project_id == ^project_id and
                     is_nil(flow.deleted_at),
                 lock: "FOR SHARE"
               )
             ) do
        exit_ids =
          Repo.all(
            from(node in FlowNode,
              where:
                node.flow_id == ^normalized_flow_id and node.type == "exit" and
                  is_nil(node.deleted_at),
              order_by: [asc: node.id],
              lock: "FOR SHARE",
              select: node.id
            )
          )

        {:ok, Enum.map(exit_ids, &"exit_#{&1}")}
      else
        nil ->
          {:error, {:invalid_project_reference, :referenced_flow_id, referenced_flow_id}}

        {:error, _reason} = error ->
          error
      end
    end
  end

  def lock_effective_output_pins(_project_id, %FlowNode{} = node) do
    ensure_transaction!()
    {:ok, NodeConnectionRules.output_pins(node.type, node.data || %{})}
  end

  defp flow_project_id(flow_id) do
    case Repo.one(from(flow in Flow, where: flow.id == ^flow_id, select: flow.project_id)) do
      nil -> {:error, :flow_not_found}
      project_id -> {:ok, project_id}
    end
  end

  defp lock_project(project_id, project_lock_mode) do
    case ProjectReferenceIntegrity.lock_active_project(
           project_id,
           project_lock_mode
         ) do
      {:ok, project} -> {:ok, project}
      {:error, _reason} -> {:error, :flow_not_found}
    end
  end

  defp lock_active_flow(flow_id, project_id) do
    case Repo.one(
           from(flow in Flow,
             where:
               flow.id == ^flow_id and flow.project_id == ^project_id and
                 is_nil(flow.deleted_at),
             lock: "FOR UPDATE"
           )
         ) do
      nil -> {:error, :flow_not_found}
      flow -> {:ok, flow}
    end
  end

  defp lock_active_node(node_id, flow_id) do
    case Repo.one(
           from(node in FlowNode,
             where:
               node.id == ^node_id and node.flow_id == ^flow_id and
                 is_nil(node.deleted_at),
             lock: "FOR UPDATE"
           )
         ) do
      nil -> {:error, :node_not_found}
      node -> {:ok, node}
    end
  end

  defp node_reference_specs(data, exit_target) do
    [
      {:sheet, :speaker_sheet_id, data["speaker_sheet_id"]},
      {:sheet, :location_sheet_id, data["location_sheet_id"]},
      {:flow, :referenced_flow_id, data["referenced_flow_id"]},
      {:asset, :audio_asset_id, data["audio_asset_id"]}
    ] ++ exit_target_spec(exit_target)
  end

  defp exit_target_spec({type, id}) when type in [:flow, :scene], do: [{type, :exit_target_id, id}]

  defp exit_target_spec(nil), do: []

  defp normalized_ids_by_context(specs, normalized_ids) do
    specs
    |> Enum.zip(normalized_ids)
    |> Map.new(fn {{_type, context, _raw}, normalized_id} ->
      {context, normalized_id}
    end)
  end

  defp apply_normalized_node_ids(data, normalized_by_context) do
    Enum.reduce(
      [:speaker_sheet_id, :location_sheet_id, :referenced_flow_id, :audio_asset_id],
      data,
      fn context, acc ->
        put_if_present(
          acc,
          Atom.to_string(context),
          normalized_by_context[context]
        )
      end
    )
  end

  defp normalize_exit_target("exit", data) do
    mode = data["exit_mode"] || "terminal"
    type = blank_to_nil(data["target_type"])
    id = blank_to_nil(data["target_id"])

    cond do
      is_nil(type) and is_nil(id) ->
        {:ok, nil}

      mode != "terminal" ->
        {:error, {:invalid_exit_target, :exit_mode, mode}}

      type not in ["flow", "scene"] ->
        {:error, {:invalid_exit_target, :target_type, type}}

      is_nil(id) ->
        {:error, {:invalid_exit_target, :target_id, id}}

      true ->
        {:ok, {String.to_existing_atom(type), id}}
    end
  end

  defp normalize_exit_target(_node_type, _data), do: {:ok, nil}

  defp validate_referenced_flow_contract(_node_type, %{"referenced_flow_id" => value}) when value in [nil, ""], do: :ok

  defp validate_referenced_flow_contract("subflow", _data), do: :ok

  defp validate_referenced_flow_contract("exit", %{"exit_mode" => "flow_reference"}), do: :ok

  defp validate_referenced_flow_contract(node_type, data) do
    case data["referenced_flow_id"] do
      value when value in [nil, ""] -> :ok
      value -> {:error, {:invalid_referenced_flow, node_type, value}}
    end
  end

  defp apply_normalized_exit_target(data, nil, _normalized_id) do
    data
    |> put_if_present("target_type", nil)
    |> put_if_present("target_id", nil)
  end

  defp apply_normalized_exit_target(data, {type, _raw_id}, normalized_id) do
    data
    |> Map.put("target_type", Atom.to_string(type))
    |> Map.put("target_id", normalized_id)
  end

  defp prepare_node_reference_batch(candidates) do
    candidates
    |> Enum.reduce_while({:ok, []}, fn
      {key, source_flow_id, node_type, data}, {:ok, prepared}
      when is_integer(source_flow_id) and is_binary(node_type) and is_map(data) ->
        data = stringify_keys(data)

        with :ok <- validate_referenced_flow_contract(node_type, data),
             {:ok, exit_target} <- normalize_exit_target(node_type, data),
             {:ok, mention_specs} <- mention_reference_specs(data) do
          candidate = %{
            key: key,
            source_flow_id: source_flow_id,
            node_type: node_type,
            data: data,
            exit_target: exit_target,
            specs: node_reference_specs(data, exit_target) ++ mention_specs
          }

          {:cont, {:ok, [candidate | prepared]}}
        else
          {:error, _reason} = error -> {:halt, error}
        end

      invalid_candidate, _prepared ->
        {:halt, {:error, {:invalid_node_reference_candidate, invalid_candidate}}}
    end)
    |> case do
      {:ok, prepared} -> {:ok, Enum.reverse(prepared)}
      {:error, _reason} = error -> error
    end
  end

  defp finish_node_reference_batch(project_id, prepared, normalized_ids) do
    with {:ok, normalized_candidates} <-
           apply_normalized_reference_ids(prepared, normalized_ids) do
      audio_asset_ids =
        batch_audio_asset_ids(project_id, normalized_candidates)

      avatar_results =
        AvatarIntegrity.lock_and_normalize_node_avatar_batch_for_project(
          project_id,
          Enum.map(normalized_candidates, & &1.data)
        )

      jump_hub_counts = lock_batch_jump_hub_counts(normalized_candidates)

      circular_reference_pairs =
        normalized_candidates
        |> batch_referenced_flow_pairs()
        |> NodeCreate.circular_reference_pairs()

      semantic_context = %{
        audio_asset_ids: audio_asset_ids,
        jump_hub_counts: jump_hub_counts,
        circular_reference_pairs: circular_reference_pairs
      }

      finish_batch_candidates(
        normalized_candidates,
        avatar_results,
        semantic_context
      )
    end
  end

  defp finish_batch_candidates(candidates, avatar_results, semantic_context) do
    candidates
    |> Enum.zip(avatar_results)
    |> Enum.reduce_while({:ok, %{}}, fn candidate_and_avatar, acc ->
      reduce_batch_candidate(candidate_and_avatar, acc, semantic_context)
    end)
  end

  defp reduce_batch_candidate({candidate, avatar_result}, {:ok, normalized}, semantic_context) do
    case finish_batch_node_reference_normalization(
           candidate,
           avatar_result,
           semantic_context.audio_asset_ids,
           semantic_context.jump_hub_counts,
           semantic_context.circular_reference_pairs
         ) do
      {:ok, normalized_data} ->
        {:cont, {:ok, Map.put(normalized, candidate.key, normalized_data)}}

      {:error, _reason} = error ->
        {:halt, error}

      :error ->
        {:halt, :error}
    end
  end

  defp apply_normalized_reference_ids(prepared, normalized_ids) do
    prepared
    |> Enum.reduce_while({:ok, [], normalized_ids}, fn candidate, {:ok, normalized, remaining_ids} ->
      {candidate_ids, remaining_ids} = Enum.split(remaining_ids, length(candidate.specs))
      normalized_by_context = normalized_ids_by_context(candidate.specs, candidate_ids)

      normalized_data =
        candidate.data
        |> apply_normalized_node_ids(normalized_by_context)
        |> apply_normalized_exit_target(
          candidate.exit_target,
          normalized_by_context[:exit_target_id]
        )

      {:cont, {:ok, [%{candidate | data: normalized_data} | normalized], remaining_ids}}
    end)
    |> case do
      {:ok, normalized, []} -> {:ok, Enum.reverse(normalized)}
      {:ok, _normalized, remaining_ids} -> {:error, {:unexpected_normalized_reference_ids, remaining_ids}}
      {:error, _reason} = error -> error
    end
  end

  defp finish_batch_node_reference_normalization(
         candidate,
         avatar_result,
         audio_asset_ids,
         jump_hub_counts,
         circular_reference_pairs
       ) do
    with :ok <-
           validate_batch_audio_asset(
             candidate.data["audio_asset_id"],
             audio_asset_ids
           ),
         {:ok, normalized_data} <- avatar_result,
         {:ok, normalized_data} <-
           normalize_batch_jump_target(
             candidate.source_flow_id,
             candidate.node_type,
             normalized_data,
             jump_hub_counts
           ),
         :ok <-
           validate_batch_referenced_flow_cycle(
             candidate.source_flow_id,
             normalized_data["referenced_flow_id"],
             circular_reference_pairs
           ) do
      {:ok, normalized_data}
    end
  end

  defp batch_audio_asset_ids(project_id, candidates) do
    audio_asset_ids =
      candidates
      |> Enum.map(& &1.data["audio_asset_id"])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    if audio_asset_ids == [] do
      MapSet.new()
    else
      from(asset in Asset,
        where:
          asset.id in ^audio_asset_ids and asset.project_id == ^project_id and
            is_nil(asset.deleted_at) and
            like(asset.content_type, "audio/%"),
        select: asset.id
      )
      |> Repo.all()
      |> MapSet.new()
    end
  end

  defp validate_batch_audio_asset(nil, _audio_asset_ids), do: :ok

  defp validate_batch_audio_asset(asset_id, audio_asset_ids) do
    if MapSet.member?(audio_asset_ids, asset_id),
      do: :ok,
      else: {:error, {:invalid_audio_asset_reference, asset_id}}
  end

  defp lock_batch_jump_hub_counts(candidates) do
    jump_targets =
      candidates
      |> Enum.flat_map(fn
        %{source_flow_id: flow_id, node_type: "jump", data: %{"target_hub_id" => value}}
        when is_binary(value) ->
          if String.trim(value) == "", do: [], else: [{flow_id, value}]

        _candidate ->
          []
      end)
      |> Enum.uniq()

    flow_ids =
      jump_targets
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()
      |> Enum.sort()

    hub_ids =
      jump_targets
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()
      |> Enum.sort()

    if jump_targets == [] do
      %{}
    else
      from(node in FlowNode,
        where:
          node.flow_id in ^flow_ids and node.type == "hub" and
            is_nil(node.deleted_at) and
            fragment("?->>'hub_id'", node.data) in ^hub_ids,
        order_by: [asc: node.id],
        lock: "FOR SHARE",
        select: {node.flow_id, fragment("?->>'hub_id'", node.data)}
      )
      |> Repo.all()
      |> Enum.frequencies()
    end
  end

  defp normalize_batch_jump_target(flow_id, "jump", data, hub_counts) do
    value = data["target_hub_id"]

    cond do
      value in [nil, ""] ->
        {:ok, data}

      not is_binary(value) ->
        {:error, {:invalid_jump_target, value}}

      String.trim(value) == "" ->
        {:ok, Map.put(data, "target_hub_id", "")}

      Map.get(hub_counts, {flow_id, value}) == 1 ->
        {:ok, data}

      true ->
        {:error, {:invalid_jump_target, value}}
    end
  end

  defp normalize_batch_jump_target(_flow_id, _node_type, data, _hub_counts), do: {:ok, data}

  defp batch_referenced_flow_pairs(candidates) do
    candidates
    |> Enum.flat_map(fn candidate ->
      case candidate.data["referenced_flow_id"] do
        target_flow_id when is_integer(target_flow_id) ->
          [{candidate.source_flow_id, target_flow_id}]

        _absent_reference ->
          []
      end
    end)
    |> Enum.uniq()
  end

  defp validate_batch_referenced_flow_cycle(_source_flow_id, nil, _circular_pairs), do: :ok

  defp validate_batch_referenced_flow_cycle(source_flow_id, source_flow_id, _circular_pairs),
    do: {:error, :self_reference}

  defp validate_batch_referenced_flow_cycle(source_flow_id, target_flow_id, circular_pairs) do
    if MapSet.member?(circular_pairs, {source_flow_id, target_flow_id}),
      do: {:error, :circular_reference},
      else: :ok
  end

  defp finish_node_reference_normalization(project_id, source_flow_id, node_type, normalized_data) do
    with :ok <-
           validate_audio_asset(
             project_id,
             normalized_data["audio_asset_id"]
           ),
         {:ok, normalized_data} <-
           AvatarIntegrity.lock_and_normalize_node_avatar_for_project(
             project_id,
             node_type,
             normalized_data
           ),
         {:ok, normalized_data} <-
           lock_and_normalize_jump_target(
             source_flow_id,
             node_type,
             normalized_data
           ),
         :ok <- validate_referenced_flow_cycle(source_flow_id, normalized_data["referenced_flow_id"]) do
      {:ok, normalized_data}
    end
  end

  defp mention_reference_specs(data) do
    data
    |> RichTextMentions.html_candidates()
    |> Enum.reduce_while({:ok, []}, fn html, {:ok, specs} ->
      case mention_specs_from_html(html) do
        {:ok, html_specs} -> {:cont, {:ok, html_specs ++ specs}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp mention_specs_from_html(html) do
    case RichTextMentions.extract_from_html(html) do
      {:ok, mentions} ->
        {:ok,
         Enum.map(mentions, fn %{type: type, id: id} ->
           reference_type = if(type == "sheet", do: :sheet, else: :flow)
           {reference_type, {:flow_node_mention, type}, id}
         end)}

      {:error, {:invalid_html, reason}} ->
        {:error, {:invalid_flow_node_html, reason}}

      {:error, {:invalid_mention, %{type: type_attributes, id: id_attributes}}} ->
        mention_spec_error(type_attributes, id_attributes)
    end
  end

  defp mention_spec_error([type], [id]), do: invalid_mention_reference(type, id)

  defp mention_spec_error(type_attributes, id_attributes) do
    details = %{type: type_attributes, id: id_attributes}
    {:error, {:invalid_project_reference, {:flow_node_mention, :malformed}, details}}
  end

  defp invalid_mention_reference(type, id) do
    {:error, {:invalid_project_reference, {:flow_node_mention, type}, id}}
  end

  defp lock_and_normalize_jump_target(flow_id, "jump", data) when is_integer(flow_id) and is_map(data) do
    normalize_jump_target(flow_id, data, data["target_hub_id"])
  end

  defp lock_and_normalize_jump_target(_flow_id, _node_type, data), do: {:ok, data}

  defp normalize_jump_target(_flow_id, data, value) when value in [nil, ""], do: {:ok, data}

  defp normalize_jump_target(flow_id, data, value) when is_binary(value) do
    if String.trim(value) == "" do
      {:ok, Map.put(data, "target_hub_id", "")}
    else
      validate_jump_target(flow_id, data, value)
    end
  end

  defp normalize_jump_target(_flow_id, _data, value), do: {:error, {:invalid_jump_target, value}}

  defp validate_jump_target(flow_id, data, value) do
    hubs =
      Repo.all(
        from(node in FlowNode,
          where:
            node.flow_id == ^flow_id and node.type == "hub" and
              is_nil(node.deleted_at) and
              fragment("?->>'hub_id' = ?", node.data, ^value),
          order_by: [asc: node.id],
          lock: "FOR SHARE"
        )
      )

    case hubs do
      [_hub] -> {:ok, data}
      _missing_or_ambiguous -> {:error, {:invalid_jump_target, value}}
    end
  end

  defp validate_audio_asset(_project_id, nil), do: :ok

  defp validate_audio_asset(project_id, asset_id) do
    case Repo.one(
           from(asset in Asset,
             where:
               asset.id == ^asset_id and asset.project_id == ^project_id and
                 is_nil(asset.deleted_at) and
                 like(asset.content_type, "audio/%"),
             select: asset.id
           )
         ) do
      ^asset_id -> :ok
      nil -> {:error, {:invalid_audio_asset_reference, asset_id}}
    end
  end

  defp validate_referenced_flow_cycle(_source_flow_id, nil), do: :ok
  defp validate_referenced_flow_cycle(source_flow_id, source_flow_id), do: {:error, :self_reference}

  defp validate_referenced_flow_cycle(source_flow_id, target_flow_id) do
    if NodeCreate.has_circular_reference?(source_flow_id, target_flow_id),
      do: {:error, :circular_reference},
      else: :ok
  end

  defp reject_self_parent(parent_id, source_node_id) when is_integer(source_node_id) and parent_id == source_node_id,
    do: {:error, :cyclic_parent}

  defp reject_self_parent(_parent_id, _source_node_id), do: :ok

  defp reject_node_parent_cycle(_parent, nil), do: :ok

  defp reject_node_parent_cycle(parent, source_node_id) do
    if node_ancestor?(parent, source_node_id, MapSet.new()),
      do: {:error, :cyclic_parent},
      else: :ok
  end

  defp node_ancestor?(%FlowNode{id: id}, source_node_id, _visited) when id == source_node_id, do: true

  defp node_ancestor?(%FlowNode{parent_id: nil}, _source_node_id, _visited), do: false

  defp node_ancestor?(%FlowNode{parent_id: parent_id, flow_id: flow_id}, source_node_id, visited) do
    if MapSet.member?(visited, parent_id) do
      true
    else
      case Repo.one(
             from(node in FlowNode,
               where:
                 node.id == ^parent_id and node.flow_id == ^flow_id and
                   node.type == "sequence" and is_nil(node.deleted_at),
               lock: "FOR SHARE"
             )
           ) do
        nil -> false
        parent -> node_ancestor?(parent, source_node_id, MapSet.put(visited, parent_id))
      end
    end
  end

  defp reject_flow_parent_cycle(_source_flow_id, nil), do: :ok
  defp reject_flow_parent_cycle(nil, _parent_id), do: :ok
  defp reject_flow_parent_cycle(source_flow_id, source_flow_id), do: {:error, :cyclic_parent}

  defp reject_flow_parent_cycle(source_flow_id, parent_id) do
    if flow_ancestor?(parent_id, source_flow_id, MapSet.new()),
      do: {:error, :cyclic_parent},
      else: :ok
  end

  defp flow_ancestor?(flow_id, source_flow_id, _visited) when flow_id == source_flow_id, do: true

  defp flow_ancestor?(flow_id, source_flow_id, visited) do
    if MapSet.member?(visited, flow_id) do
      true
    else
      case Repo.one(
             from(flow in Flow,
               where: flow.id == ^flow_id and is_nil(flow.deleted_at),
               select: flow.parent_id
             )
           ) do
        nil -> false
        parent_id -> flow_ancestor?(parent_id, source_flow_id, MapSet.put(visited, flow_id))
      end
    end
  end

  defp normalize_id(value, context) do
    case ProjectReferenceIntegrity.normalize_optional_id(value) do
      {:ok, nil} -> {:error, {:invalid_node_parent, value}}
      {:ok, id} -> {:ok, id}
      :error -> {:error, {:invalid_node_parent, context, value}}
    end
  end

  defp normalize_required_reference_id(value, context) do
    case ProjectReferenceIntegrity.normalize_optional_id(value) do
      {:ok, id} when is_integer(id) -> {:ok, id}
      _other -> {:error, {:invalid_project_reference, context, value}}
    end
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp put_if_present(map, key, value) do
    if Map.has_key?(map, key), do: Map.put(map, key, value), else: map
  end

  defp stringify_keys(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
  end

  defp ensure_transaction! do
    if not Repo.in_transaction?() do
      raise ArgumentError, "flow reference integrity checks require an explicit transaction"
    end
  end
end
