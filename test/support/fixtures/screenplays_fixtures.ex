defmodule Storyarn.ScreenplaysFixtures do
  @moduledoc """
  This module defines test helpers for creating
  screenplays via the `Storyarn.Screenplays` context.
  """

  alias Storyarn.ProjectsFixtures
  alias Storyarn.Repo
  alias Storyarn.Screenplays.{Screenplay, ScreenplayElement}

  def unique_screenplay_name, do: "Screenplay #{System.unique_integer([:positive])}"

  def valid_screenplay_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_screenplay_name(),
      description: "A test screenplay"
    })
  end

  @doc """
  Creates a screenplay.
  Uses Repo directly to avoid circular dependency with context facade
  (which may not be available during early tasks).
  """
  def screenplay_fixture(project \\ nil, attrs \\ %{}) do
    project = project || ProjectsFixtures.project_fixture()

    attrs = valid_screenplay_attributes(attrs)

    {:ok, screenplay} =
      %Screenplay{project_id: project.id}
      |> Screenplay.create_changeset(Map.put(attrs, :shortcut, nil))
      |> Repo.insert()

    screenplay
  end

  @doc """
  Creates a screenplay element.
  """
  def element_fixture(screenplay, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        type: "action",
        content: "Test action line.",
        position: next_element_position(screenplay.id)
      })

    {:ok, element} =
      %ScreenplayElement{screenplay_id: screenplay.id}
      |> ScreenplayElement.create_changeset(attrs)
      |> Repo.insert()

    element
  end

  defp next_element_position(screenplay_id) do
    import Ecto.Query

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
