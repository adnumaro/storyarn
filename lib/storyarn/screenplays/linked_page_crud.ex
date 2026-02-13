defmodule Storyarn.Screenplays.LinkedPageCrud do
  @moduledoc """
  Manages linked screenplay pages for response choices.

  Response choices can link to child screenplay pages, turning the
  sidebar tree into a narrative branching structure. This module
  provides CRUD operations for creating, linking, and unlinking
  child pages from response choices.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo

  alias Storyarn.Screenplays.{
    Screenplay,
    ScreenplayCrud,
    ScreenplayElement
  }

  @doc """
  Creates a child screenplay from a response choice.

  Names the child after the choice text (or a default).
  Sets `linked_screenplay_id` on the choice.
  Returns `{:ok, screenplay, element}` or `{:error, reason}`.
  """
  def create_linked_page(%Screenplay{} = parent, %ScreenplayElement{} = element, choice_id) do
    project = Storyarn.Projects.get_project!(parent.project_id)
    choice = find_choice(element, choice_id)

    cond do
      is_nil(choice) ->
        {:error, :choice_not_found}

      choice["linked_screenplay_id"] ->
        {:error, :already_linked}

      true ->
        do_create_linked_page(project, parent, element, choice)
    end
  end

  @doc """
  Links a response choice to an existing child screenplay.

  Validates the child exists, is a child of the parent, and is not deleted.
  Returns `{:ok, element}` or `{:error, reason}`.
  """
  def link_choice(%ScreenplayElement{} = element, choice_id, child_screenplay_id, parent_id) do
    choice = find_choice(element, choice_id)

    cond do
      is_nil(choice) ->
        {:error, :choice_not_found}

      not valid_child?(child_screenplay_id, parent_id) ->
        {:error, :invalid_child}

      already_linked_to_other_choice?(element, child_screenplay_id, choice_id) ->
        {:error, :already_linked_to_other_choice}

      true ->
        update_choice(element, choice_id, fn c ->
          Map.put(c, "linked_screenplay_id", child_screenplay_id)
        end)
    end
  end

  @doc """
  Unlinks a response choice from its linked screenplay.

  Does NOT delete the child screenplay.
  Returns `{:ok, element}` or `{:error, reason}`.
  """
  def unlink_choice(%ScreenplayElement{} = element, choice_id) do
    choice = find_choice(element, choice_id)

    cond do
      is_nil(choice) ->
        {:error, :choice_not_found}

      is_nil(choice["linked_screenplay_id"]) ->
        {:ok, element}

      true ->
        update_choice(element, choice_id, fn c ->
          Map.put(c, "linked_screenplay_id", nil)
        end)
    end
  end

  @doc """
  Returns the linked screenplay IDs for all choices in a response element.
  Skips nil values.
  """
  def linked_screenplay_ids(%ScreenplayElement{data: data}) do
    (data || %{})
    |> Map.get("choices", [])
    |> Enum.map(& &1["linked_screenplay_id"])
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Lists child screenplays for a parent. Returns `[%{id, name}]`.
  """
  def list_child_screenplays(parent_id) do
    from(s in Screenplay,
      where: s.parent_id == ^parent_id and is_nil(s.deleted_at),
      order_by: [asc: s.position],
      select: %{id: s.id, name: s.name}
    )
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp do_create_linked_page(project, parent, element, choice) do
    name = choice_name(choice)

    Repo.transaction(fn ->
      with {:ok, child} <-
             ScreenplayCrud.create_screenplay(project, %{name: name, parent_id: parent.id}),
           {:ok, updated_element} <- set_linked_screenplay_id(element, choice["id"], child.id) do
        {child, updated_element}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, {child, updated_element}} -> {:ok, child, updated_element}
      {:error, reason} -> {:error, reason}
    end
  end

  defp set_linked_screenplay_id(element, choice_id, child_id) do
    update_choice(element, choice_id, fn c ->
      Map.put(c, "linked_screenplay_id", child_id)
    end)
  end

  @doc "Finds a choice by ID in a response element's data."
  def find_choice(%ScreenplayElement{data: data}, choice_id) do
    (data || %{})
    |> Map.get("choices", [])
    |> Enum.find(&(&1["id"] == choice_id))
  end

  @doc "Updates a choice in a response element by applying update_fn to the matching choice."
  def update_choice(%ScreenplayElement{} = element, choice_id, update_fn) do
    data = element.data || %{}

    choices =
      Enum.map(data["choices"] || [], fn choice ->
        if choice["id"] == choice_id, do: update_fn.(choice), else: choice
      end)

    element
    |> ScreenplayElement.update_changeset(%{data: Map.put(data, "choices", choices)})
    |> Repo.update()
  end

  defp valid_child?(child_screenplay_id, parent_id) do
    from(s in Screenplay,
      where: s.id == ^child_screenplay_id and s.parent_id == ^parent_id and is_nil(s.deleted_at)
    )
    |> Repo.exists?()
  end

  defp already_linked_to_other_choice?(element, child_id, current_choice_id) do
    (element.data || %{})
    |> Map.get("choices", [])
    |> Enum.any?(fn c ->
      c["id"] != current_choice_id and c["linked_screenplay_id"] == child_id
    end)
  end

  defp choice_name(choice) do
    text = choice["text"] || ""
    if text == "", do: "Untitled Branch", else: text
  end
end
