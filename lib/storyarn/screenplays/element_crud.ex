defmodule Storyarn.Screenplays.ElementCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Screenplays.{Screenplay, ScreenplayElement}

  @doc """
  Lists all elements for a screenplay, ordered by position.
  """
  def list_elements(screenplay_id) do
    from(e in ScreenplayElement,
      where: e.screenplay_id == ^screenplay_id,
      order_by: [asc: e.position]
    )
    |> Repo.all()
  end

  @doc """
  Creates an element appended at the end of the screenplay.
  """
  def create_element(%Screenplay{} = screenplay, attrs) do
    position = next_position(screenplay.id)

    %ScreenplayElement{screenplay_id: screenplay.id}
    |> ScreenplayElement.create_changeset(Map.put(attrs, :position, position))
    |> Repo.insert()
  end

  @doc """
  Inserts an element at a specific position, shifting subsequent elements.
  """
  def insert_element_at(%Screenplay{} = screenplay, position, attrs) when is_integer(position) do
    Repo.transaction(fn ->
      # Shift all elements at >= position by +1
      from(e in ScreenplayElement,
        where: e.screenplay_id == ^screenplay.id and e.position >= ^position
      )
      |> Repo.update_all(inc: [position: 1])

      # Insert new element at the target position
      case %ScreenplayElement{screenplay_id: screenplay.id}
           |> ScreenplayElement.create_changeset(Map.put(attrs, :position, position))
           |> Repo.insert() do
        {:ok, element} -> element
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Updates an element's content, data, type, depth, or branch.
  """
  def update_element(%ScreenplayElement{} = element, attrs) do
    element
    |> ScreenplayElement.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an element and compacts positions of subsequent elements.
  """
  def delete_element(%ScreenplayElement{} = element) do
    Repo.transaction(fn ->
      screenplay_id = element.screenplay_id
      deleted_position = element.position

      case Repo.delete(element) do
        {:ok, deleted} ->
          # Shift elements after the deleted one by -1
          from(e in ScreenplayElement,
            where: e.screenplay_id == ^screenplay_id and e.position > ^deleted_position
          )
          |> Repo.update_all(inc: [position: -1])

          deleted

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Reorders elements by a list of element IDs.
  Each element's position is set to its index in the list.
  """
  def reorder_elements(screenplay_id, element_ids) when is_list(element_ids) do
    if element_ids == [] do
      {:ok, list_elements(screenplay_id)}
    else
      ids = Enum.map(element_ids, &to_integer/1)
      positions = Enum.to_list(0..(length(ids) - 1))

      Repo.query!(
        """
        UPDATE screenplay_elements AS e
        SET position = v.new_position
        FROM unnest($1::bigint[], $2::int[]) AS v(id, new_position)
        WHERE e.id = v.id AND e.screenplay_id = $3
        """,
        [ids, positions, screenplay_id]
      )

      {:ok, list_elements(screenplay_id)}
    end
  end

  defp to_integer(v) when is_integer(v), do: v
  defp to_integer(v) when is_binary(v), do: String.to_integer(v)

  @doc """
  Splits an element at a cursor position, inserting a new element of the given type.

  1. Current element keeps text before cursor
  2. New element of `new_type` is inserted at position + 1 with empty content
  3. Third element (same type as original) at position + 2 with text after cursor
  4. All subsequent elements shift by +2

  Returns `{:ok, {before_element, new_element, after_element}}`.
  """
  def split_element(%ScreenplayElement{} = element, cursor_position, new_type)
      when is_integer(cursor_position) and is_binary(new_type) do
    content = element.content || ""
    before_text = String.slice(content, 0, cursor_position)
    after_text = String.slice(content, cursor_position, String.length(content))
    original_type = element.type
    screenplay_id = element.screenplay_id
    pos = element.position

    Repo.transaction(fn ->
      # Shift all elements after current position by +2
      from(e in ScreenplayElement,
        where: e.screenplay_id == ^screenplay_id and e.position > ^pos
      )
      |> Repo.update_all(inc: [position: 2])

      before_element =
        element
        |> ScreenplayElement.update_changeset(%{content: before_text})
        |> Repo.update()
        |> unwrap_or_rollback()

      new_element =
        %ScreenplayElement{screenplay_id: screenplay_id}
        |> ScreenplayElement.create_changeset(%{type: new_type, position: pos + 1, content: ""})
        |> Repo.insert()
        |> unwrap_or_rollback()

      after_element =
        %ScreenplayElement{screenplay_id: screenplay_id}
        |> ScreenplayElement.create_changeset(%{
          type: original_type,
          position: pos + 2,
          content: after_text
        })
        |> Repo.insert()
        |> unwrap_or_rollback()

      {before_element, new_element, after_element}
    end)
  end

  defp unwrap_or_rollback({:ok, record}), do: record
  defp unwrap_or_rollback({:error, changeset}), do: Repo.rollback(changeset)

  defp next_position(screenplay_id) do
    from(e in ScreenplayElement,
      where: e.screenplay_id == ^screenplay_id,
      select: max(e.position)
    )
    |> Repo.one()
    |> case do
      nil -> 0
      max -> max + 1
    end
  end
end
