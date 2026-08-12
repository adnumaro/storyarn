defmodule Storyarn.Notifications do
  @moduledoc """
  Durable in-app notifications and recipient-scoped read state.

  Producers insert notifications inside the same transaction as the source
  mutation. They pass the returned outcome to `publish_committed/1` only after
  that outer transaction succeeds. PostgreSQL remains the source of truth;
  PubSub is only a lightweight signal for connected clients to refetch.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.Notifications.Notification
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Workspaces.WorkspaceMembership

  @default_limit 20
  @max_limit 100

  @type delivery_outcome ::
          {:created, Notification.t()}
          | {:created, [Notification.t()]}
          | :deduplicated
          | :suppressed

  @type delivery_error :: :not_found | Changeset.t()

  @doc """
  Inserts one notification for the scoped recipient without broadcasting.

  Pass `nil` as the actor for system-generated results, including asynchronous
  operations requested by the recipient. When a project is supplied, current
  recipient access is checked before anything is stored.
  """
  @spec deliver(Scope.t(), User.t() | nil, map()) ::
          {:ok, delivery_outcome()} | {:error, delivery_error()}
  def deliver(%Scope{} = recipient_scope, actor, attrs) when is_map(attrs) do
    deliver(recipient_scope, actor, nil, attrs)
  end

  @doc """
  Inserts one project-scoped notification for the scoped recipient without broadcasting.
  """
  @spec deliver(Scope.t(), User.t() | nil, Project.t(), map()) ::
          {:ok, delivery_outcome()} | {:error, delivery_error()}
  def deliver(%Scope{user: %User{} = recipient} = recipient_scope, actor, %Project{} = project, attrs)
      when is_map(attrs) do
    if self_notification?(recipient, actor) do
      {:ok, :suppressed}
    else
      case Projects.get_project(recipient_scope, project.id) do
        {:ok, authorized_project, _membership} ->
          insert_one(recipient, actor, authorized_project, attrs)

        {:error, _reason} ->
          {:error, :not_found}
      end
    end
  end

  def deliver(%Scope{user: %User{} = recipient}, actor, nil, attrs) when is_map(attrs) do
    if self_notification?(recipient, actor) do
      {:ok, :suppressed}
    else
      insert_one(recipient, actor, nil, attrs)
    end
  end

  def deliver(%Scope{}, _actor, _project, _attrs), do: {:error, :not_found}

  @doc """
  Inserts a notification for every other member with effective project access.

  Direct project members and users inheriting access from the workspace are
  unioned and deduplicated. The scoped actor is always excluded. No PubSub
  message is sent until the caller invokes `publish_committed/1`.
  """
  @spec deliver_to_project_members(Scope.t(), Project.t(), map()) ::
          {:ok, delivery_outcome()} | {:error, delivery_error()}
  def deliver_to_project_members(%Scope{user: %User{} = actor} = actor_scope, %Project{} = project, attrs)
      when is_map(attrs) do
    case Projects.get_project(actor_scope, project.id) do
      {:ok, authorized_project, _membership} ->
        insert_for_effective_members(actor, authorized_project, attrs)

      {:error, _reason} ->
        {:error, :not_found}
    end
  end

  def deliver_to_project_members(%Scope{}, %Project{}, _attrs), do: {:error, :not_found}

  @doc """
  Lists the scoped user's recent, currently visible notifications.

  Supported options are `:unread_only` and `:limit`. The default limit is 20
  and values are capped at 100.
  """
  @spec list_notifications(Scope.t(), keyword()) :: [Notification.t()]
  def list_notifications(scope, opts \\ [])

  def list_notifications(%Scope{user: %User{}} = scope, opts) when is_list(opts) do
    scope
    |> visible_query()
    |> maybe_only_unread(Keyword.get(opts, :unread_only, false))
    |> order_by([notification], desc: notification.inserted_at, desc: notification.id)
    |> limit(^normalize_limit(Keyword.get(opts, :limit, @default_limit)))
    |> Repo.all()
  end

  def list_notifications(%Scope{}, _opts), do: []

  @doc "Returns the scoped user's count of currently visible unread notifications."
  @spec unread_count(Scope.t()) :: non_neg_integer()
  def unread_count(%Scope{user: %User{}} = scope) do
    scope
    |> visible_query()
    |> where([notification], is_nil(notification.read_at))
    |> Repo.aggregate(:count, :id)
  end

  def unread_count(%Scope{}), do: 0

  @doc "Marks one currently visible notification as read."
  @spec mark_read(Scope.t(), integer()) :: {:ok, Notification.t()} | {:error, :not_found}
  def mark_read(%Scope{user: %User{id: user_id}} = scope, notification_id)
      when is_integer(notification_id) and notification_id > 0 do
    ensure_outside_transaction!("mark_read/2")

    result =
      Repo.transact(fn ->
        visible_notification_ids =
          scope
          |> visible_query()
          |> where([item], item.id == ^notification_id)
          |> select([item], item.id)

        {updated_count, _rows} =
          Notification
          |> where(
            [item],
            item.id in subquery(visible_notification_ids) and is_nil(item.read_at)
          )
          |> Repo.update_all(set: [read_at: TimeHelpers.now()])

        notification =
          scope
          |> visible_query()
          |> where([item], item.id == ^notification_id)
          |> Repo.one()

        case {notification, updated_count} do
          {nil, _count} ->
            {:error, :not_found}

          {%Notification{} = read, 1} ->
            {:ok, {read, true}}

          {%Notification{} = read, 0} ->
            {:ok, {read, false}}
        end
      end)

    case result do
      {:ok, {notification, true}} ->
        broadcast_users([user_id])
        {:ok, notification}

      {:ok, {notification, false}} ->
        {:ok, notification}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def mark_read(%Scope{}, _notification_id), do: {:error, :not_found}

  @doc "Marks all currently visible unread notifications for the scoped user as read."
  @spec mark_all_read(Scope.t()) :: {:ok, non_neg_integer()}
  def mark_all_read(%Scope{user: %User{id: user_id}} = scope) do
    ensure_outside_transaction!("mark_all_read/1")

    result =
      Repo.transact(fn ->
        visible_unread_ids =
          scope
          |> visible_query()
          |> where([notification], is_nil(notification.read_at))
          |> select([notification], notification.id)

        {count, _rows} =
          Notification
          |> where([notification], notification.id in subquery(visible_unread_ids))
          |> Repo.update_all(set: [read_at: TimeHelpers.now()])

        {:ok, count}
      end)

    case result do
      {:ok, count} when count > 0 ->
        broadcast_users([user_id])
        {:ok, count}

      {:ok, count} ->
        {:ok, count}
    end
  end

  def mark_all_read(%Scope{}), do: {:ok, 0}

  @doc "Subscribes the current process to notification invalidations for the scoped user."
  @spec subscribe(Scope.t()) :: :ok | {:error, :not_found}
  def subscribe(%Scope{user: %User{id: user_id}}) do
    Phoenix.PubSub.subscribe(Storyarn.PubSub, user_topic(user_id))
  end

  def subscribe(%Scope{}), do: {:error, :not_found}

  @doc """
  Publishes invalidations for notifications created by a committed transaction.

  Suppressed and deduplicated outcomes are intentionally silent. This function
  raises when called from an open production transaction so a producer cannot
  accidentally publish state that may still roll back.
  """
  @spec publish_committed(delivery_outcome() | [delivery_outcome()]) :: :ok
  def publish_committed(outcomes) do
    ensure_outside_transaction!("publish_committed/1")

    outcomes
    |> created_notifications()
    |> Enum.map(& &1.recipient_id)
    |> broadcast_users()
  end

  @doc false
  def user_topic(user_id) when is_integer(user_id), do: "notifications:user:#{user_id}"

  defp insert_one(recipient, actor, project, attrs) do
    %Notification{
      recipient_id: recipient.id,
      actor_id: actor_id(actor),
      project_id: project_id(project)
    }
    |> Notification.create_changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:recipient_id, :dedupe_key],
      returning: true
    )
    |> case do
      {:ok, %Notification{id: nil}} -> {:ok, :deduplicated}
      {:ok, %Notification{} = notification} -> {:ok, {:created, notification}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp insert_for_effective_members(actor, project, attrs) do
    with {:ok, validated} <- validate_fanout_attrs(actor, project, attrs) do
      now = TimeHelpers.now()
      kind = validated.kind
      entity_type = validated.entity_type
      entity_id = validated.entity_id
      entity_name = validated.entity_name
      status = validated.status
      dedupe_key = validated.dedupe_key

      rows_query =
        project
        |> effective_recipient_ids(actor.id)
        |> select([recipient], %{
          recipient_id: recipient.user_id,
          actor_id: ^actor.id,
          project_id: ^project.id,
          kind: ^kind,
          entity_type: ^entity_type,
          entity_id: ^entity_id,
          entity_name: ^entity_name,
          status: ^status,
          dedupe_key: ^dedupe_key,
          inserted_at: ^now
        })

      {_count, notifications} =
        Repo.insert_all(Notification, rows_query,
          on_conflict: :nothing,
          conflict_target: [:recipient_id, :dedupe_key],
          returning: true
        )

      {:ok, {:created, notifications}}
    end
  end

  defp validate_fanout_attrs(actor, project, attrs) do
    %Notification{recipient_id: -1, actor_id: actor.id, project_id: project.id}
    |> Notification.create_changeset(attrs)
    |> Changeset.apply_action(:insert)
  end

  defp effective_recipient_ids(project, actor_id) do
    direct_members =
      from(membership in ProjectMembership,
        where: membership.project_id == ^project.id,
        select: %{user_id: membership.user_id}
      )

    workspace_members =
      from(membership in WorkspaceMembership,
        where: membership.workspace_id == ^project.workspace_id,
        select: %{user_id: membership.user_id}
      )

    direct_members
    |> union(^workspace_members)
    |> subquery()
    |> where([recipient], recipient.user_id != ^actor_id)
  end

  defp visible_query(%Scope{user: %User{id: user_id}}) do
    from(notification in Notification,
      left_join: project in Project,
      on: project.id == notification.project_id,
      left_join: project_membership in ProjectMembership,
      on: project_membership.project_id == project.id and project_membership.user_id == ^user_id,
      left_join: workspace_membership in WorkspaceMembership,
      on: workspace_membership.workspace_id == project.workspace_id and workspace_membership.user_id == ^user_id,
      where:
        notification.recipient_id == ^user_id and
          (is_nil(notification.project_id) or
             (not is_nil(project.id) and is_nil(project.deleted_at) and
                (not is_nil(project_membership.id) or not is_nil(workspace_membership.id))))
    )
  end

  defp maybe_only_unread(query, true), do: where(query, [notification], is_nil(notification.read_at))
  defp maybe_only_unread(query, _other), do: query

  defp normalize_limit(limit) when is_integer(limit) and limit > 0, do: min(limit, @max_limit)
  defp normalize_limit(_invalid), do: @default_limit

  defp self_notification?(%User{id: user_id}, %User{id: user_id}), do: true
  defp self_notification?(%User{}, %User{}), do: false
  defp self_notification?(%User{}, nil), do: false

  defp actor_id(%User{id: id}), do: id
  defp actor_id(nil), do: nil

  defp project_id(%Project{id: id}), do: id
  defp project_id(nil), do: nil

  defp created_notifications({:created, %Notification{} = notification}), do: [notification]
  defp created_notifications({:created, notifications}) when is_list(notifications), do: notifications
  defp created_notifications(:deduplicated), do: []
  defp created_notifications(:suppressed), do: []

  defp created_notifications(outcomes) when is_list(outcomes) do
    Enum.flat_map(outcomes, &created_notifications/1)
  end

  defp ensure_outside_transaction!(operation) do
    if Repo.in_transaction?() do
      raise ArgumentError, "#{operation} must be called outside an open transaction"
    end
  end

  defp broadcast_users(user_ids) do
    user_ids
    |> Enum.uniq()
    |> Enum.each(fn user_id ->
      Phoenix.PubSub.broadcast(Storyarn.PubSub, user_topic(user_id), :notifications_changed)
    end)

    :ok
  end
end
