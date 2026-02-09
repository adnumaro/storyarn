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
end
