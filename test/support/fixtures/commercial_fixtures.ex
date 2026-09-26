defmodule Storyarn.CommercialFixtures do
  @moduledoc """
  Test helpers for account plans and the read-only state that follows when an
  account is over its plan's limits.
  """

  alias Storyarn.Commercial.Billing.SubscriptionCrud
  alias Storyarn.Repo
  alias Storyarn.Workspaces

  @doc "Moves the user's account to `plan`."
  def change_plan!(user, plan) do
    {:ok, _subscription} = user.id |> SubscriptionCrud.get_subscription() |> SubscriptionCrud.update_plan(plan)
    :ok
  end

  @doc """
  Makes every workspace the user owns read-only: the account gets a second
  workspace on a plan that allows it, then drops to Free, which allows one.

  Returns the extra workspace; deleting it unlocks the account.
  """
  def lock_account!(user) do
    change_plan!(user, "beta")

    {:ok, extra} =
      Workspaces.create_workspace_with_owner(user, %{
        name: "Extra saga",
        slug: "extra-saga-#{System.unique_integer([:positive])}"
      })

    change_plan!(user, "free")
    extra
  end

  @doc "Brings the account back within its limits by deleting the workspace `lock_account!/1` added."
  def unlock_account!(extra_workspace) do
    Repo.delete!(extra_workspace)
    :ok
  end
end
