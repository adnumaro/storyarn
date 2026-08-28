defmodule Storyarn.Platform.Onboarding.Commands.Tutorials do
  @moduledoc false

  alias Storyarn.Platform.Onboarding.Queries.Tutorials, as: TutorialQueries
  alias Storyarn.Platform.Onboarding.TutorialProgress
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  @spec complete_tutorial(map(), atom() | String.t()) ::
          {:ok, TutorialProgress.t()} | {:error, :invalid_tutorial | Ecto.Changeset.t()}
  def complete_tutorial(%{user: %{id: _} = user}, tutorial) do
    case TutorialProgress.cast_tutorial(tutorial) do
      {:ok, tutorial} -> put_progress(user, tutorial, TimeHelpers.now())
      :error -> {:error, :invalid_tutorial}
    end
  end

  @spec restart_tutorial(map(), atom() | String.t()) ::
          {:ok, TutorialProgress.t()} | {:error, :invalid_tutorial | Ecto.Changeset.t()}
  def restart_tutorial(%{user: %{id: _} = user}, tutorial) do
    case TutorialProgress.cast_tutorial(tutorial) do
      {:ok, tutorial} -> put_progress(user, tutorial, nil)
      :error -> {:error, :invalid_tutorial}
    end
  end

  @spec restart_all(map()) :: {:ok, [TutorialProgress.t()]} | {:error, Ecto.Changeset.t()}
  def restart_all(%{user: %{id: _} = user}) do
    Repo.transact(fn -> {:ok, restart_tutorials(user, TutorialQueries.tutorials(), [])} end)
  end

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
      guide_version: TutorialQueries.guide_version(tutorial),
      completed_at: completed_at
    })
    |> Repo.insert(
      conflict_target: [:user_id, :tutorial],
      on_conflict: {:replace, [:guide_version, :completed_at, :updated_at]},
      returning: true
    )
  end
end
