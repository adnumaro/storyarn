defmodule Storyarn.Platform.Onboarding.Queries.Tutorials do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Onboarding.TutorialProgress
  alias Storyarn.Repo

  # Version 1 completions predate the explicit opt-out checkbox. Keeping the
  # current guides on version 2 makes those legacy finishes pending again while
  # preserving version 2 completions as explicit opt-outs.
  @guide_versions %{
    workspace: 2,
    sheets: 2,
    flows: 2,
    scenes: 2,
    localization: 2,
    export: 2
  }

  @type tutorial_state :: :pending | :completed
  @type summary :: %{
          guides: %{String.t() => %{state: tutorial_state(), version: pos_integer()}}
        }

  @spec tutorials() :: [TutorialProgress.tutorial()]
  def tutorials, do: TutorialProgress.tutorials()

  @spec guide_version(TutorialProgress.tutorial()) :: pos_integer()
  def guide_version(tutorial), do: Map.fetch!(@guide_versions, tutorial)

  @spec summary(map()) :: summary()
  def summary(%{user: %{id: _} = user}) do
    progress_by_tutorial =
      TutorialProgress
      |> where([progress], progress.user_id == ^user.id)
      |> Repo.all()
      |> Map.new(&{&1.tutorial, &1})

    guides =
      Map.new(tutorials(), fn tutorial ->
        progress = Map.get(progress_by_tutorial, tutorial)
        state = tutorial_state(progress, guide_version(tutorial))

        {Atom.to_string(tutorial), %{state: state, version: guide_version(tutorial)}}
      end)

    %{guides: guides}
  end

  @spec pending?(summary(), atom() | String.t()) :: boolean()
  def pending?(%{guides: guides}, tutorial) do
    with {:ok, tutorial} <- TutorialProgress.cast_tutorial(tutorial),
         %{state: :pending} <- Map.get(guides, Atom.to_string(tutorial)) do
      true
    else
      _ -> false
    end
  end

  defp tutorial_state(%TutorialProgress{completed_at: %DateTime{}, guide_version: version}, current_version)
       when version == current_version, do: :completed

  defp tutorial_state(%TutorialProgress{}, _current_version), do: :pending
  defp tutorial_state(nil, _current_version), do: :pending
end
