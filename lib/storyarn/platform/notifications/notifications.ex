defmodule Storyarn.Platform.Notifications do
  @moduledoc """
  Durable in-app notifications and recipient-scoped read state.

  Producers insert notifications inside the same transaction as the source
  mutation. They pass the returned outcome to `publish_committed/1` only after
  that outer transaction succeeds. PostgreSQL remains the source of truth;
  PubSub is only a lightweight signal for connected clients to refetch.
  """

  alias Ecto.Changeset
  alias Storyarn.Accounts.Scope
  alias Storyarn.Platform.Notifications.Execution.Delivery
  alias Storyarn.Platform.Notifications.Notification
  alias Storyarn.Platform.Notifications.Projections.ProjectRecord, as: Project
  alias Storyarn.Platform.Notifications.Projections.UserRecord, as: User

  @type delivery_outcome :: Delivery.delivery_outcome()
  @type delivery_error :: :not_found | Changeset.t()
  @type content_action :: :created | :deleted

  @doc """
  Inserts one notification for the scoped recipient without broadcasting.

  Pass `nil` as the actor for system-generated results, including asynchronous
  operations requested by the recipient. When a project is supplied, current
  recipient access is checked before anything is stored.
  """
  @spec deliver(Scope.t(), User.t() | nil, map()) ::
          {:ok, delivery_outcome()} | {:error, delivery_error()}
  defdelegate deliver(recipient_scope, actor, attrs), to: Delivery

  @doc "Inserts one project-scoped notification for the scoped recipient without broadcasting."
  @spec deliver(Scope.t(), User.t() | nil, Project.t(), map()) ::
          {:ok, delivery_outcome()} | {:error, delivery_error()}
  defdelegate deliver(recipient_scope, actor, project, attrs), to: Delivery

  @doc """
  Inserts a requester-only asynchronous outcome without broadcasting.

  A missing requester or revoked project access suppresses delivery instead of
  rolling back the source operation's terminal transition. Producers still
  pass the returned outcome to `publish_committed/1` after their transaction
  succeeds.
  """
  @spec deliver_async_result(Scope.t() | nil, Project.t() | nil, map()) ::
          {:ok, delivery_outcome()} | {:error, Changeset.t()}
  defdelegate deliver_async_result(recipient_scope, project, attrs), to: Delivery

  @doc """
  Inserts an asynchronous outcome using scalar identities.

  Product contexts can keep their own Project and User read models while
  Platform resolves the canonical notification recipients. Parent rows are
  locked in the same Project -> User order used by existing async producers.
  """
  @spec deliver_async_result_by_ids(integer() | nil, integer(), map()) ::
          {:ok, delivery_outcome()} | {:error, Changeset.t()}
  defdelegate deliver_async_result_by_ids(requested_by_id, project_id, attrs), to: Delivery

  @doc """
  Inserts a notification for every other member with effective project access.

  Direct project members and users inheriting access from the workspace are
  unioned and deduplicated. The scoped actor is always excluded. No PubSub
  message is sent until the caller invokes `publish_committed/1`.
  """
  @spec deliver_to_project_members(Scope.t(), Project.t(), map()) ::
          {:ok, delivery_outcome()} | {:error, delivery_error()}
  defdelegate deliver_to_project_members(actor_scope, project, attrs), to: Delivery

  @doc """
  Inserts one structural content notification for every other effective project member.

  The entity identity and action form the stable deduplication key. Producers
  call this inside their source transaction and publish the returned outcome
  only after that transaction commits.
  """
  @spec deliver_content_activity(
          Scope.t(),
          Project.t(),
          content_action(),
          String.t(),
          %{required(:id) => integer(), required(:name) => String.t()}
        ) :: {:ok, delivery_outcome()} | {:error, delivery_error()}
  defdelegate deliver_content_activity(actor_scope, project, action, entity_type, entity),
    to: Delivery

  @doc """
  Inserts structural content activity using a scalar project identity.

  Producers that own their own project read model do not need to exchange a
  project schema with the notification context. Platform resolves and
  authorizes its local projection before applying the same delivery contract.
  """
  @spec deliver_content_activity_by_project_id(
          Scope.t(),
          integer(),
          content_action(),
          String.t(),
          %{required(:id) => integer(), required(:name) => String.t()}
        ) :: {:ok, delivery_outcome()} | {:error, delivery_error()}
  defdelegate deliver_content_activity_by_project_id(
                actor_scope,
                project_id,
                action,
                entity_type,
                entity
              ),
              to: Delivery

  @doc """
  Inserts structural content activity using scalar actor and project identities.

  This is the boundary-safe contract for product contexts that own local read
  models instead of importing Accounts or Projects schemas.
  """
  @spec deliver_content_activity_by_ids(
          integer(),
          integer(),
          content_action(),
          String.t(),
          %{required(:id) => integer(), required(:name) => String.t()}
        ) :: {:ok, delivery_outcome()} | {:error, delivery_error()}
  defdelegate deliver_content_activity_by_ids(actor_id, project_id, action, entity_type, entity),
    to: Delivery

  @doc """
  Lists the scoped user's recent, currently visible notifications.

  Supported options are `:unread_only` and `:limit`. The default limit is 20
  and values are capped at 100.
  """
  @spec list_notifications(Scope.t(), keyword()) :: [Notification.t()]
  defdelegate list_notifications(scope, opts \\ []), to: Delivery

  @doc "Returns the scoped user's count of currently visible unread notifications."
  @spec unread_count(Scope.t()) :: non_neg_integer()
  defdelegate unread_count(scope), to: Delivery

  @doc "Marks one currently visible notification as read."
  @spec mark_read(Scope.t(), integer()) :: {:ok, Notification.t()} | {:error, :not_found}
  defdelegate mark_read(scope, notification_id), to: Delivery

  @doc "Marks all currently visible unread notifications for the scoped user as read."
  @spec mark_all_read(Scope.t()) :: {:ok, non_neg_integer()}
  defdelegate mark_all_read(scope), to: Delivery

  @doc "Subscribes the current process to notification invalidations for the scoped user."
  @spec subscribe(Scope.t()) :: :ok | {:error, :not_found}
  defdelegate subscribe(scope), to: Delivery

  @doc """
  Publishes invalidations for notifications created by a committed transaction.

  Suppressed and deduplicated outcomes are intentionally silent. This function
  raises when called from an open production transaction so a producer cannot
  accidentally publish state that may still roll back.
  """
  @spec publish_committed(delivery_outcome() | [delivery_outcome()]) :: :ok
  defdelegate publish_committed(outcomes), to: Delivery

  @doc false
  defdelegate user_topic(user_id), to: Delivery
end
