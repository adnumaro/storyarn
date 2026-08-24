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
  alias Storyarn.Billing.Persistence.ProjectMembershipRecord, as: ProjectMembership
  alias Storyarn.Billing.Persistence.ProjectRecord, as: Project
  alias Storyarn.Billing.Persistence.WorkspaceMembershipRecord, as: WorkspaceMembership
  alias Storyarn.Notifications.Notification
  alias Storyarn.Notifications.Persistence.UserRecord, as: User
  alias Storyarn.Notifications.ProjectAccess
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  @default_limit 20
  @max_limit 100
  @content_entity_types ~w(sheet flow scene localization_language)
  @content_activity_marker_table "notification_content_activity_markers"

  @type delivery_outcome ::
          {:created, Notification.t()}
          | {:created, [Notification.t()]}
          | :deduplicated
          | :suppressed

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
  def deliver(%{user: _} = recipient_scope, actor, attrs) when is_map(attrs) do
    deliver(recipient_scope, actor, nil, attrs)
  end

  @doc """
  Inserts one project-scoped notification for the scoped recipient without broadcasting.
  """
  @spec deliver(Scope.t(), User.t() | nil, Project.t(), map()) ::
          {:ok, delivery_outcome()} | {:error, delivery_error()}
  def deliver(%{user: %{id: _} = recipient} = recipient_scope, actor, %{id: _} = project, attrs) when is_map(attrs) do
    if self_notification?(recipient, actor) do
      {:ok, :suppressed}
    else
      case ProjectAccess.get_project(recipient_scope, project.id) do
        {:ok, authorized_project, _membership} ->
          insert_one(recipient, actor, authorized_project, attrs)

        {:error, _reason} ->
          {:error, :not_found}
      end
    end
  end

  def deliver(%{user: %{id: _} = recipient}, actor, nil, attrs) when is_map(attrs) do
    if self_notification?(recipient, actor) do
      {:ok, :suppressed}
    else
      insert_one(recipient, actor, nil, attrs)
    end
  end

  def deliver(%{user: _}, _actor, _project, _attrs), do: {:error, :not_found}

  @doc """
  Inserts a requester-only asynchronous outcome without broadcasting.

  A missing requester or revoked project access suppresses delivery instead of
  rolling back the source operation's terminal transition. Producers still
  pass the returned outcome to `publish_committed/1` after their transaction
  succeeds.
  """
  @spec deliver_async_result(Scope.t() | nil, Project.t() | nil, map()) ::
          {:ok, delivery_outcome()} | {:error, Changeset.t()}
  def deliver_async_result(nil, _project, attrs) when is_map(attrs) do
    ensure_inside_transaction!("deliver_async_result/3")
    {:ok, :suppressed}
  end

  def deliver_async_result(%{user: _} = recipient_scope, project, attrs) when is_map(attrs) do
    ensure_inside_transaction!("deliver_async_result/3")
    attrs = Map.put(attrs, :kind, "async_operation")

    case deliver(recipient_scope, nil, project, attrs) do
      {:error, :not_found} -> {:ok, :suppressed}
      result -> result
    end
  end

  @doc """
  Inserts an asynchronous outcome using scalar identities.

  Product contexts can keep their own Project and User read models while
  Platform resolves the canonical notification recipients. Parent rows are
  locked in the same Project -> User order used by existing async producers.
  """
  @spec deliver_async_result_by_ids(integer() | nil, integer(), map()) ::
          {:ok, delivery_outcome()} | {:error, Changeset.t()}
  def deliver_async_result_by_ids(requested_by_id, project_id, attrs) when is_map(attrs) do
    ensure_inside_transaction!("deliver_async_result_by_ids/3")

    with %Project{} = project <- lock_async_project(project_id),
         %User{} = requester <- lock_async_requester(requested_by_id) do
      deliver_async_result(%{user: requester}, project, attrs)
    else
      _missing_parent -> {:ok, :suppressed}
    end
  end

  @doc """
  Inserts a notification for every other member with effective project access.

  Direct project members and users inheriting access from the workspace are
  unioned and deduplicated. The scoped actor is always excluded. No PubSub
  message is sent until the caller invokes `publish_committed/1`.
  """
  @spec deliver_to_project_members(Scope.t(), Project.t(), map()) ::
          {:ok, delivery_outcome()} | {:error, delivery_error()}
  def deliver_to_project_members(%{user: %{id: _} = actor} = actor_scope, %{id: _, workspace_id: _} = project, attrs)
      when is_map(attrs) do
    with {:ok, authorized_project} <- authorize_project(actor_scope, project) do
      insert_for_effective_members(actor, authorized_project, attrs)
    end
  end

  def deliver_to_project_members(%{user: _}, %{id: _, workspace_id: _}, _attrs), do: {:error, :not_found}

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
  def deliver_content_activity(
        %{user: %{id: _} = actor} = actor_scope,
        %{id: _, workspace_id: _} = project,
        action,
        entity_type,
        %{id: entity_id, name: entity_name}
      )
      when action in [:created, :deleted] and entity_type in @content_entity_types and is_integer(entity_id) and
             is_binary(entity_name) do
    ensure_inside_transaction!("deliver_content_activity/5")

    attrs = %{
      kind: "content_#{action}",
      entity_type: entity_type,
      entity_id: entity_id,
      entity_name: entity_name,
      dedupe_key: "structural-content:v1:#{project.id}:#{entity_type}:#{entity_id}:#{action}"
    }

    with {:ok, authorized_project} <- authorize_project(actor_scope, project),
         {:ok, validated} <- validate_fanout_attrs(actor, authorized_project, attrs) do
      if claim_content_activity(authorized_project, action, entity_type, entity_id) do
        insert_validated_for_effective_members(actor, authorized_project, validated)
      else
        {:ok, {:created, []}}
      end
    end
  end

  def deliver_content_activity(%{user: _}, %{id: _, workspace_id: _}, action, entity_type, %{
        id: entity_id,
        name: entity_name
      })
      when action in [:created, :deleted] and entity_type in @content_entity_types and is_integer(entity_id) and
             is_binary(entity_name) do
    ensure_inside_transaction!("deliver_content_activity/5")
    {:error, :not_found}
  end

  @doc """
  Inserts structural content activity using a scalar project identity.

  Producers that own their own project read model do not need to exchange a
  `Storyarn.Projects.Project` schema with the notification context. This
  function resolves and authorizes the canonical project internally before
  applying the same delivery contract as `deliver_content_activity/5`.
  """
  @spec deliver_content_activity_by_project_id(
          Scope.t(),
          integer(),
          content_action(),
          String.t(),
          %{required(:id) => integer(), required(:name) => String.t()}
        ) :: {:ok, delivery_outcome()} | {:error, delivery_error()}
  def deliver_content_activity_by_project_id(%{user: _} = actor_scope, project_id, action, entity_type, entity)
      when is_integer(project_id) do
    ensure_inside_transaction!("deliver_content_activity_by_project_id/5")

    case ProjectAccess.get_project(actor_scope, project_id) do
      {:ok, project, _membership} ->
        deliver_content_activity(actor_scope, project, action, entity_type, entity)

      {:error, _reason} ->
        {:error, :not_found}
    end
  end

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
  def deliver_content_activity_by_ids(actor_id, project_id, action, entity_type, entity)
      when is_integer(actor_id) and is_integer(project_id) do
    ensure_inside_transaction!("deliver_content_activity_by_ids/5")

    with %Project{} = project <- lock_async_project(project_id),
         %User{} = actor <- lock_async_requester(actor_id) do
      deliver_content_activity(%{user: actor}, project, action, entity_type, entity)
    else
      _missing_parent -> {:error, :not_found}
    end
  end

  @doc """
  Lists the scoped user's recent, currently visible notifications.

  Supported options are `:unread_only` and `:limit`. The default limit is 20
  and values are capped at 100.
  """
  @spec list_notifications(Scope.t(), keyword()) :: [Notification.t()]
  def list_notifications(scope, opts \\ [])

  def list_notifications(%{user: %{id: _}} = scope, opts) when is_list(opts) do
    scope
    |> visible_query()
    |> maybe_only_unread(Keyword.get(opts, :unread_only, false))
    |> order_by([notification], desc: notification.inserted_at, desc: notification.id)
    |> limit(^normalize_limit(Keyword.get(opts, :limit, @default_limit)))
    |> Repo.all()
    |> Repo.preload([:actor, :project])
  end

  def list_notifications(%{user: _}, _opts), do: []

  @doc "Returns the scoped user's count of currently visible unread notifications."
  @spec unread_count(Scope.t()) :: non_neg_integer()
  def unread_count(%{user: %{id: _}} = scope) do
    scope
    |> visible_query()
    |> where([notification], is_nil(notification.read_at))
    |> Repo.aggregate(:count, :id)
  end

  def unread_count(%{user: _}), do: 0

  @doc "Marks one currently visible notification as read."
  @spec mark_read(Scope.t(), integer()) :: {:ok, Notification.t()} | {:error, :not_found}
  def mark_read(%{user: %{id: user_id}} = scope, notification_id)
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

  def mark_read(%{user: _}, _notification_id), do: {:error, :not_found}

  @doc "Marks all currently visible unread notifications for the scoped user as read."
  @spec mark_all_read(Scope.t()) :: {:ok, non_neg_integer()}
  def mark_all_read(%{user: %{id: user_id}} = scope) do
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

  def mark_all_read(%{user: _}), do: {:ok, 0}

  @doc "Subscribes the current process to notification invalidations for the scoped user."
  @spec subscribe(Scope.t()) :: :ok | {:error, :not_found}
  def subscribe(%{user: %{id: user_id}}) do
    Phoenix.PubSub.subscribe(Storyarn.PubSub, user_topic(user_id))
  end

  def subscribe(%{user: _}), do: {:error, :not_found}

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

  defp lock_async_project(project_id) when is_integer(project_id) and project_id > 0 do
    Repo.one(from(project in Project, where: project.id == ^project_id, lock: "FOR SHARE"))
  end

  defp lock_async_project(_project_id), do: nil

  defp lock_async_requester(user_id) when is_integer(user_id) and user_id > 0 do
    Repo.one(from(user in User, where: user.id == ^user_id, lock: "FOR KEY SHARE"))
  end

  defp lock_async_requester(_user_id), do: nil

  defp insert_for_effective_members(actor, project, attrs) do
    with {:ok, validated} <- validate_fanout_attrs(actor, project, attrs) do
      insert_validated_for_effective_members(actor, project, validated)
    end
  end

  defp insert_validated_for_effective_members(actor, project, validated) do
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

  defp validate_fanout_attrs(actor, project, attrs) do
    %Notification{recipient_id: -1, actor_id: actor.id, project_id: project.id}
    |> Notification.create_changeset(attrs)
    |> Changeset.apply_action(:insert)
  end

  defp authorize_project(actor_scope, project) do
    case ProjectAccess.get_project(actor_scope, project.id) do
      {:ok, authorized_project, _membership} -> {:ok, authorized_project}
      {:error, _reason} -> {:error, :not_found}
    end
  end

  defp claim_content_activity(project, action, entity_type, entity_id) do
    {claimed_count, _rows} =
      Repo.insert_all(
        @content_activity_marker_table,
        [
          %{
            project_id: project.id,
            entity_type: entity_type,
            entity_id: entity_id,
            action: Atom.to_string(action),
            inserted_at: TimeHelpers.now()
          }
        ],
        on_conflict: :nothing,
        conflict_target: [:project_id, :entity_type, :entity_id, :action]
      )

    claimed_count == 1
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

  defp visible_query(%{user: %{id: user_id}}) do
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

  defp self_notification?(%{id: user_id}, %{id: user_id}), do: true
  defp self_notification?(%{id: _}, %{id: _}), do: false
  defp self_notification?(%{id: _}, nil), do: false

  defp actor_id(%{id: id}), do: id
  defp actor_id(nil), do: nil

  defp project_id(%{id: id}), do: id
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

  defp ensure_inside_transaction!(operation) do
    if !Repo.in_transaction?() do
      raise ArgumentError, "#{operation} must be called inside an open transaction"
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
