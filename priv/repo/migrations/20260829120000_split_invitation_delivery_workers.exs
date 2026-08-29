defmodule Storyarn.Repo.Migrations.SplitInvitationDeliveryWorkers do
  @moduledoc """
  Moves incomplete invitation delivery jobs from the cross-context Platform
  worker to the worker owned by the invitation's bounded context.

  The exclusive lock makes the rewrite and its routing fence one atomic
  cutover. A dedicated queue prevents an older application node from claiming
  a job whose worker module it does not know. A database ingress router rewrites
  legacy jobs inserted by an older node while a rolling deployment is replacing
  it. Executing jobs fail the migration closed because changing their persisted
  identity while they run would make retry and cancellation semantics ambiguous.
  """

  use Ecto.Migration

  @legacy_worker "Storyarn.Workers.DeliverInvitationWorker"
  @project_worker "Storyarn.Workers.DeliverProjectInvitationWorker"
  @workspace_worker "Storyarn.Workers.DeliverWorkspaceInvitationWorker"
  @new_queue "invitation_delivery"
  @legacy_queue "default"
  @incomplete_states ~w(suspended available scheduled executing retryable)
  @routing_constraint "oban_jobs_invitation_worker_routing"
  @rollback_constraint "oban_jobs_invitation_worker_rollback_fence"
  @routing_function "storyarn_route_legacy_invitation_delivery_job"
  @routing_trigger "storyarn_route_legacy_invitation_delivery_job"

  def up do
    {schema, jobs} = qualified_jobs_table!()

    lock_jobs!(jobs)
    drop_rollback_fence!(jobs)
    assert_no_executing_workers!(jobs, [@legacy_worker], "legacy")
    route_legacy_jobs!(jobs)
    cancel_unknown_legacy_jobs!(jobs)
    install_legacy_ingress_router!(schema, jobs)
    install_routing_fence!(jobs)
  end

  def down do
    {schema, jobs} = qualified_jobs_table!()

    lock_jobs!(jobs)

    assert_no_executing_workers!(
      jobs,
      [@project_worker, @workspace_worker],
      "context-owned"
    )

    execute("ALTER TABLE #{jobs} DROP CONSTRAINT #{@routing_constraint}")
    remove_legacy_ingress_router!(schema, jobs)

    restore_legacy_jobs!(jobs, @project_worker, "project")
    restore_legacy_jobs!(jobs, @workspace_worker, "workspace")
    install_rollback_fence!(jobs)
  end

  defp lock_jobs!(jobs) do
    # `oban_jobs` is continuously active. Bound lock acquisition so a release
    # fails visibly instead of waiting indefinitely behind application work.
    repo().query!("SET LOCAL lock_timeout = '5s'")
    repo().query!("LOCK TABLE #{jobs} IN ACCESS EXCLUSIVE MODE")
  end

  defp assert_no_executing_workers!(jobs, workers, label) do
    quoted_workers = Enum.map_join(workers, ", ", &quote_literal/1)

    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM #{jobs}
        WHERE worker IN (#{quoted_workers})
          AND state = 'executing'
      ) THEN
        RAISE EXCEPTION
          'invitation delivery worker cutover requires every #{label} invitation job to stop executing before retrying'
          USING ERRCODE = 'object_not_in_prerequisite_state';
      END IF;
    END;
    $$
    """)
  end

  defp route_legacy_jobs!(jobs) do
    for {context, worker} <- [
          {"project", @project_worker},
          {"workspace", @workspace_worker}
        ] do
      execute("""
      UPDATE #{jobs}
      SET worker = #{quote_literal(worker)},
          queue = #{quote_literal(@new_queue)}
      WHERE worker = #{quote_literal(@legacy_worker)}
        AND state IN (#{incomplete_states_sql()})
        AND args ->> 'context' = #{quote_literal(context)}
      """)
    end
  end

  defp cancel_unknown_legacy_jobs!(jobs) do
    execute("""
    UPDATE #{jobs}
    SET state = 'cancelled',
        cancelled_at = COALESCE(cancelled_at, timezone('UTC', clock_timestamp()))
    WHERE worker = #{quote_literal(@legacy_worker)}
      AND state IN (#{incomplete_states_sql()})
      AND COALESCE(args ->> 'context', '') NOT IN ('project', 'workspace')
    """)
  end

  defp install_legacy_ingress_router!(schema, jobs) do
    function = ~s(#{schema}."#{@routing_function}")

    execute("""
    CREATE FUNCTION #{function}()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF NEW.worker = #{quote_literal(@legacy_worker)}
         AND NEW.state IN (#{incomplete_states_sql()}) THEN
        CASE NEW.args ->> 'context'
          WHEN 'project' THEN
            NEW.worker := #{quote_literal(@project_worker)};
            NEW.queue := #{quote_literal(@new_queue)};
          WHEN 'workspace' THEN
            NEW.worker := #{quote_literal(@workspace_worker)};
            NEW.queue := #{quote_literal(@new_queue)};
          ELSE
            NULL;
        END CASE;
      END IF;

      RETURN NEW;
    END;
    $$
    """)

    execute("""
    CREATE TRIGGER #{@routing_trigger}
    BEFORE INSERT OR UPDATE OF worker, state, queue, args
    ON #{jobs}
    FOR EACH ROW
    EXECUTE FUNCTION #{function}()
    """)
  end

  defp remove_legacy_ingress_router!(schema, jobs) do
    function = ~s(#{schema}."#{@routing_function}")

    execute("DROP TRIGGER #{@routing_trigger} ON #{jobs}")
    execute("DROP FUNCTION #{function}()")
  end

  defp install_routing_fence!(jobs) do
    execute("""
    ALTER TABLE #{jobs}
    ADD CONSTRAINT #{@routing_constraint}
    CHECK (
      state NOT IN (#{incomplete_states_sql()}) OR
      (
        worker IS DISTINCT FROM #{quote_literal(@legacy_worker)} AND
        (
          worker IS DISTINCT FROM #{quote_literal(@project_worker)} OR
          (
            queue IS NOT DISTINCT FROM #{quote_literal(@new_queue)} AND
            args ->> 'context' IS NOT DISTINCT FROM 'project'
          )
        ) AND
        (
          worker IS DISTINCT FROM #{quote_literal(@workspace_worker)} OR
          (
            queue IS NOT DISTINCT FROM #{quote_literal(@new_queue)} AND
            args ->> 'context' IS NOT DISTINCT FROM 'workspace'
          )
        )
      )
    )
    """)
  end

  defp drop_rollback_fence!(jobs) do
    execute("ALTER TABLE #{jobs} DROP CONSTRAINT IF EXISTS #{@rollback_constraint}")
  end

  defp install_rollback_fence!(jobs) do
    execute("""
    ALTER TABLE #{jobs}
    ADD CONSTRAINT #{@rollback_constraint}
    CHECK (
      state NOT IN (#{incomplete_states_sql()}) OR
      worker NOT IN (
        #{quote_literal(@project_worker)},
        #{quote_literal(@workspace_worker)}
      )
    )
    """)
  end

  defp restore_legacy_jobs!(jobs, worker, context) do
    execute("""
    UPDATE #{jobs}
    SET worker = #{quote_literal(@legacy_worker)},
        queue = #{quote_literal(@legacy_queue)},
        args = jsonb_set(
          COALESCE(args, '{}'::jsonb),
          '{context}',
          to_jsonb(#{quote_literal(context)}::text),
          true
        )
    WHERE worker = #{quote_literal(worker)}
    """)
  end

  defp qualified_jobs_table! do
    current_prefix =
      case repo().query!("SELECT current_schema()").rows do
        [[value]] ->
          validate_prefix!(value)

        invalid ->
          raise Ecto.MigrationError, "Invalid current migration prefix: #{inspect(invalid)}"
      end

    requested_prefix = validate_prefix!(prefix() || current_prefix)

    if requested_prefix == current_prefix do
      schema = ~s("#{current_prefix}")
      {schema, ~s(#{schema}."oban_jobs")}
    else
      raise Ecto.MigrationError,
            "Invitation worker cutover requires its explicit prefix to match current_schema(); requested #{inspect(requested_prefix)}, current #{inspect(current_prefix)}"
    end
  end

  defp validate_prefix!(value) when is_binary(value) and byte_size(value) > 0 do
    if Regex.match?(~r/\A[A-Za-z_][A-Za-z0-9_$]*\z/, value) do
      value
    else
      raise Ecto.MigrationError, "Unsafe invitation worker cutover prefix: #{inspect(value)}"
    end
  end

  defp validate_prefix!(value) do
    raise Ecto.MigrationError, "Invalid invitation worker cutover prefix: #{inspect(value)}"
  end

  defp incomplete_states_sql do
    Enum.map_join(@incomplete_states, ", ", &quote_literal/1)
  end

  defp quote_literal(value), do: "'#{String.replace(value, "'", "''")}'"
end
