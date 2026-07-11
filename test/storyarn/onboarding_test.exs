defmodule Storyarn.OnboardingTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures

  alias Storyarn.Accounts.Scope
  alias Storyarn.Onboarding
  alias Storyarn.Onboarding.TutorialProgress
  alias Storyarn.Repo

  describe "summary/1" do
    test "keeps existing users inactive by default" do
      user = user_fixture()

      summary = Onboarding.summary(Scope.for_user(user))

      refute summary.eligible
      assert summary.guides["workspace"].state == :inactive
      assert summary.guides["export"].state == :inactive
    end

    test "makes every guide pending for a newly onboarded user" do
      user = onboarding_user_fixture()

      summary = Onboarding.summary(Scope.for_user(user))

      assert summary.eligible
      assert Enum.all?(summary.guides, fn {_key, guide} -> guide.state == :pending end)
    end

    test "makes a completed guide pending when its stored version differs" do
      user = onboarding_user_fixture()

      Repo.insert!(%TutorialProgress{
        user_id: user.id,
        tutorial: :workspace,
        guide_version: Onboarding.guide_version(:workspace) + 1,
        completed_at: DateTime.utc_now(:second)
      })

      summary = Onboarding.summary(Scope.for_user(user))

      assert summary.guides["workspace"].state == :pending
      assert summary.guides["workspace"].version == Onboarding.guide_version(:workspace)
    end
  end

  describe "tutorial progress" do
    test "completes and restarts one tutorial without changing the others" do
      user = user_fixture()
      scope = Scope.for_user(user)

      assert {:ok, completed} = Onboarding.complete_tutorial(scope, "sheets")
      assert completed.tutorial == :sheets
      assert completed.completed_at

      summary = Onboarding.summary(scope)
      assert summary.guides["sheets"].state == :completed
      assert summary.guides["flows"].state == :inactive

      assert {:ok, restarted} = Onboarding.restart_tutorial(scope, :sheets)
      assert restarted.tutorial == :sheets
      assert is_nil(restarted.completed_at)

      summary = Onboarding.summary(scope)
      assert summary.guides["sheets"].state == :pending
      assert summary.guides["flows"].state == :inactive
    end

    test "restarts all tutorials independently of cohort eligibility" do
      user = user_fixture()
      scope = Scope.for_user(user)

      assert {:ok, progress} = Onboarding.restart_all(scope)
      assert length(progress) == 6

      summary = Onboarding.summary(scope)
      refute summary.eligible
      assert Enum.all?(summary.guides, fn {_key, guide} -> guide.state == :pending end)
    end

    test "isolates progress by user" do
      first_user = user_fixture()
      second_user = user_fixture()

      assert {:ok, _progress} =
               first_user
               |> Scope.for_user()
               |> Onboarding.complete_tutorial(:workspace)

      assert Onboarding.summary(Scope.for_user(first_user)).guides["workspace"].state ==
               :completed

      assert Onboarding.summary(Scope.for_user(second_user)).guides["workspace"].state ==
               :inactive
    end

    test "rejects unknown client keys without creating atoms" do
      scope = Scope.for_user(user_fixture())

      assert {:error, :invalid_tutorial} =
               Onboarding.complete_tutorial(scope, "not-a-real-tutorial")
    end
  end

  defp onboarding_user_fixture do
    user_fixture()
    |> change(onboarding_started_at: DateTime.utc_now(:second))
    |> Repo.update!()
  end
end
