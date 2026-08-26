defmodule Storyarn.Platform.Onboarding do
  @moduledoc """
  Platform capability for contextual, per-user onboarding tutorials.

  Every authenticated user starts with each tutorial pending. A tutorial only
  stops opening automatically after the user explicitly chooses not to see it
  again. Account settings can restart any hidden tutorial.
  """

  alias Storyarn.Platform.Onboarding.Commands.Tutorials, as: TutorialCommands
  alias Storyarn.Platform.Onboarding.Queries.Tutorials, as: TutorialQueries
  alias Storyarn.Platform.Onboarding.TutorialProgress

  @type tutorial_state :: :pending | :completed
  @type scope :: %{required(:user) => %{required(:id) => pos_integer()}}
  @type summary :: %{
          guides: %{String.t() => %{state: tutorial_state(), version: pos_integer()}}
        }

  @doc "Returns the ordered list of tutorial keys."
  @spec tutorials() :: [TutorialProgress.tutorial()]
  defdelegate tutorials(), to: TutorialQueries

  @doc "Casts a client or server tutorial key without creating atoms."
  @spec cast_tutorial(atom() | String.t()) :: {:ok, TutorialProgress.tutorial()} | :error
  defdelegate cast_tutorial(tutorial), to: TutorialProgress

  @doc "Returns the current version of a tutorial guide."
  @spec guide_version(TutorialProgress.tutorial()) :: pos_integer()
  defdelegate guide_version(tutorial), to: TutorialQueries

  @doc "Builds the complete onboarding state for a user in a single query."
  @spec summary(scope()) :: summary()
  defdelegate summary(scope), to: TutorialQueries

  @doc "Marks a tutorial as completed for the current user."
  @spec complete_tutorial(scope(), atom() | String.t()) ::
          {:ok, TutorialProgress.t()} | {:error, :invalid_tutorial | Ecto.Changeset.t()}
  defdelegate complete_tutorial(scope, tutorial), to: TutorialCommands

  @doc "Restarts one tutorial without changing the remaining guides."
  @spec restart_tutorial(scope(), atom() | String.t()) ::
          {:ok, TutorialProgress.t()} | {:error, :invalid_tutorial | Ecto.Changeset.t()}
  defdelegate restart_tutorial(scope, tutorial), to: TutorialCommands

  @doc "Restarts every tutorial for the current user."
  @spec restart_all(scope()) :: {:ok, [TutorialProgress.t()]} | {:error, Ecto.Changeset.t()}
  defdelegate restart_all(scope), to: TutorialCommands

  @doc "Returns whether a guide should auto-open on its canonical route."
  @spec pending?(summary(), atom() | String.t()) :: boolean()
  defdelegate pending?(summary, tutorial), to: TutorialQueries
end
