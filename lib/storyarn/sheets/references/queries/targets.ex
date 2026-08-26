defmodule Storyarn.Sheets.References.Queries.Targets do
  @moduledoc """
  Resolves active Sheet and Flow targets in the vocabulary of Sheet references.

  Flow identity is a References-local projection. Sheet lookup enters the
  editor through its capability facade rather than importing editor queries.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.SearchHelpers
  alias Storyarn.Repo
  alias Storyarn.Sheets.Editor
  alias Storyarn.Sheets.References.Data.FlowRecord
  alias Storyarn.Sheets.Sheet

  @spec validate(String.t(), integer(), integer()) ::
          {:ok, Sheet.t() | FlowRecord.t()} | {:error, :not_found | :invalid_type}
  def validate("sheet", target_id, project_id) do
    case Editor.get_sheet(project_id, target_id) do
      nil -> {:error, :not_found}
      sheet -> {:ok, sheet}
    end
  end

  def validate("flow", target_id, project_id) do
    case get_flow(project_id, target_id) do
      nil -> {:error, :not_found}
      flow -> {:ok, flow}
    end
  end

  def validate(_target_type, _target_id, _project_id), do: {:error, :invalid_type}

  @spec search(integer(), String.t(), [String.t()]) :: [map()]
  def search(project_id, query, allowed_types \\ ["sheet", "flow"]) do
    query = String.trim(query)

    results =
      if "sheet" in allowed_types do
        project_id
        |> Editor.search_sheets(query)
        |> Enum.map(fn sheet ->
          %{type: "sheet", id: sheet.id, name: sheet.name, shortcut: sheet.shortcut}
        end)
      else
        []
      end

    results =
      if "flow" in allowed_types do
        flow_results =
          project_id
          |> search_flows(query)
          |> Enum.map(fn flow ->
            %{type: "flow", id: flow.id, name: flow.name, shortcut: flow.shortcut}
          end)

        results ++ flow_results
      else
        results
      end

    results
    |> Enum.sort_by(& &1.name)
    |> Enum.take(20)
  end

  @spec get(String.t() | nil, integer() | nil, integer()) :: map() | nil
  def get(nil, _target_id, _project_id), do: nil
  def get(_target_type, nil, _project_id), do: nil

  def get("sheet", target_id, project_id) do
    case Editor.get_sheet(project_id, target_id) do
      nil -> nil
      sheet -> %{type: "sheet", id: sheet.id, name: sheet.name, shortcut: sheet.shortcut}
    end
  end

  def get("flow", target_id, project_id) do
    case get_flow(project_id, target_id) do
      nil -> nil
      flow -> %{type: "flow", id: flow.id, name: flow.name, shortcut: flow.shortcut}
    end
  end

  def get(_target_type, _target_id, _project_id), do: nil

  @doc false
  @spec search_flows(integer(), String.t(), keyword()) :: [FlowRecord.t()]
  def search_flows(project_id, query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 25)
    offset = Keyword.get(opts, :offset, 0)
    query = String.trim(query)

    base =
      from(flow in FlowRecord,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at)
      )

    if query == "" do
      Repo.all(
        from(flow in base,
          order_by: [desc: flow.updated_at],
          limit: ^limit,
          offset: ^offset
        ),
        log: false
      )
    else
      search_term = "%#{SearchHelpers.sanitize_like_query(query)}%"

      Repo.all(
        from(flow in base,
          where: ilike(flow.name, ^search_term) or ilike(flow.shortcut, ^search_term),
          order_by: [asc: flow.name],
          limit: ^limit,
          offset: ^offset
        ),
        log: false
      )
    end
  end

  @doc false
  @spec get_flow(integer(), integer()) :: FlowRecord.t() | nil
  def get_flow(project_id, flow_id) do
    Repo.one(
      from(flow in FlowRecord,
        where:
          flow.project_id == ^project_id and flow.id == ^flow_id and
            is_nil(flow.deleted_at)
      )
    )
  end
end
