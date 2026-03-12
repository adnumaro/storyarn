defmodule Storyarn.Billing do
  @moduledoc """
  The Billing context.

  Handles plan limits, subscriptions, and usage tracking.
  """

  alias Storyarn.Billing.{Limits, Plan, SubscriptionCrud}

  # Plan queries
  defdelegate get_plan(plan_key), to: Plan, as: :get
  defdelegate list_plans(), to: Plan, as: :all
  defdelegate default_plan(), to: Plan
  defdelegate plan_limit(plan_key, resource), to: Plan, as: :limit

  # Usage counting (internal, exposed for testing)
  defdelegate count_project_items(project_id), to: Limits
  defdelegate count_unique_workspace_users(workspace_id), to: Limits

  # Limit checks
  defdelegate can_create_workspace?(user), to: Limits
  defdelegate can_create_project?(workspace), to: Limits
  defdelegate can_invite_member?(workspace_or_project), to: Limits
  defdelegate can_upload_asset?(workspace, file_size), to: Limits
  defdelegate can_create_item?(project), to: Limits
  defdelegate can_create_named_version?(project_id, workspace_id), to: Limits
  defdelegate can_create_project_snapshot?(project_id, workspace_id), to: Limits
  defdelegate usage(workspace), to: Limits

  # Subscription operations
  defdelegate plan_for(workspace), to: SubscriptionCrud
  defdelegate create_subscription(workspace), to: SubscriptionCrud
  defdelegate create_subscription(workspace, plan), to: SubscriptionCrud
  defdelegate get_subscription(workspace_id), to: SubscriptionCrud
  defdelegate update_plan(subscription, new_plan), to: SubscriptionCrud
end
