# ENG-52 operational recovery validation

> Owner: Engineering
>
> Last reviewed: 2026-09-04
>
> Source of truth: ENG-52, `docs/reference/versioning-containment.md`, dated
> deployed-release and provider validation, and the evidence links recorded
> below

This record captures sanitized, point-in-time evidence for the operational
recovery contract. It is not a substitute for the durable records in the
database or providers, and one successful check does not prove future
availability or integrity.

## Evidence handling

Record only the minimum aggregate result needed to prove the control. Never
copy project or workspace IDs, user identifiers, filenames, imported content,
storage keys, bucket or host names, upload IDs, signed URLs, database connection
details, credentials, raw job arguments, or raw exception messages into this
document, dashboards, GitHub, or Linear.

The operator field in shared evidence must use an internal incident/audit
reference, not a person's name or email. Raw provider evidence, when retention
is required, belongs only in the access-controlled provider or incident system;
link to it rather than copying it.

## Production observations on 2026-09-02

Environment: production application, real Tigris principal and namespace.
Deployed code: `0172ff9a`. Deployment evidence:
[successful Fly deployment](https://github.com/adnumaro/storyarn/actions/runs/33676061134).

| Control                                      | Sanitized procedure                                                                                                                                                                             | Observed result                                                                                                                                                                                     | What it does not prove                                                                                          |
| -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Ready snapshot archive                       | Public read-only `Storyarn.Projects.run_snapshot_archive_smoke!/1` entrypoint                                                                                                                   | The selected snapshot was `ready` and `verified`. It passed multipart inventory for the selected exact keys, full GET, incremental byte count and SHA-256, private response headers, and Range GET. | Restore, future object durability, hostile same-key overwrite protection, or global multipart inventory.        |
| Tigris native incomplete-multipart lifecycle | Applied an abort-only lifecycle proposal to the real bucket, then read the configuration again.                                                                                                 | Rejected with HTTP 400, provider code `InvalidRequest`: `Lifecycle only supports expiration rule. Expiration rule with content days or dates only.` The lifecycle configuration remained empty.     | There is no provider-side automatic abort control. Completed-object expiration is not an acceptable substitute. |
| Multipart permissions and cleanup primitives | Created one disposable incomplete upload, uploaded a small part, listed uploads and parts, aborted it, then verified provider state. Cleanup was attempted even if an intermediate step failed. | Create, upload-part, list-uploads, list-parts, and abort all succeeded. The upload and parts were absent afterward, and no completed object existed.                                                | The application-path durable receipt, two-pass quiescence protocol, retries, or global drift.                   |
| Observation-only reconciliation              | Started through `Storyarn.Platform.Release`, waited for completion, then inspected the immutable result.                                                                                        | Completed with zero findings in the supported scan. `multipart_inventory_state = unsupported` and `physical_inventory_complete = false`.                                                            | Zero findings is not evidence that global multipart drift is zero or that physical inventory is complete.       |

Only the deployment has an immutable evidence link above. The ad-hoc release
and provider command outputs do not yet have an access-controlled artifact link,
so these observations alone do not satisfy ENG-52's closure evidence.

The lifecycle rejection may be accepted as a provider limitation only when the
exact-key compensating control in
[versioning containment](versioning-containment.md#real-tigris-validation) is
demonstrated and monitored. It is not a waived risk.

## Controls still requiring evidence

These items are not completed by the observations above and remain tracked in
ENG-52:

- After ENG-116 is deployed, run exact-key multipart cleanup through the
  application path, prove the durable receipt survives the complete quiescence
  protocol, and finish with no overdue cleanup backlog or provider residue.
- For ENG-117, validate the server-controlled upload path merged in PR #115:
  success, repeated cancellation, interrupted transfer, expiry, and both
  upload/cleanup race orders. Verify that every outcome converges to one accepted
  object or an absent key with durable cleanup ownership. New uploads no longer
  issue protected presigned PUTs, so browser `If-Match`, CORS and bearer replay
  are not acceptance criteria for this path. Previously issued URLs still need
  the containment described in `versioning-containment.md`. Verify that cleanup
  retains the original provider namespace and refuses a different one.
  Upload owners created before namespace pinning remain blocked if their original
  identity is unknown; do not backfill it from current configuration or delete
  their records before verifying ownership of the retained bytes.
- Restore a disposable project exactly after removing its live asset bytes, and
  compare the complete project and asset inventory.
- Exercise recovery ZIP import and verify its cleanup on success, cancellation,
  retry exhaustion, and controlled failure.
- Exercise Yarn replacement, its recovery snapshot, and exact restoration on a
  disposable project.
- Deploy the low-cardinality recovery metrics, connect a real reporter, and
  demonstrate dashboards and actionable alerts for all eight operational
  recovery and inventory queues, cleanup backlog, reconciliation, restores,
  imports, and storage failures. Restart one
  metrics process and prove the reconciliation gauges rehydrate from the latest
  durable completed run while its source-run age remains unchanged.
- Keep the Prometheus listener on private port `9091`; do not expose it as a Fly
  public service. Prove that the complete provider namespace emits a fresh observation,
  that a failed poll and a terminal Yarn import are actionable, and that the
  installed rules exercise one sanitized firing and recovery through the owned
  notification receiver.
- Add a durable polling projection or persisted outbox for terminal Yarn
  execution, Yarn expiration, snapshot-import, failed reconciliation, and
  failed/manual repair outcomes. Their current counters are best-effort edge
  signals and can be missed if a process dies after the domain transaction
  commits but before telemetry is emitted. The completed-run projection does
  not cover failed runs or repair actions. Prove replay or rehydration after
  restart before claiming complete terminal coverage.
- Deploy and exercise the read-only global multipart inventory through
  `Storyarn.Projects.inspect_storage_multipart_inventory/0`, then prove its
  reporter and alert. It must not abort uploads without durable exact-key
  ownership.
- Validate the global inventory against real Tigris with an empty-prefix
  `ListMultipartUploads` permission and at least one pagination boundary. Prove
  that URL-encoded keys and continuation markers are decoded correctly and that
  the 10,000-upload, 100-page, and 2 MiB response limits fail closed without
  exposing keys or provider response bodies.
- Complete an isolated Neon PITR drill, record measured RPO/RTO, and reconcile
  the recovered database with the unchanged object namespace.
- Verify the external durable copy and its restore procedure. Neither its
  existence nor its recoverability has been demonstrated here.

Do not close ENG-52 or describe recovery as production-ready while any required
control lacks dated evidence and an access-controlled evidence link. The
dashboard, notification receiver, installed alert rules, and firing/recovery
evidence are still pending; the runbook's PromQL is a required contract, not
evidence that those controls are deployed.

## Sanitized evidence template

Use this template for every drill step:

```text
Ticket: ENG-52
Evidence date/time (UTC):
Environment: production | isolated production clone | staging
Deployed commit/image reference:
Operator reference: <incident or audit ID; no name or email>
Control exercised:
Public application/release entrypoint:
Expected invariant:
Sanitized result: pass | fail | blocked
Aggregate counts/booleans only:
Duration and measured RPO/RTO, when applicable:
Cleanup residue: uploads=<count>, parts=<count>, objects=<count>, overdue_receipts=<count>
Inventory boundary: multipart_inventory_state=<value>, physical_inventory_complete=<boolean>
Residual risk:
Follow-up owner role and deadline:
Access-controlled evidence link:
```

Before sharing, search the evidence for connection strings, bearer or signed
URLs, secrets, storage keys, bucket/host names, upload IDs, project, workspace,
or user identifiers, filenames, imported content, job arguments, and exception
messages. Redact or replace them with aggregate counts. If sanitization cannot
be proven, do not publish the evidence.
