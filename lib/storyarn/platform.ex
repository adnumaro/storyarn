defmodule Storyarn.Platform do
  @moduledoc """
  Public facade for platform-wide capabilities and reaction policy.

  Product contexts own the business facts they emit. Platform decides which
  cross-cutting reactions those facts trigger. The current reaction is
  best-effort product analytics; durable notifications and email delivery must
  enter through persisted, idempotent workflows rather than this synchronous
  path.
  """

  alias Storyarn.Platform.Notifications
  alias Storyarn.Platform.Onboarding
  alias Storyarn.Platform.Reactions

  @type notification_delivery_outcome :: Notifications.delivery_outcome()
  @type onboarding_summary :: Onboarding.summary()

  @doc "Routes a context-owned event through Platform reaction policy."
  @spec react_to_event(term(), atom(), atom(), map()) :: :ok
  defdelegate react_to_event(scope_or_user, source, event_type, payload), to: Reactions

  @doc "Tracks one allowlisted, privacy-safe presentation analytics event."
  @spec track_analytics(term(), String.t(), map()) :: :ok
  defdelegate track_analytics(scope_or_user, event_name, properties \\ %{}),
    to: Reactions

  @doc "Returns frontend-safe analytics configuration for the presentation adapter."
  @spec analytics_frontend_config(term()) :: map() | nil
  defdelegate analytics_frontend_config(scope_or_user), to: Reactions

  @doc "Returns the ordered Platform onboarding tutorial keys."
  @spec onboarding_tutorials() :: [atom()]
  defdelegate onboarding_tutorials(), to: Onboarding, as: :tutorials

  @doc "Casts an onboarding tutorial key without creating atoms."
  @spec cast_onboarding_tutorial(atom() | String.t()) :: {:ok, atom()} | :error
  defdelegate cast_onboarding_tutorial(tutorial), to: Onboarding, as: :cast_tutorial

  @doc "Builds the complete Platform onboarding state for the current user."
  @spec onboarding_summary(term()) :: onboarding_summary()
  defdelegate onboarding_summary(scope), to: Onboarding, as: :summary

  @doc "Returns whether a Platform onboarding guide should open automatically."
  @spec onboarding_pending?(onboarding_summary(), atom() | String.t()) :: boolean()
  defdelegate onboarding_pending?(summary, tutorial), to: Onboarding, as: :pending?

  @doc "Marks one Platform onboarding tutorial as completed."
  @spec complete_onboarding_tutorial(term(), atom() | String.t()) :: {:ok, term()} | {:error, term()}
  defdelegate complete_onboarding_tutorial(scope, tutorial),
    to: Onboarding,
    as: :complete_tutorial

  @doc "Restarts one Platform onboarding tutorial."
  @spec restart_onboarding_tutorial(term(), atom() | String.t()) :: {:ok, term()} | {:error, term()}
  defdelegate restart_onboarding_tutorial(scope, tutorial),
    to: Onboarding,
    as: :restart_tutorial

  @doc "Restarts every Platform onboarding tutorial."
  @spec restart_all_onboarding_tutorials(term()) :: {:ok, [term()]} | {:error, term()}
  defdelegate restart_all_onboarding_tutorials(scope),
    to: Onboarding,
    as: :restart_all

  @doc "Returns the stable project categories collected for product metrics."
  @spec product_metric_project_types() :: [String.t()]
  defdelegate product_metric_project_types(), to: Reactions

  @doc "Returns the stable project subtype taxonomy collected for product metrics."
  @spec product_metric_project_subtypes() :: %{String.t() => [String.t()]}
  defdelegate product_metric_project_subtypes(), to: Reactions

  @doc "Returns the product metric subtypes available for one project category."
  @spec product_metric_project_subtypes(String.t()) :: [String.t()]
  defdelegate product_metric_project_subtypes(project_type), to: Reactions

  @doc "Returns the complete project classification options for presentation adapters."
  @spec product_metric_project_options() :: %{
          project_types: [String.t()],
          project_subtypes: %{String.t() => [String.t()]}
        }
  defdelegate product_metric_project_options(), to: Reactions

  @doc "Checks whether a project category belongs to the product metric taxonomy."
  @spec known_product_metric_project_type?(term()) :: boolean()
  defdelegate known_product_metric_project_type?(project_type), to: Reactions

  @doc "Checks whether a project subtype belongs to its product metric category."
  @spec known_product_metric_project_subtype?(term(), term()) :: boolean()
  defdelegate known_product_metric_project_subtype?(project_type, project_subtype),
    to: Reactions

  @doc "Persists a context-owned content activity through Platform notification policy."
  @spec deliver_content_activity(term(), pos_integer(), atom(), String.t(), map()) ::
          {:ok, term()} | {:error, term()}
  defdelegate deliver_content_activity(scope, project_id, action, entity_type, entity),
    to: Notifications,
    as: :deliver_content_activity_by_project_id

  @doc "Persists content activity from scalar context-owned identities."
  @spec deliver_content_activity_by_ids(pos_integer(), pos_integer(), atom(), String.t(), map()) ::
          {:ok, term()} | {:error, term()}
  defdelegate deliver_content_activity_by_ids(actor_id, project_id, action, entity_type, entity),
    to: Notifications

  @doc "Persists comment mentions and replies for the producer's selected recipients."
  @spec deliver_comment_activity(pos_integer(), pos_integer(), pos_integer(), [map()]) ::
          {:ok, notification_delivery_outcome()} | {:error, term()}
  defdelegate deliver_comment_activity(actor_id, project_id, comment_id, recipients),
    to: Notifications

  @doc "Persists a requester-only async outcome from scalar context-owned identities."
  @spec deliver_async_result(integer() | nil, pos_integer(), map()) ::
          {:ok, notification_delivery_outcome()} | {:error, term()}
  defdelegate deliver_async_result(requested_by_id, project_id, attrs),
    to: Notifications,
    as: :deliver_async_result_by_ids

  @doc "Persists a requester-only async outcome from an authorized consumer scope."
  @spec deliver_scoped_async_result(term(), term(), map()) ::
          {:ok, notification_delivery_outcome()} | {:error, term()}
  defdelegate deliver_scoped_async_result(recipient_scope, project, attrs),
    to: Notifications,
    as: :deliver_async_result

  @doc "Lists the current recipient's durable notifications."
  @spec list_notifications(term(), keyword()) :: [term()]
  defdelegate list_notifications(scope, opts \\ []), to: Notifications

  @doc "Counts unread durable notifications for the current recipient."
  @spec unread_notification_count(term()) :: non_neg_integer()
  defdelegate unread_notification_count(scope), to: Notifications, as: :unread_count

  @doc "Marks one recipient-owned notification as read."
  @spec mark_notification_read(term(), integer()) :: {:ok, term()} | {:error, :not_found}
  defdelegate mark_notification_read(scope, notification_id), to: Notifications, as: :mark_read

  @doc "Marks all recipient-owned notifications as read."
  @spec mark_all_notifications_read(term()) :: {:ok, non_neg_integer()}
  defdelegate mark_all_notifications_read(scope), to: Notifications, as: :mark_all_read

  @doc "Subscribes a recipient scope to its notification signal topic."
  @spec subscribe_notifications(term()) :: :ok | {:error, :not_found}
  defdelegate subscribe_notifications(scope), to: Notifications, as: :subscribe

  @doc "Publishes the committed notification outcome to connected recipients."
  @spec publish_notification_delivery(notification_delivery_outcome() | [notification_delivery_outcome()]) :: :ok
  defdelegate publish_notification_delivery(outcome), to: Notifications, as: :publish_committed
end
