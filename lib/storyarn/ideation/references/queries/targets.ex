defmodule Storyarn.Ideation.References.Queries.Targets do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Flows
  alias Storyarn.Localization
  alias Storyarn.Platform.Shared.HtmlUtils
  alias Storyarn.Platform.Shared.SearchHelpers
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Sheets

  @types ~w(sheet flow scene asset localization)
  @max_limit 50
  @max_id 9_223_372_036_854_775_807
  @max_text_bytes 2_000

  def search(scope, project_id, type, query, opts \\ [])

  def search(scope, project_id, type, query, opts) when type in @types and is_binary(query) and is_list(opts) do
    with true <- byte_size(query) <= 500 and Keyword.keyword?(opts),
         {:ok, target_query} <- target_query(scope, project_id, type) do
      pattern = "%#{SearchHelpers.sanitize_like_query(String.trim(query))}%"
      fields = fields(type)

      targets =
        from(target in subquery(target_query),
          where: ilike(target.search_text, ^pattern),
          order_by: [asc: target.name, asc: target.id],
          limit: ^limit(opts[:limit]),
          offset: ^offset(opts[:offset]),
          select: map(target, ^fields)
        )
        |> select_merge([target], %{inserted_at: type(target.inserted_at, :utc_datetime)})
        |> Repo.all()
        |> Enum.map(&describe(type, &1))

      with :ok <- authorize(scope, project_id), do: {:ok, targets}
    else
      _invalid_or_unavailable -> {:error, :not_found}
    end
  end

  def search(_scope, _project_id, _type, _query, _opts), do: {:error, :not_found}

  def get(scope, project_id, type, id) do
    with {:ok, targets} <- get_many(scope, project_id, [{type, id}]),
         %{} = target <- Map.get(targets, {type, id}) do
      {:ok, target}
    else
      _unavailable -> {:error, :not_found}
    end
  end

  def get_many(scope, project_id, targets) when is_list(targets) and length(targets) <= @max_limit do
    with :ok <- authorize(scope, project_id),
         true <- Enum.all?(targets, &valid_target?/1),
         {:ok, rows} <- load_groups(scope, project_id, Enum.group_by(targets, &elem(&1, 0))),
         :ok <- authorize(scope, project_id) do
      {:ok, rows}
    else
      _unavailable -> {:error, :not_found}
    end
  end

  def get_many(_scope, _project_id, _targets), do: {:error, :not_found}

  defp load_groups(scope, project_id, groups) do
    Enum.reduce_while(groups, {:ok, %{}}, fn {type, targets}, {:ok, acc} ->
      case target_query(scope, project_id, type) do
        {:ok, target_query} ->
          ids = targets |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
          rows = load_targets(target_query, type, ids)

          {:cont, {:ok, Map.merge(acc, rows)}}

        {:error, _reason} ->
          {:halt, {:error, :not_found}}
      end
    end)
  end

  defp load_targets(query, type, ids) do
    fields = fields(type)

    from(target in subquery(query),
      where: target.id in ^ids,
      limit: ^@max_limit,
      select: map(target, ^fields)
    )
    |> select_merge([target], %{inserted_at: type(target.inserted_at, :utc_datetime)})
    |> Repo.all()
    |> Map.new(fn row -> {{type, row.id}, describe(type, row)} end)
  end

  defp target_query(scope, project_id, "sheet"), do: Sheets.reference_targets_query(scope, project_id)
  defp target_query(scope, project_id, "flow"), do: Flows.reference_targets_query(scope, project_id)
  defp target_query(scope, project_id, "scene"), do: Scenes.reference_targets_query(scope, project_id)
  defp target_query(scope, project_id, "asset"), do: Projects.reference_targets_query(scope, project_id)
  defp target_query(scope, project_id, "localization"), do: Localization.reference_targets_query(scope, project_id)

  defp fields(type) when type in ~w(sheet flow scene) do
    [:id, :name, :name_digest, :shortcut, :description, :description_digest, :description_bytes, :inserted_at] ++
      editor_fields(type)
  end

  defp fields("asset"), do: [:id, :name, :name_digest, :content_type, :size, :blob_hash, :inserted_at]

  defp fields("localization") do
    [
      :id,
      :name,
      :locale_code,
      :source_type,
      :source_id,
      :source_field,
      :source_text,
      :translated_text,
      :source_digest,
      :translated_digest,
      :source_text_bytes,
      :translated_text_bytes,
      :status,
      :inserted_at
    ]
  end

  defp editor_fields("sheet"), do: [:color]
  defp editor_fields("flow"), do: [:is_main, :scene_id]
  defp editor_fields("scene"), do: [:width, :height]

  defp describe(type, row) do
    context = Map.put(context(type, row), "comparison_scope", "overview_v1")

    comparison =
      Map.take(row, [:name_digest, :description_digest, :source_digest, :translated_digest, :blob_hash])

    %{
      type: type,
      id: row.id,
      name: name(type, row),
      identity: "created:" <> DateTime.to_iso8601(row.inserted_at),
      context: context,
      fingerprint: fingerprint({context, comparison}),
      locator: locator(type, row)
    }
  end

  defp context(type, row) when type in ~w(sheet flow scene) do
    Map.merge(
      %{
        "name" => text(row.name, 240),
        "shortcut" => text(row.shortcut, 240),
        "description" => text(row.description, @max_text_bytes),
        "description_truncated" => row.description_bytes > @max_text_bytes
      },
      editor_metadata(type, row)
    )
  end

  defp context("asset", row) do
    %{
      "filename" => text(row.name, 240),
      "content_type" => text(row.content_type, 120),
      "size" => row.size
    }
  end

  defp context("localization", row) do
    %{
      "locale_code" => text(row.locale_code, 40),
      "source_type" => row.source_type,
      "source_id" => row.source_id,
      "source_field" => text(row.source_field, 120),
      "source_text" => text(row.source_text, @max_text_bytes),
      "translated_text" => text(row.translated_text, @max_text_bytes),
      "source_text_truncated" => row.source_text_bytes > @max_text_bytes,
      "translated_text_truncated" => row.translated_text_bytes > @max_text_bytes,
      "status" => row.status
    }
  end

  defp editor_metadata("sheet", row), do: %{"color" => row.color}
  defp editor_metadata("flow", row), do: %{"is_main" => row.is_main, "scene_id" => row.scene_id}
  defp editor_metadata("scene", row), do: %{"width" => row.width, "height" => row.height}

  defp name("localization", row) do
    text(row.locale_code <> " · " <> (row.name || "Text ##{row.id}"), 240)
  end

  defp name(_type, row), do: text(row.name, 240)

  defp locator("localization", row) do
    %{
      type: "localization",
      id: row.id,
      locale_code: row.locale_code,
      source_type: row.source_type,
      source_id: row.source_id
    }
  end

  defp locator(type, row), do: %{type: type, id: row.id}

  defp text(nil, _max_bytes), do: nil

  defp text(value, max_bytes) do
    value |> HtmlUtils.strip_html() |> String.trim() |> truncate_bytes(max_bytes)
  end

  defp truncate_bytes(value, max_bytes) when byte_size(value) <= max_bytes, do: value
  defp truncate_bytes(value, max_bytes), do: value |> binary_part(0, max_bytes) |> valid_prefix()

  defp valid_prefix(value) do
    if String.valid?(value), do: value, else: value |> binary_part(0, byte_size(value) - 1) |> valid_prefix()
  end

  defp fingerprint(value) do
    value
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp authorize(%{user: %{id: user_id}} = scope, project_id)
       when is_integer(user_id) and user_id > 0 and is_integer(project_id) and project_id in 1..@max_id do
    case Projects.authorize(scope, project_id, :view) do
      {:ok, _project, _membership} -> :ok
      _unavailable -> {:error, :not_found}
    end
  end

  defp authorize(_scope, _project_id), do: {:error, :not_found}

  defp valid_target?({type, id}), do: type in @types and is_integer(id) and id in 1..@max_id
  defp valid_target?(_target), do: false
  defp limit(value) when is_integer(value), do: value |> max(1) |> min(@max_limit)
  defp limit(_value), do: 20
  defp offset(value) when is_integer(value), do: value |> max(0) |> min(1_000)
  defp offset(_value), do: 0
end
