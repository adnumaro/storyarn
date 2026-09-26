defmodule Storyarn.Commercial.Queries.TrashRetentionTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.CommercialFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Commercial
  alias Storyarn.Commercial.Billing.PlanPeriod

  @studio_hours 90 * 24
  @free_hours 24

  setup do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    now = DateTime.utc_now(:second)

    # Studio for eight days, then Free for the last two.
    Repo.delete_all(from(period in PlanPeriod, where: period.user_id == ^owner.id))
    Repo.insert!(%PlanPeriod{user_id: owner.id, plan: "studio", started_at: DateTime.shift(now, day: -10)})
    Repo.insert!(%PlanPeriod{user_id: owner.id, plan: "free", started_at: DateTime.shift(now, day: -2)})

    %{owner: owner, workspace: workspace, now: now}
  end

  test "an item deleted under a longer plan keeps its retention after a downgrade", ctx do
    during_studio = DateTime.shift(ctx.now, day: -5)
    after_downgrade = DateTime.shift(ctx.now, day: -1)

    assert Commercial.trash_retention_hours([{ctx.workspace.id, during_studio}, {ctx.workspace.id, after_downgrade}]) ==
             [@studio_hours, @free_hours]
  end

  test "an item deleted before any recorded plan gets the current plan's retention", ctx do
    assert Commercial.trash_retention_hours([{ctx.workspace.id, DateTime.shift(ctx.now, day: -20)}]) == [@free_hours]
  end

  test "an upgrade lengthens the retention of everything already in the trash", ctx do
    change_plan!(ctx.owner, "studio")

    assert Commercial.trash_retention_hours([
             {ctx.workspace.id, DateTime.shift(ctx.now, day: -5)},
             {ctx.workspace.id, DateTime.shift(ctx.now, day: -1)}
           ]) == [@studio_hours, @studio_hours]
  end

  test "returns nothing for no deletions" do
    assert Commercial.trash_retention_hours([]) == []
  end
end
