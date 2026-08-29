# Invitation delivery worker cutover

> Owner: Engineering
>
> Last reviewed: 2026-08-29
>
> Scope: ENG-109 deployment and rollback contract

Project and Workspace invitations own separate workers and queue adapters. The
database migration moves incomplete legacy jobs to those owner workers and
routes jobs inserted by an older application node during replacement. This is
a controlled, forward-only cutover; it is not permission to restore the old
cross-context worker in application code.

## Normal deployment

The release migration takes a bounded exclusive lock on `oban_jobs`. It aborts
without changing any row while a legacy invitation job is executing or when it
cannot acquire the lock within five seconds. Let the job or blocking
transaction finish and retry the deploy.

After Oban starts, the replacement application wakes `invitation_delivery`
immediately and every 15 seconds for five minutes. These signals are
best-effort and do not resume an operator-paused queue. They cover both jobs
rewritten by the migration and jobs inserted late by the previous node without
changing the global fifteen-minute Stager interval.

Every new Project or Workspace invitation also sends a second best-effort
signal after its enclosing database transaction has committed. This is
required because the configured process-group notifier is not transactional:
the signal emitted internally by `Oban.insert/1` can arrive while the job is
still invisible to the queue producer. A failed post-commit signal never
changes the successful invitation result; the durable job remains recoverable
by Oban's Stager.

After deployment, this query must return no rows:

```sql
SELECT worker, queue, state, args ->> 'context' AS context, count(*)
FROM oban_jobs
WHERE state IN ('suspended', 'available', 'scheduled', 'executing', 'retryable')
  AND (
    worker = 'Storyarn.Workers.DeliverInvitationWorker'
    OR (worker = 'Storyarn.Workers.DeliverProjectInvitationWorker'
        AND (queue IS DISTINCT FROM 'invitation_delivery'
             OR args ->> 'context' IS DISTINCT FROM 'project'))
    OR (worker = 'Storyarn.Workers.DeliverWorkspaceInvitationWorker'
        AND (queue IS DISTINCT FROM 'invitation_delivery'
             OR args ->> 'context' IS DISTINCT FROM 'workspace'))
  )
GROUP BY worker, queue, state, args ->> 'context';
```

The routing constraint enforces the same invariant for every later write.

## Failed deployment and rollback

An image-only rollback is not valid after the migration commits. The old image
does not poll `invitation_delivery` and does not contain the owner worker
modules. A failed new release therefore requires a fix-forward by default. The
jobs remain durable, but their email delivery waits until the owner workers are
running.

If reverting the database and image is unavoidable:

1. Stop application traffic and every Oban producer from the new image.
2. Using the new image, run the migration down to version `20260829120000`.
3. Verify that no incomplete Project or Workspace owner-worker job remains and
   that the legacy jobs are back on `default`.
4. Only then start the previous image and restore traffic.

The down migration aborts while an owner job is executing. On success it
installs a rollback fence: a stray new producer can no longer persist another
incomplete owner-worker job after the rewrite. Its invitation transaction
fails closed instead of committing work that the old image cannot execute.
Reapplying the up migration removes that fence atomically under the same table
lock.

Do not describe an ordinary Fly image rollback as safe for this cutover, and do
not remove the database ingress router until rollback to every pre-ENG-109
image is deliberately unsupported.
