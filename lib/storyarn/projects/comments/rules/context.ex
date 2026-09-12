defmodule Storyarn.Projects.Comments.Context do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Platform.Shared.HtmlUtils
  alias Storyarn.Projects.Comments.DTO
  alias Storyarn.Projects.Comments.Payload
  alias Storyarn.Projects.Comments.Projections.FlowNodeRecord
  alias Storyarn.Projects.Comments.Projections.SceneAnnotationRecord
  alias Storyarn.Projects.Comments.Projections.SceneConnectionRecord
  alias Storyarn.Projects.Comments.Projections.ScenePinRecord
  alias Storyarn.Projects.Comments.Projections.SceneZoneRecord
  alias Storyarn.Projects.Comments.Projections.SheetBlockRecord
  alias Storyarn.Projects.Comments.Projections.SheetRecord
  alias Storyarn.Projects.Comments.Thread
  alias Storyarn.Repo

  @fixed_types ~w(sheet_cover sheet_header sheet_title)
  @targets %{
    "flow_node" => {FlowNodeRecord, :flow_id, :flow_node_id, "flow_canvas"},
    "sheet_block" => {SheetBlockRecord, :sheet_id, :context_sheet_block_id, "sheet_canvas"},
    "scene_pin" => {ScenePinRecord, :scene_id, :context_scene_pin_id, "scene_canvas"},
    "scene_zone" => {SceneZoneRecord, :scene_id, :context_scene_zone_id, "scene_canvas"},
    "scene_connection" => {SceneConnectionRecord, :scene_id, :context_scene_connection_id, "scene_canvas"},
    "scene_annotation" => {SceneAnnotationRecord, :scene_id, :context_scene_annotation_id, "scene_canvas"}
  }
  @types Map.keys(@targets) ++ @fixed_types ++ ["sheet_column_group"]
  @empty %{
    context_type: nil,
    context_id: nil,
    context_label: nil,
    context_inserted_at: nil,
    context_offset_x: nil,
    context_offset_y: nil,
    flow_node_id: nil,
    context_sheet_block_id: nil,
    context_sheet_column_group_id: nil,
    context_scene_pin_id: nil,
    context_scene_zone_id: nil,
    context_scene_connection_id: nil,
    context_scene_annotation_id: nil
  }

  def normalize(nil), do: {:ok, nil}

  def normalize(input) when is_map(input) do
    type = normalize_type(Payload.value(input, :type))

    with true <- type in @types,
         {:ok, id} <- normalize_id(type, Payload.value(input, :id)),
         {:ok, offset} <- Payload.position(Payload.value(input, :offset)) do
      {:ok, %{type: type, id: id, offset: offset}}
    else
      _ -> {:error, :invalid_context}
    end
  end

  def normalize(_input), do: {:error, :invalid_context}

  def attributes(thread, context, opts \\ [])
  def attributes(_thread, nil, _opts), do: {:ok, @empty}

  def attributes(thread, %{type: type, id: id} = context, opts) do
    case find_target(thread, type, id, opts) do
      nil ->
        {:error, :context_unavailable}

      target ->
        offset = Map.get(context, :offset)

        attrs =
          Map.merge(@empty, %{
            context_type: type,
            context_id: id,
            context_label: label(type, target),
            context_inserted_at: target.inserted_at,
            context_offset_x: offset && offset.x,
            context_offset_y: offset && offset.y
          })

        {:ok, put_pointer(attrs, type, target.id)}
    end
  end

  def attributes(_thread, _context, _opts), do: {:error, :invalid_context}

  # The caller authorizes and validates the owning surface before resolving context.
  def available(thread, opts \\ [])
  def available(%{context_type: nil}, _opts), do: nil

  def available(thread, opts) do
    if pointer_available?(thread) do
      target = find_target(thread, thread.context_type, thread.context_id, opts)
      if matching_identity?(thread, target), do: target
    end
  end

  def available_many(threads) do
    threads
    |> Enum.reject(&is_nil(&1.context_type))
    |> Enum.group_by(& &1.context_type)
    |> Enum.reduce(%{}, fn {type, grouped}, result ->
      Map.merge(result, resolve_group(type, grouped))
    end)
  end

  # Search the current contextual labels with the same pointer/owner/identity
  # guards used by the DTO resolver; renamed or replaced targets cannot match a
  # stale captured label. All values stay inside a database-filtered subquery.
  def matching_threads(text) do
    targets =
      Enum.map(@targets, fn {type, {schema, owner_key, pointer, surface}} ->
        label = search_label(type)
        matches = dynamic(fragment("strpos(lower(?), lower(?)) > 0", ^label, ^text))

        active_search_target(
          from(t in Thread,
            as: :thread,
            join: target in ^schema,
            as: :target,
            on:
              field(t, ^pointer) == target.id and field(target, ^owner_key) == t.container_id and
                t.context_id == fragment("CAST(? AS text)", target.id) and t.context_inserted_at == target.inserted_at,
            where: t.source_type == ^surface and t.context_type == ^type,
            where: ^matches,
            select: t.id
          ),
          type
        )
      end)

    Enum.reduce([fixed_context_matches(text), column_group_matches(text) | targets], &union_all(&2, ^&1))
  end

  defp search_label("flow_node"),
    do:
      dynamic(
        [target: n],
        fragment(
          "COALESCE(?->>'name', ?->>'text', ?->>'label', initcap(?) || ' #' || CAST(? AS text))",
          n.data,
          n.data,
          n.data,
          n.type,
          n.id
        )
      )

  defp search_label("sheet_block") do
    value = dynamic([target: b], fragment("COALESCE(?->>'label', ?)", b.config, b.variable_name))
    searchable_label(value, "Block")
  end

  defp search_label("scene_zone"), do: searchable_label(dynamic([target: t], t.name), "Zone")
  defp search_label("scene_annotation"), do: searchable_label(dynamic([target: t], t.text), "Annotation")
  defp search_label("scene_pin"), do: searchable_label(dynamic([target: t], t.label), "Pin")
  defp search_label("scene_connection"), do: searchable_label(dynamic([target: t], t.label), "Connection")

  defp searchable_label(value, fallback) do
    dynamic(
      [target: target],
      fragment(
        "COALESCE(NULLIF(btrim(regexp_replace(?, '<[^>]*>', '', 'g')), ''), ? || ' #' || CAST(? AS text))",
        ^value,
        ^fallback,
        target.id
      )
    )
  end

  defp active_search_target(query, type) when type in ~w(flow_node sheet_block),
    do: where(query, [target: target], is_nil(target.deleted_at))

  defp active_search_target(query, _), do: query

  defp fixed_context_matches(text) do
    from(t in Thread,
      join: sheet in SheetRecord,
      on: sheet.id == t.sheet_canvas_id and sheet.id == t.container_id and sheet.project_id == t.project_id,
      where: is_nil(sheet.deleted_at) and t.source_type == "sheet_canvas" and t.context_type in ^@fixed_types,
      where: t.context_id == fragment("CAST(? AS text)", sheet.id) and t.context_inserted_at == sheet.inserted_at,
      where:
        fragment(
          "strpos(lower(CASE ? WHEN 'sheet_cover' THEN 'Cover' WHEN 'sheet_header' THEN 'Header' ELSE 'Title' END), lower(?)) > 0",
          t.context_type,
          ^text
        ),
      select: t.id
    )
  end

  defp column_group_matches(text) do
    from(t in Thread,
      join: block in SheetBlockRecord,
      on: block.sheet_id == t.container_id and block.column_group_id == t.context_sheet_column_group_id,
      where: t.source_type == "sheet_canvas" and t.context_type == "sheet_column_group" and is_nil(block.deleted_at),
      where: t.sheet_canvas_id == t.container_id,
      where: t.context_id == fragment("CAST(? AS text)", block.column_group_id),
      group_by: t.id,
      having: count(block.id) >= 2,
      having:
        fragment("strpos(lower('Row of ' || CAST(? AS text) || ' blocks'), lower(?)) > 0", count(block.id), ^text),
      select: t.id
    )
  end

  defp resolve_group(type, threads) do
    targets = batch_targets(type, threads)

    Map.new(threads, fn thread ->
      target = Map.get(targets, {thread.container_id, thread.context_id})
      available = if pointer_available?(thread) and matching_identity?(thread, target), do: target
      {thread.id, available}
    end)
  end

  def to_dto(thread), do: to_dto(thread, available(thread))
  def to_dto(%{context_type: nil}, _target), do: nil

  def to_dto(thread, target) do
    %{
      type: thread.context_type,
      id: thread.context_id,
      label: if(target, do: label(thread.context_type, target), else: thread.context_label),
      status: if(target, do: "available", else: "unavailable"),
      offset: offset(thread)
    }
  end

  defp normalize_type(type) when is_atom(type), do: Atom.to_string(type)
  defp normalize_type(type), do: type

  defp normalize_id("sheet_column_group", id) when is_binary(id), do: Ecto.UUID.cast(id)
  defp normalize_id("sheet_column_group", _id), do: :error

  defp normalize_id(_type, id) when is_integer(id) do
    if Payload.valid_id?(id), do: {:ok, Integer.to_string(id)}, else: :error
  end

  defp normalize_id(type, id) when is_binary(id) and byte_size(id) <= 19 do
    case Integer.parse(id) do
      {number, ""} when number > 0 -> normalize_id(type, number)
      _ -> :error
    end
  end

  defp normalize_id(_type, _id), do: :error

  defp find_target(%{source_type: "sheet_canvas"} = thread, type, id, opts) when type in @fixed_types do
    if id == to_string(thread.container_id) do
      SheetRecord
      |> where([sheet], sheet.id == ^thread.container_id and sheet.project_id == ^thread.project_id)
      |> where([sheet], is_nil(sheet.deleted_at))
      |> maybe_lock(opts)
      |> Repo.one()
    end
  end

  defp find_target(%{source_type: "sheet_canvas"} = thread, "sheet_column_group", id, opts) do
    lock_group(thread.container_id, id, opts)

    SheetBlockRecord
    |> where([block], block.sheet_id == ^thread.container_id and block.column_group_id == ^id)
    |> where([block], is_nil(block.deleted_at))
    |> Repo.all()
    |> group_target()
  end

  defp find_target(thread, type, id, opts) do
    case @targets[type] do
      {schema, owner_key, _pointer, surface} when surface == thread.source_type ->
        schema
        |> where([target], target.id == ^String.to_integer(id) and field(target, ^owner_key) == ^thread.container_id)
        |> active_entities(type)
        |> maybe_lock(opts)
        |> Repo.one()

      _ ->
        nil
    end
  end

  defp batch_targets(type, threads) when type in @fixed_types do
    ids = Enum.map(threads, & &1.container_id)

    from(sheet in SheetRecord, where: sheet.id in ^ids and is_nil(sheet.deleted_at))
    |> Repo.all()
    |> Map.new(&{{&1.id, to_string(&1.id)}, &1})
  end

  defp batch_targets("sheet_column_group", threads) do
    ids = threads |> Enum.map(& &1.context_sheet_column_group_id) |> Enum.reject(&is_nil/1)
    owners = Enum.map(threads, & &1.container_id)

    from(block in SheetBlockRecord,
      where: block.column_group_id in ^ids and block.sheet_id in ^owners and is_nil(block.deleted_at)
    )
    |> Repo.all()
    |> Enum.group_by(&{&1.sheet_id, &1.column_group_id})
    |> Map.new(fn {key, blocks} -> {key, group_target(blocks)} end)
  end

  defp batch_targets(type, threads) do
    case @targets[type] do
      {schema, owner_key, pointer, _surface} ->
        ids = threads |> Enum.map(&Map.get(&1, pointer)) |> Enum.reject(&is_nil/1)

        schema
        |> where([target], target.id in ^ids)
        |> active_entities(type)
        |> Repo.all()
        |> Map.new(&{{Map.fetch!(&1, owner_key), to_string(&1.id)}, &1})

      _ ->
        %{}
    end
  end

  defp active_entities(query, type) when type in ~w(flow_node sheet_block),
    do: where(query, [target], is_nil(target.deleted_at))

  defp active_entities(query, _type), do: query

  defp group_target([first, _second | _] = blocks) do
    %{id: first.column_group_id, sheet_id: first.sheet_id, inserted_at: nil, name: "Row of #{length(blocks)} blocks"}
  end

  defp group_target(_blocks), do: nil

  defp pointer_available?(%{context_type: type} = thread) when type in @fixed_types,
    do:
      thread.source_type == "sheet_canvas" and thread.sheet_canvas_id == thread.container_id and
        thread.context_id == to_string(thread.container_id)

  defp pointer_available?(%{context_type: "sheet_column_group"} = thread),
    do:
      thread.source_type == "sheet_canvas" and thread.sheet_canvas_id == thread.container_id and
        thread.context_sheet_column_group_id == thread.context_id

  defp pointer_available?(thread) do
    case @targets[thread.context_type] do
      {_schema, _owner, pointer, surface} ->
        value = Map.get(thread, pointer)
        surface == thread.source_type and not is_nil(value) and to_string(value) == thread.context_id

      _ ->
        false
    end
  end

  defp matching_identity?(_thread, nil), do: false
  defp matching_identity?(%{context_type: "sheet_column_group"}, _target), do: true
  defp matching_identity?(thread, target), do: thread.context_inserted_at == target.inserted_at

  defp put_pointer(attrs, type, _id) when type in @fixed_types, do: attrs
  defp put_pointer(attrs, "sheet_column_group", id), do: Map.put(attrs, :context_sheet_column_group_id, id)
  defp put_pointer(attrs, type, id), do: Map.put(attrs, elem(Map.fetch!(@targets, type), 2), id)

  defp label("flow_node", target), do: DTO.source_label(target)
  defp label("sheet_cover", _target), do: "Cover"
  defp label("sheet_header", _target), do: "Header"
  defp label("sheet_title", _target), do: "Title"
  defp label("sheet_column_group", target), do: target.name

  defp label("sheet_block", target),
    do: clean_label(Map.get(target.config || %{}, "label") || target.variable_name, "Block", target.id)

  defp label("scene_zone", target), do: clean_label(target.name, "Zone", target.id)
  defp label("scene_annotation", target), do: clean_label(target.text, "Annotation", target.id)
  defp label("scene_pin", target), do: clean_label(target.label, "Pin", target.id)
  defp label("scene_connection", target), do: clean_label(target.label, "Connection", target.id)

  defp clean_label(value, fallback, id) when is_binary(value) do
    case HtmlUtils.strip_and_truncate(value, 120) do
      "" -> "#{fallback} ##{id}"
      label -> label
    end
  end

  defp clean_label(_value, fallback, id), do: "#{fallback} ##{id}"
  defp offset(%{context_offset_x: nil}), do: nil
  defp offset(thread), do: %{x: thread.context_offset_x, y: thread.context_offset_y}

  defp lock_group(sheet_id, group_id, opts) do
    if opts[:lock] && Repo.in_transaction?() do
      key = "comment_sheet_column_group:#{sheet_id}:#{group_id}"
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key])
    end
  end

  defp maybe_lock(query, opts) do
    case opts[:lock] do
      :share -> lock(query, "FOR SHARE")
      :update -> lock(query, "FOR UPDATE")
      _ -> query
    end
  end
end
