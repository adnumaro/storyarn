defmodule Storyarn.Screenplays.ScreenplayQueries do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Screenplays.{Screenplay, ScreenplayElement}

  @doc """
  Gets a screenplay with all elements preloaded (ordered by position).
  """
  def get_with_elements(screenplay_id) do
    from(s in Screenplay,
      where: s.id == ^screenplay_id and is_nil(s.deleted_at),
      preload: [elements: ^from(e in ScreenplayElement, order_by: e.position)]
    )
    |> Repo.one()
  end

  @doc """
  Returns the number of elements in a screenplay.
  """
  def count_elements(screenplay_id) do
    from(e in ScreenplayElement,
      where: e.screenplay_id == ^screenplay_id,
      select: count(e.id)
    )
    |> Repo.one()
  end

  @doc """
  Lists all drafts of a given screenplay.
  Excludes soft-deleted drafts.
  """
  def list_drafts(screenplay_id) do
    from(s in Screenplay,
      where: s.draft_of_id == ^screenplay_id and is_nil(s.deleted_at),
      order_by: [asc: s.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Resolves screenplay element source info for entity reference backlinks.
  Joins entity_references with screenplay_elements and screenplays to return enriched backlink data.
  Used by the Sheets.ReferenceTracker to avoid cross-context schema queries.
  """
  def query_screenplay_element_backlinks(target_type, target_id, project_id) do
    alias Storyarn.Sheets.EntityReference

    from(r in EntityReference,
      join: e in ScreenplayElement,
      on: r.source_type == "screenplay_element" and r.source_id == e.id,
      join: s in Screenplay,
      on: e.screenplay_id == s.id,
      where: r.target_type == ^target_type and r.target_id == ^target_id,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      select: %{
        id: r.id,
        source_type: r.source_type,
        source_id: r.source_id,
        context: r.context,
        inserted_at: r.inserted_at,
        element_type: e.type,
        screenplay_id: s.id,
        screenplay_name: s.name
      },
      order_by: [desc: r.inserted_at]
    )
    |> Repo.all()
    |> Enum.map(fn ref ->
      %{
        id: ref.id,
        source_type: "screenplay_element",
        source_id: ref.source_id,
        context: ref.context,
        inserted_at: ref.inserted_at,
        source_info: %{
          type: :screenplay,
          screenplay_id: ref.screenplay_id,
          screenplay_name: ref.screenplay_name,
          element_type: ref.element_type
        }
      }
    end)
  end
end
