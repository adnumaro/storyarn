defmodule Storyarn.Onboarding do
  @moduledoc """
  Context for contextual, per-user onboarding tutorials.

  New users enter the automatic onboarding cohort when they complete
  registration. Existing users remain inactive until they explicitly restart a
  tutorial from account settings.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.Onboarding.TutorialProgress
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @guide_versions %{
    workspace: 1,
    sheets: 1,
    flows: 1,
    scenes: 1,
    localization: 1,
    export: 1
  }

  @type tutorial_state :: :inactive | :pending | :completed
  @type summary :: %{
          eligible: boolean(),
          guides: %{String.t() => %{state: tutorial_state(), version: pos_integer()}}
        }

  @doc "Returns the ordered list of tutorial keys."
  @spec tutorials() :: [TutorialProgress.tutorial()]
  def tutorials, do: TutorialProgress.tutorials()

  @doc "Returns the current version of a tutorial guide."
  @spec guide_version(TutorialProgress.tutorial()) :: pos_integer()
  def guide_version(tutorial), do: Map.fetch!(@guide_versions, tutorial)

  @doc "Builds the complete onboarding state for a user in a single query."
  @spec summary(Scope.t()) :: summary()
  def summary(%Scope{user: %User{} = user}) do
    progress_by_tutorial =
      TutorialProgress
      |> where([progress], progress.user_id == ^user.id)
      |> Repo.all()
      |> Map.new(&{&1.tutorial, &1})

    eligible = not is_nil(user.onboarding_started_at)

    guides =
      Map.new(tutorials(), fn tutorial ->
        progress = Map.get(progress_by_tutorial, tutorial)
        state = tutorial_state(progress, eligible)

        {Atom.to_string(tutorial), %{state: state, version: guide_version(tutorial)}}
      end)

    %{eligible: eligible, guides: guides}
  end

  @doc "Marks a tutorial as completed for the current user."
  @spec complete_tutorial(Scope.t(), atom() | String.t()) ::
          {:ok, TutorialProgress.t()} | {:error, :invalid_tutorial | Ecto.Changeset.t()}
  def complete_tutorial(%Scope{user: %User{} = user}, tutorial) do
    case TutorialProgress.cast_tutorial(tutorial) do
      {:ok, tutorial} -> put_progress(user, tutorial, TimeHelpers.now())
      :error -> {:error, :invalid_tutorial}
    end
  end

  @doc "Restarts one tutorial without enabling the remaining inactive guides."
  @spec restart_tutorial(Scope.t(), atom() | String.t()) ::
          {:ok, TutorialProgress.t()} | {:error, :invalid_tutorial | Ecto.Changeset.t()}
  def restart_tutorial(%Scope{user: %User{} = user}, tutorial) do
    case TutorialProgress.cast_tutorial(tutorial) do
      {:ok, tutorial} -> put_progress(user, tutorial, nil)
      :error -> {:error, :invalid_tutorial}
    end
  end

  @doc "Restarts every tutorial for the current user."
  @spec restart_all(Scope.t()) :: {:ok, [TutorialProgress.t()]} | {:error, Ecto.Changeset.t()}
  def restart_all(%Scope{user: %User{} = user}) do
    Repo.transact(fn -> {:ok, restart_tutorials(user, tutorials(), [])} end)
  end

  @doc "Returns whether a guide should auto-open on its canonical route."
  @spec pending?(summary(), atom() | String.t()) :: boolean()
  def pending?(%{guides: guides}, tutorial) do
    with {:ok, tutorial} <- TutorialProgress.cast_tutorial(tutorial),
         %{state: :pending} <- Map.get(guides, Atom.to_string(tutorial)) do
      true
    else
      _ -> false
    end
  end

  defp tutorial_state(%TutorialProgress{completed_at: %DateTime{}}, _eligible), do: :completed
  defp tutorial_state(%TutorialProgress{completed_at: nil}, _eligible), do: :pending
  defp tutorial_state(nil, true), do: :pending
  defp tutorial_state(nil, false), do: :inactive

  defp restart_tutorials(_user, [], progress), do: Enum.reverse(progress)

  defp restart_tutorials(user, [tutorial | remaining], progress) do
    case put_progress(user, tutorial, nil) do
      {:ok, item} -> restart_tutorials(user, remaining, [item | progress])
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp put_progress(user, tutorial, completed_at) do
    %TutorialProgress{user_id: user.id}
    |> TutorialProgress.changeset(%{
      tutorial: tutorial,
      guide_version: guide_version(tutorial),
      completed_at: completed_at
    })
    |> Repo.insert(
      conflict_target: [:user_id, :tutorial],
      on_conflict: {:replace, [:guide_version, :completed_at, :updated_at]},
      returning: true
    )
  end
end
