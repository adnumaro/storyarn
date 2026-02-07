defmodule Storyarn.Sheets.SheetQueries do
  @moduledoc """
  Read-only query functions for sheets.

  Provides all sheet retrieval, listing, search, and tree traversal operations.
  Mutation operations remain in `SheetCrud`.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Sheets.Sheet
  alias Storyarn.Repo

  # =============================================================================
  # Tree Operations
  # =============================================================================

  @spec list_sheets_tree(integer()) :: [Sheet.t()]
  def list_sheets_tree(project_id) do
    from(s in Sheet,
      where: s.project_id == ^project_id and is_nil(s.parent_id) and is_nil(s.deleted_at),
      order_by: [asc: s.position, asc: s.name]
    )
    |> Repo.all()
    |> preload_children_recursive()
  end

  @spec get_sheet(integer(), integer()) :: Sheet.t() | nil
  def get_sheet(project_id, sheet_id) do
    Sheet
    |> where(project_id: ^project_id, id: ^sheet_id)
    |> where([s], is_nil(s.deleted_at))
    |> preload([:blocks, :avatar_asset, :banner_asset])
    |> Repo.one()
  end

  @spec get_sheet!(integer(), integer()) :: Sheet.t()
  def get_sheet!(project_id, sheet_id) do
    Sheet
    |> where(project_id: ^project_id, id: ^sheet_id)
    |> where([s], is_nil(s.deleted_at))
    |> preload([:blocks, :avatar_asset, :banner_asset])
    |> Repo.one!()
  end

  @spec get_sheet_with_ancestors(integer(), integer()) :: [Sheet.t()] | nil
  def get_sheet_with_ancestors(project_id, sheet_id) do
    case get_sheet(project_id, sheet_id) do
      nil -> nil
      sheet -> build_ancestor_chain(sheet, [sheet])
    end
  end

  @spec get_sheet_with_descendants(integer(), integer()) :: Sheet.t() | nil
  def get_sheet_with_descendants(project_id, sheet_id) do
    case get_sheet(project_id, sheet_id) do
      nil -> nil
      sheet -> sheet |> preload_children_recursive() |> List.wrap() |> List.first()
    end
  end

  @spec get_children(integer()) :: [Sheet.t()]
  def get_children(sheet_id) do
    from(s in Sheet,
      where: s.parent_id == ^sheet_id and is_nil(s.deleted_at),
      order_by: [asc: s.position, asc: s.name],
      preload: [:avatar_asset]
    )
    |> Repo.all()
  end

  @spec list_all_sheets(integer()) :: [Sheet.t()]
  def list_all_sheets(project_id) do
    from(s in Sheet,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      order_by: [asc: s.position, asc: s.name],
      preload: [:avatar_asset]
    )
    |> Repo.all()
  end

  @spec list_leaf_sheets(integer()) :: [Sheet.t()]
  def list_leaf_sheets(project_id) do
    parent_ids_subquery =
      from(s in Sheet,
        where: s.project_id == ^project_id and not is_nil(s.parent_id) and is_nil(s.deleted_at),
        select: s.parent_id
      )

    from(s in Sheet,
      where:
        s.project_id == ^project_id and s.id not in subquery(parent_ids_subquery) and
          is_nil(s.deleted_at),
      order_by: [asc: s.position, asc: s.name],
      preload: [:avatar_asset]
    )
    |> Repo.all()
  end

  # =============================================================================
  # Search
  # =============================================================================

  @spec search_sheets(integer(), String.t()) :: [Sheet.t()]
  def search_sheets(project_id, query) when is_binary(query) do
    query = String.trim(query)

    if query == "" do
      from(s in Sheet,
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        order_by: [desc: s.updated_at],
        limit: 10
      )
      |> Repo.all()
    else
      search_term = "%#{query}%"

      from(s in Sheet,
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        where: ilike(s.name, ^search_term) or ilike(s.shortcut, ^search_term),
        order_by: [asc: s.name],
        limit: 10
      )
      |> Repo.all()
    end
  end

  @spec get_sheet_by_shortcut(integer(), String.t() | nil) :: Sheet.t() | nil
  def get_sheet_by_shortcut(project_id, shortcut) when is_binary(shortcut) do
    from(s in Sheet,
      where: s.project_id == ^project_id and s.shortcut == ^shortcut and is_nil(s.deleted_at),
      preload: [:blocks, :avatar_asset]
    )
    |> Repo.one()
  end

  def get_sheet_by_shortcut(_project_id, _shortcut), do: nil

  # =============================================================================
  # Variables
  # =============================================================================

  @spec list_project_variables(integer()) :: [map()]
  def list_project_variables(project_id) do
    alias Storyarn.Sheets.Block

    variable_types = ~w(text rich_text number select multi_select boolean date)

    from(b in Block,
      join: s in Sheet,
      on: b.sheet_id == s.id,
      where:
        s.project_id == ^project_id and
          is_nil(s.deleted_at) and
          is_nil(b.deleted_at) and
          b.type in ^variable_types and
          not is_nil(b.variable_name) and
          b.variable_name != "" and
          b.is_constant == false,
      select: %{
        sheet_id: s.id,
        sheet_name: s.name,
        sheet_shortcut: coalesce(s.shortcut, fragment("CAST(? AS TEXT)", s.id)),
        block_id: b.id,
        variable_name: b.variable_name,
        block_type: b.type,
        config: b.config
      },
      order_by: [asc: s.name, asc: b.position]
    )
    |> Repo.all()
    |> Enum.map(fn var ->
      options =
        case var.block_type do
          type when type in ["select", "multi_select"] ->
            var.config["options"] || []

          _ ->
            nil
        end

      var
      |> Map.put(:options, options)
      |> Map.delete(:config)
    end)
  end

  # =============================================================================
  # Reference Validation
  # =============================================================================

  @spec validate_reference_target(String.t(), integer(), integer()) ::
          {:ok, Sheet.t() | Storyarn.Flows.Flow.t()} | {:error, :not_found | :invalid_type}
  def validate_reference_target(target_type, target_id, project_id) do
    case target_type do
      "sheet" ->
        case get_sheet(project_id, target_id) do
          nil -> {:error, :not_found}
          sheet -> {:ok, sheet}
        end

      "flow" ->
        case Storyarn.Flows.get_flow(project_id, target_id) do
          nil -> {:error, :not_found}
          flow -> {:ok, flow}
        end

      _ ->
        {:error, :invalid_type}
    end
  end

  # =============================================================================
  # Trash
  # =============================================================================

  @spec list_trashed_sheets(integer()) :: [Sheet.t()]
  def list_trashed_sheets(project_id) do
    from(s in Sheet,
      where: s.project_id == ^project_id and not is_nil(s.deleted_at),
      order_by: [desc: s.deleted_at],
      preload: [:avatar_asset]
    )
    |> Repo.all()
  end

  @spec get_trashed_sheet(integer(), integer()) :: Sheet.t() | nil
  def get_trashed_sheet(project_id, sheet_id) do
    Sheet
    |> where(project_id: ^project_id, id: ^sheet_id)
    |> where([s], not is_nil(s.deleted_at))
    |> preload([:avatar_asset])
    |> Repo.one()
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp build_ancestor_chain(%Sheet{parent_id: nil}, chain), do: chain

  defp build_ancestor_chain(%Sheet{parent_id: parent_id, project_id: project_id}, chain) do
    parent =
      Sheet
      |> Repo.get!(parent_id)
      |> Repo.preload(:avatar_asset)

    if parent.project_id == project_id do
      build_ancestor_chain(parent, [parent | chain])
    else
      chain
    end
  end

  defp preload_children_recursive(sheets) when is_list(sheets) do
    Enum.map(sheets, &preload_children_recursive/1)
  end

  defp preload_children_recursive(%Sheet{} = sheet) do
    sheet = Repo.preload(sheet, :avatar_asset)

    children =
      from(s in Sheet,
        where: s.parent_id == ^sheet.id and is_nil(s.deleted_at),
        order_by: [asc: s.position, asc: s.name]
      )
      |> Repo.all()
      |> preload_children_recursive()

    %{sheet | children: children}
  end
end
