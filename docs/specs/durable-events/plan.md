# Durable events implementation plan

## Status

Draft for engineering review. [`spec.md`](./spec.md) defines the behavior; this
plan defines the implementation order and proof. Keep this branch plan-only.

Implement each slice as a small stacked PR. Every slice must pass its focused
tests and the full suite before the next slice starts. If implementation changes
the design, update the spec and this plan first.

## Guardrails

- Keep `Strata::Events.durable = false` for the first release.
- Preserve the legacy synchronous path when durability is disabled or the
  event tables are missing.
- Add conditional case transitions before switching delivery to ActiveJob.
- Use one dispatcher for initial delivery, retry, replay, and recovery. Do not
  use ActiveJob `retry_on` for handler failures.
- Enqueue only after the publisher's outermost transaction commits.
- Treat duplicate execution as normal. Before recording a failure in its new
  transaction, lock and re-check that another job has not already completed or
  rescheduled the delivery.
- Payload preflight must exercise host-provided publisher samples before
  rollout. Scanning stored events alone is insufficient because an
  unserializable payload never creates an event row.

## Files that change

### 1. Handler outcomes

Files:

- `app/models/strata/business_process_instance.rb`
- `app/models/strata/business_process.rb`
- `spec/models/strata/business_process_instance_spec.rb`
- `spec/models/strata/business_process_spec.rb`

Return `:transitioned` or `:no_match`, aggregate multi-case results, and emit
one structured outcome log per resolved case. Existing PR #382 supplies most
of this slice; add the structured logging if it is not already present.

Proof:

- Start events return `:transitioned`.
- No matching transition returns `:no_match`.
- Mixed multi-case results return `:transitioned` and log every case outcome.

### 2. Safe synchronous transitions

Files:

- `app/models/strata/business_process_instance.rb`
- `app/models/strata/business_process.rb`
- `app/helpers/strata/event_manager.rb`
- `spec/models/strata/business_process_instance_spec.rb`
- `spec/models/strata/business_process_spec.rb`
- `spec/helpers/strata/event_manager_spec.rb`
- `spec/models/strata/application_form_spec.rb`
- `spec/models/strata/task_spec.rb`

Wrap step mutation and execution in one transaction. Do the same for start-case
creation and first-step execution. Stop swallowing `StandardError`, but add the
temporary publish-boundary rescue so a failed handler does not roll back the
form or task that published the event.

Proof:

- A failed step leaves the case at its prior step and rolls back step writes.
- A failed start leaves no partial case.
- The publishing form or task remains committed.
- Non-`StandardError` exceptions still propagate.

### 3. Durable records with synchronous delivery

Schema and generator files:

- `lib/generators/strata/events/events_generator.rb`
- `lib/generators/strata/events/templates/create_strata_events.rb.tt`
- `lib/generators/strata/events/USAGE`
- `lib/generators/strata/case/case_generator.rb`
- `lib/generators/strata/migration/migration_generator.rb`
- `app/models/strata/case.rb`
- `spec/lib/generators/strata/generators/events_generator_spec.rb`
- `spec/lib/generators/strata/generators/case_generator_spec.rb`
- `spec/lib/generators/strata/generators/migration_generator_spec.rb`
- `spec/dummy/db/migrate/<timestamp>_create_strata_events.rb`
- `spec/dummy/db/schema.rb`

Runtime files:

- `app/models/strata/event.rb`
- `app/models/strata/event_delivery.rb`
- `app/lib/strata/events.rb`
- `app/lib/strata/events/payload.rb`
- `app/lib/strata/events/subscriber_registry.rb`
- `app/lib/strata/events/delivery_runner.rb`
- `app/helpers/strata/event_manager.rb`
- `lib/strata/engine.rb`
- `spec/factories/strata/events.rb`
- `spec/models/strata/event_spec.rb`
- `spec/models/strata/event_delivery_spec.rb`
- `spec/lib/strata/events_spec.rb`
- `spec/lib/strata/events/payload_spec.rb`
- `spec/lib/strata/events/subscriber_registry_spec.rb`
- `spec/lib/strata/events/delivery_runner_spec.rb`
- `spec/helpers/strata/event_manager_spec.rb`
- `spec/lib/strata/engine_spec.rb`
- `spec/integration/strata/durable_events_spec.rb`

Generate the two tables from the spec and add
`business_process_transition_version` to explicitly named existing case tables.
New case migrations must also create that column with database-level
`null: false, default: 0`; updating the model attribute alone is not enough.

Use `ActiveJob::Arguments` for payloads. Register only named class/module
methods in durable mode. Persist one event and one delivery per subscriber in
the publisher transaction, return `Strata::Event`, and run the delivery
synchronously for this slice. Missing tables warn once and use the legacy path.

Proof:

- Generated migrations run forward and backward and contain every constraint,
  index, and cascade from the spec.
- Symbol keys, nested values, timestamps, and GlobalID values round-trip.
- Anonymous subscribers are rejected only in durable mode.
- Commit persists the event and deliveries; rollback persists nothing.
- Synchronous outcomes become `succeeded`, `no_match`, or visible `failed`.

### 4. Concurrency and retry policy

Files:

- `app/lib/strata/events/errors.rb`
- `app/models/concerns/strata/step.rb`
- `app/models/strata/business_process_builder.rb`
- `app/models/strata/staff_task.rb`
- `app/models/strata/system_process.rb`
- `app/models/strata/applicant_task.rb`
- `app/models/strata/third_party_task.rb`
- `app/models/strata/business_process_instance.rb`
- `spec/models/strata/business_process_builder_spec.rb`
- `spec/models/strata/business_process_instance_spec.rb`
- `spec/models/strata/staff_task_spec.rb`
- `spec/models/strata/system_process_spec.rb`
- `spec/models/strata/applicant_task_spec.rb`
- `spec/models/strata/third_party_task_spec.rb`

Replace the ordinary step save with the step-and-version conditional update
from the spec. On conflict, reload and re-evaluate up to three times. Run no
step effect before the update succeeds. Add `retryable:` to every step helper,
defaulting to true, and wrap failures from non-retryable steps in a typed error.

Proof:

- Only the conditional-update winner runs effects.
- A loser applies against fresh state or returns `:no_match`.
- Three still-valid conflicts raise the retryable conflict error.
- A stale A-to-B-to-A worker cannot update the newer version.
- Every step helper propagates its retry policy.

### 5. ActiveJob delivery and recovery

Files:

- `app/jobs/strata/event_delivery_job.rb`
- `app/jobs/strata/requeue_stranded_deliveries_job.rb`
- `app/lib/strata/events/dispatcher.rb`
- `app/lib/strata/events/delivery_runner.rb`
- `app/helpers/strata/event_manager.rb`
- `app/models/strata/event_delivery.rb`
- `lib/tasks/strata_events.rake`
- `lib/strata/testing/event_helpers.rb`
- `spec/jobs/strata/event_delivery_job_spec.rb`
- `spec/jobs/strata/requeue_stranded_deliveries_job_spec.rb`
- `spec/lib/strata/events/dispatcher_spec.rb`
- `spec/lib/strata/events/delivery_runner_spec.rb`
- `spec/lib/tasks/strata_events_spec.rb`
- `spec/lib/strata/testing/event_helpers_spec.rb`
- `spec/helpers/strata/event_manager_spec.rb`
- `spec/integration/strata/durable_events_spec.rb`

After the publisher's outermost commit, dispatch each pending delivery and set
`enqueued_at` only after the adapter accepts it. The job locks the delivery,
returns for terminal or early work, and runs the subscriber plus terminal
status update in one transaction.

When a handler raises, roll back its transaction. In a new transaction, lock
and re-check the delivery; do nothing if a duplicate already completed or
rescheduled it. Otherwise record the attempt and either set the next durable
schedule or mark it `dead`. Dispatch retries only after that commit.

Add replay, status, pruning, stranded recovery, and payload-preflight tasks;
remove `publish_case_event`. Preflight must invoke payload samples registered by
the host in `Strata::Events`, not rely only on stored rows. The sweeper selects
only due `pending`/`failed` rows with null `enqueued_at` after the grace period.

Proof:

- No job exists before commit; rollback creates no job or rows.
- Duplicate jobs produce one terminal result and cannot overwrite success with
  a later failure record.
- Handler writes roll back before failure state commits.
- Retry enqueue failure leaves a recoverable row with null `enqueued_at`.
- The sweeper recovers missing initial and retry enqueues but ignores stamped
  or not-yet-due rows.
- Exhausted, non-retryable, and deleted-GlobalID deliveries become `dead`.
- Replay resets and dispatches the same delivery without republishing.
- Payload preflight catches an unserializable host sample before rollout.

### 6. Supported backend and rollout documentation

Files:

- `Gemfile`
- `Gemfile.lock`
- `spec/dummy/config/environments/test.rb`
- `spec/dummy/config/environments/development.rb`
- `spec/dummy/config/queue.yml`
- `spec/dummy/config/recurring.yml`
- `spec/dummy/db/queue_schema.rb`
- `README.md`
- `docs/case-management-business-process.md`
- `docs/generators.md`
- `docs/getting-started.md`

Use Solid Queue in the dummy app only; do not add a queue backend to the gemspec.
Document the generator, host-provided payload samples, subscriber migration,
idempotency, `retryable: false`, operator tasks, test helpers, supported queue
backends, and the breaking `publish` return value.

Proof:

- Start a Solid Queue worker, block a handler after claim, kill the worker,
  restart it, and verify the delivery is attempted again.
- Document GoodJob support and Sidekiq Pro `super_fetch`; reject Sidekiq OSS and
  unknown/non-durable adapters when durable mode is enabled.

## Test gates

Run focused specs from each slice, then run before every merge:

```sh
bundle exec rspec
bundle exec rubocop
```

The final integration suite must cover:

1. Publisher commit and rollback.
2. Payload and subscriber compatibility.
3. Handler rollback, success, `no_match`, retry, and dead-lettering.
4. Duplicate jobs and the failure-versus-success race.
5. Concurrent and cyclic case transitions.
6. Missing initial/retry enqueue recovery without slow-queue amplification.
7. Replay and pruning.
8. Missing-table fallback and unsupported-adapter failure.

## Main risks

- The enqueue/stamp gap can duplicate jobs; row locking and state re-checks
  must make duplicates harmless.
- External effects are not transactional; retryable callbacks need idempotency
  keys, preferably the delivery ID.
- Subscriber keys are persisted API; renames need a compatibility deploy.
- Event ordering is not guaranteed; hosts must monitor and replay `no_match`.
- The transition-version migration changes host-owned tables and must be
  reviewed before durability is enabled.

## Done when

- Every acceptance scenario in the spec has an automated test, except the
  explicit Solid Queue worker-kill smoke.
- Generated migrations work in the dummy app and a clean host app.
- Full RSpec and RuboCop suites pass.
- Upgrade documentation is complete and durability remains default-off.
