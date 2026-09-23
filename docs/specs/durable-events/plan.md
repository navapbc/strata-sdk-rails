# Durable events implementation plan

## Status and working agreement

Draft for engineering review. The approved behavior must come from
[`spec.md`](./spec.md); this document only defines how to implement and prove
that behavior.

Do not add application code on this planning branch. After this plan is
approved, implement it as the ordered, reviewable changes below. Each change
must leave the repository deployable, include its own tests, and update this
plan before merging if the implementation departs from it.

The release boundary remains the one in the spec:

1. Make existing synchronous transitions safe.
2. Persist and synchronously exercise durable event records.
3. Move durable subscribers to ActiveJob and add recovery.

The first release ships with `Strata::Events.durable = false`. Enabling it is a
host decision after migrations, payload preflight, subscriber migration, queue
configuration, and sweeper scheduling are complete.

## Implementation choices made by this plan

- Use `ActiveRecord.after_all_transactions_commit` to enqueue only after the
  publisher's outermost transaction commits. A rollback therefore leaves no
  event, delivery, or job.
- Store `ActiveJob::Arguments.serialize([payload]).first` in JSONB and reverse
  it with `deserialize([stored_payload]).first`. This preserves symbol keys and
  GlobalID behavior without inventing a second serializer.
- Use stable subscriber keys in the form
  `NamedClassOrModule.public_method_name`. Resolve the constant and public
  method again in the worker; never retain a Ruby object in a delivery row.
- Keep `publisher_type` and `publisher_id` nullable strings so hosts with UUID,
  integer, or other primary keys are not coupled to one database type. The
  unchanged public `publish(event_key, payload = {})` API does not infer a
  publisher from payload keys, so these fields remain null until a future
  explicit publisher context is specified.
- Hold the delivery-row lock for the handler transaction. A duplicate job
  waits, then exits after observing a terminal delivery. On handler failure,
  that transaction rolls back and a separate transaction records the failed
  attempt and its next schedule.
- Strata, not ActiveJob `retry_on`, owns handler retry scheduling. Use the
  delivery's `next_attempt_at` as the durable schedule and route initial
  attempts, retries, replays, and sweeper recovery through one dispatcher.
- Use a deterministic polynomial delay of `attempts**4 + 2` seconds. Keeping
  jitter out of the first implementation makes the stored schedule and tests
  reproducible; it can be added later without changing the data model.
- Generate transition-version columns for explicitly named existing case
  tables. `rails generate strata:events --case-tables test_cases passport_cases`
  writes those table names into the migration. Also update the case generator
  so every new case table receives the column automatically.
- Use Solid Queue only in the dummy application to prove the supported backend
  contract. Do not add a queue backend to `strata.gemspec`; host applications
  own that dependency and its production configuration.

## Files that change

### Slice 1: handler outcomes

| File | Change |
| --- | --- |
| `app/models/strata/business_process_instance.rb` | Return `:transitioned` or `:no_match` from start and transition operations. |
| `app/models/strata/business_process.rb` | Aggregate case outcomes, return the subscriber outcome, and emit one structured per-case outcome log. |
| `spec/models/strata/business_process_instance_spec.rb` | New focused outcome examples. |
| `spec/models/strata/business_process_spec.rb` | Prove start, all-no-match, mixed-case, and log behavior. |

### Slice 2: synchronous transition safety

| File | Change |
| --- | --- |
| `app/models/strata/business_process_instance.rb` | Put step mutation and step execution in one transaction; rescue only to log and re-raise `StandardError`. |
| `app/models/strata/business_process.rb` | Put start-case creation and first-step execution in one transaction. |
| `app/helpers/strata/event_manager.rb` | Add the temporary synchronous publish-boundary rescue so publisher writes still commit while the handler transaction rolls back. |
| `spec/models/strata/business_process_instance_spec.rb` | Prove rollback and successful commit for transition and start paths. |
| `spec/models/strata/business_process_spec.rb` | Prove a failed start leaves no partial case. |
| `spec/helpers/strata/event_manager_spec.rb` | New tests for the temporary rescue and non-`StandardError` propagation. |
| `spec/models/strata/application_form_spec.rb` | Prove a subscriber failure does not undo a submitted form. |
| `spec/models/strata/task_spec.rb` | Prove a subscriber failure does not undo a task status change. |

### Slice 3: schema and generators

| File | Change |
| --- | --- |
| `lib/generators/strata/events/events_generator.rb` | New generator with an array `--case-tables` option. |
| `lib/generators/strata/events/templates/create_strata_events.rb.tt` | Create event/delivery tables and add transition versions to the named case tables. |
| `lib/generators/strata/events/USAGE` | Document generation, migration, rollback, and the requirement to list every existing case table. |
| `app/models/strata/case.rb` | Add `business_process_transition_version:integer` to generated base attributes and define the defaulted attribute. |
| `spec/lib/generators/strata/generators/events_generator_spec.rb` | New generator output and duplicate-table tests. |
| `spec/lib/generators/strata/generators/case_generator_spec.rb` | Expect the version column for newly generated case tables. |
| `spec/dummy/db/migrate/<timestamp>_create_strata_events.rb` | Generated migration for event tables and all dummy case tables. |
| `spec/dummy/db/schema.rb` | Generated schema after running the migration. |

The generated schema is exact:

- `strata_events`: UUID `id`, non-null `name`, non-null JSONB `payload`, nullable
  `publisher_type` and `publisher_id`, and `created_at` as the publication
  timestamp. It is append-only, so it has no `updated_at`.
- `strata_event_deliveries`: UUID `id`, non-null UUID `event_id`, non-null
  `subscriber_key`, non-null integer `status` default `0`, non-null integer
  `attempts` default `0`, nullable `next_attempt_at`, `enqueued_at`,
  `last_error`, and `completed_at`, plus timestamps.
- A unique index on `[event_id, subscriber_key]`, a sweeper index on
  `[status, next_attempt_at, enqueued_at]`, and an event index on
  `[name, created_at]`.
- A foreign key from deliveries to events with `on_delete: :cascade`.
- A non-null integer `business_process_transition_version`, default `0`, on
  each named existing case table.

### Slice 4: records, serialization, and configuration

| File | Change |
| --- | --- |
| `app/models/strata/event.rb` | New append-only event model with deliveries, name scopes, and deserialized payload access. |
| `app/models/strata/event_delivery.rb` | New delivery model with status enum, terminal/due/stranded scopes, replay reset, and invariants. |
| `app/lib/strata/events.rb` | New configuration object, retry delay, table readiness, and queue-adapter validation. |
| `app/lib/strata/events/payload.rb` | New ActiveJob serialization and development/test payload-policy validation. |
| `lib/strata/engine.rb` | Install configuration defaults and one boot-time readiness/adapter check. |
| `spec/factories/strata/events.rb` | New event and delivery factories. |
| `spec/models/strata/event_spec.rb` | Associations, append-only behavior, scopes, and cascade assumptions. |
| `spec/models/strata/event_delivery_spec.rb` | Status, due/stranded scope, invariant, and replay-reset examples. |
| `spec/lib/strata/events_spec.rb` | Defaults, runtime `max_attempts`, table fallback, and adapter support matrix. |
| `spec/lib/strata/events/payload_spec.rb` | Symbol keys, nested values, GlobalID, rejected values, and missing-record behavior. |
| `spec/lib/strata/engine_spec.rb` | Warn-once fallback and fail-closed queue-adapter boot checks. |

`Strata::EventDelivery` must reject impossible state, including a terminal
status with `next_attempt_at`, a `failed` status whose remaining retry is not
represented by `next_attempt_at`, and a non-negative-attempt violation. Keep replay as one
model operation that resets status to `pending`, attempts to `0`, error and
completion fields to null, `enqueued_at` to null, and `next_attempt_at` to the
current time.

### Slice 5: subscriber registry and synchronous recording

| File | Change |
| --- | --- |
| `app/lib/strata/events/subscriber_registry.rb` | New registry, subscription handle, key generation/resolution, and anonymous-callback validation. |
| `app/lib/strata/events/delivery_runner.rb` | New shared handler transaction and outcome-to-status mapping. |
| `app/helpers/strata/event_manager.rb` | Select legacy or durable registration at registration time; serialize and persist event plus deliveries; return `Strata::Event`; synchronously run durable deliveries for this slice. |
| `app/models/strata/business_process.rb` | Supply its named method through the registry without changing the public subscription call. |
| `lib/strata/engine.rb` | Clear both legacy subscriptions and the durable registry during reload. |
| `spec/lib/strata/events/subscriber_registry_spec.rb` | Stable keys, resolution, unsubscribe, reload, and anonymous rejection. |
| `spec/lib/strata/events/delivery_runner_spec.rb` | Applied/no-match/unrecognized outcomes, rollback on exception, and delivery state. |
| `spec/helpers/strata/event_manager_spec.rb` | Persistence atomicity, one delivery per subscriber, breaking return value, sync durable execution, and legacy fallback. |
| `spec/integration/strata/durable_events_spec.rb` | New end-to-end publish/rollback/payload/subscriber scenarios against Postgres. |

The durable publish path must perform these steps in order:

1. Snapshot the registered durable subscribers for the event name.
2. Validate and serialize the payload before inserting anything.
3. In the publisher's current transaction, insert one event and one pending
   delivery per stable subscriber key with `next_attempt_at = Time.current`.
4. In this slice only, invoke each delivery through `DeliveryRunner` in-process
   and record `succeeded`, `no_match`, or `failed`. A synchronous failure is
   visible as `failed` with `next_attempt_at = Time.current` and null
   `enqueued_at`; this slice does not dispatch that retry.
5. Return the persisted `Strata::Event` in both the no-subscriber and
   subscriber cases.

If event tables are missing, warn once and take the unchanged Notifications
path. If durability is disabled, anonymous subscriptions remain supported and
`publish` retains the legacy path until the rollout release flips the default.
The return-value change to `Strata::Event` applies to the durable path and must
be called out as breaking in the documentation before release.

### Slice 6: asynchronous delivery and durable attempt scheduling

| File | Change |
| --- | --- |
| `app/jobs/strata/event_delivery_job.rb` | New idempotent delivery job; no `retry_on` for handler errors. |
| `app/lib/strata/events/dispatcher.rb` | New single enqueue/stamp implementation used by initial attempts, retries, replay, and recovery. |
| `app/lib/strata/events/errors.rb` | New `TransitionConflict` and `NonRetryableStepError` types. |
| `app/lib/strata/events/delivery_runner.rb` | Add failure recording, terminal deserialization handling, and durable retry scheduling. |
| `app/helpers/strata/event_manager.rb` | Replace synchronous durable execution with after-outermost-commit dispatch; remove the temporary publish-boundary rescue from the durable path. |
| `spec/jobs/strata/event_delivery_job_spec.rb` | Duplicate, terminal, success, no-match, retry, exhausted, non-retryable, early, and deleted-GlobalID examples. |
| `spec/lib/strata/events/dispatcher_spec.rb` | Queue acceptance/stamping and enqueue-before-stamp failure-window examples. |
| `spec/lib/strata/events/delivery_runner_spec.rb` | Handler transaction rollback and separately committed failure schedule. |
| `spec/helpers/strata/event_manager_spec.rb` | No job before commit, job after outer commit, and no job/event/delivery after rollback. |
| `spec/integration/strata/durable_events_spec.rb` | Prove eventual job execution and duplicate absorption. |

The job protocol is:

1. Find the delivery; return when it was pruned.
2. Enter a transaction and lock the delivery row.
3. Return for a terminal status or when `next_attempt_at` is still in the
   future. This absorbs duplicate and prematurely run jobs.
4. Deserialize the event. A missing GlobalID raises a terminal payload error.
5. Resolve the subscriber key and call it with `{ name:, payload: }` inside the
   same transaction as the terminal delivery update.
6. Increment attempts once. Map `:no_match` to `no_match`; map every other
   non-raising return to `succeeded`. Clear `next_attempt_at`, set
   `completed_at`, and retain the most recent `enqueued_at`.
7. If the handler raises, roll back the handler transaction. In a new
   transaction, lock the delivery, increment attempts, store a bounded error
   class/message/backtrace, and either mark it `dead` or set it `failed` with
   the polynomial `next_attempt_at` and null `enqueued_at`.
8. After the failure transaction commits, call the dispatcher. If enqueueing
   fails, leave `enqueued_at` null and let the sweeper recover it.

Infrastructure failures before durable failure state can be written may raise
to the queue backend. Handler failures must not use ActiveJob `retry_on`, since
that would create an unrepresented retry schedule.

### Slice 7: concurrency and step retry policy

| File | Change |
| --- | --- |
| `app/models/concerns/strata/step.rb` | Add readable `retryable?`, defaulting to true. |
| `app/models/strata/business_process_builder.rb` | Accept `retryable:` for `step`, `staff_task`, `system_process`, `applicant_task`, and `third_party_task`. |
| `app/models/strata/staff_task.rb` | Store retry policy without changing execution behavior. |
| `app/models/strata/system_process.rb` | Store retry policy and surface non-retryable execution failure. |
| `app/models/strata/applicant_task.rb` | Store retry policy. |
| `app/models/strata/third_party_task.rb` | Store retry policy. |
| `app/models/strata/business_process_instance.rb` | Replace ordinary step save with the versioned conditional transition and three-attempt re-evaluation loop; run no step effect before the update succeeds; wrap a failure from a `retryable: false` step in `NonRetryableStepError`. |
| `spec/models/strata/business_process_builder_spec.rb` | New DSL default/override propagation examples. |
| `spec/models/strata/staff_task_spec.rb` | Retry-policy behavior. |
| `spec/models/strata/system_process_spec.rb` | Retry-policy behavior and error metadata. |
| `spec/models/strata/applicant_task_spec.rb` | Retry-policy behavior. |
| `spec/models/strata/third_party_task_spec.rb` | Retry-policy behavior. |
| `spec/models/strata/business_process_instance_spec.rb` | Competing events, re-evaluation, three-conflict retry, cyclic A-to-B-to-A protection, and no pre-CAS effects. |
| `spec/jobs/strata/event_delivery_job_spec.rb` | `retryable: false` goes directly to `dead`; transition conflicts remain retryable. |

For each candidate transition, capture both
`business_process_current_step` and `business_process_transition_version`, then
issue one conditional update that sets the next step and increments the
version. A zero-row update reloads the case and re-evaluates the event. Return
`:no_match` if the fresh step no longer accepts it. After three still-valid
conflicts, raise `Strata::Events::TransitionConflict`. Execute the winning step
only after the update succeeds and inside the same transaction.

### Slice 8: sweeper, operator tasks, and testing API

| File | Change |
| --- | --- |
| `app/jobs/strata/requeue_stranded_deliveries_job.rb` | New bounded-batch sweeper using the shared dispatcher. |
| `lib/tasks/strata_events.rake` | Add status, replay, replay-dead, requeue-stranded, prune, and payload-preflight tasks; delete `publish_case_event`. |
| `lib/strata/testing/event_helpers.rb` | New helpers for enabling durable mode and performing enqueued deliveries in tests. |
| `spec/jobs/strata/requeue_stranded_deliveries_job_spec.rb` | Recover unstamped initial/retry work; leave stamped or not-yet-due work alone. |
| `spec/lib/tasks/strata_events_spec.rb` | Arguments, output, replay reset/dispatch, bulk filtering, pruning guardrails/cascade, preflight, and removed-task coverage. |
| `spec/lib/strata/testing/event_helpers_spec.rb` | Helper isolation and job execution. |
| `spec/integration/strata/durable_events_spec.rb` | Acceptance scenarios for retries, replay, pruning, and sweeper recovery. |

The sweeper selects only `pending` or `failed` rows with null `enqueued_at` and
`next_attempt_at <= Time.current - Strata::Events.stranded_after`. Process in
primary-key batches and dispatch each row independently so one adapter failure
does not stop the remaining batch. A stamped delivery belongs to the queue
backend and must not be duplicated merely because the queue is slow.

Replay is allowed only from `failed` or `dead`. It calls the model's atomic
reset, then the common dispatcher after commit. Pruning requires either an
explicit positive day count or configured retention; it deletes events, lets
the database cascade deliveries, and reports counts. Payload preflight scans
stored events, optionally filtered by event name, and reports deserialization
or policy failures without invoking subscribers. If no samples exist, it says
so; host producer specs must also call the payload validator with representative
payloads before rollout.

### Slice 9: supported backend proof and release documentation

| File | Change |
| --- | --- |
| `Gemfile` | Add Solid Queue to development/test only. |
| `Gemfile.lock` | Lock the dummy-app backend dependency. |
| `spec/dummy/config/environments/test.rb` | Use the ActiveJob test adapter for deterministic job specs. |
| `spec/dummy/config/environments/development.rb` | Configure Solid Queue for manual end-to-end testing. |
| `spec/dummy/config/queue.yml` | Generated Solid Queue database configuration. |
| `spec/dummy/config/recurring.yml` | Schedule stranded-delivery recovery every few minutes. |
| `spec/dummy/db/queue_schema.rb` | Generated Solid Queue schema if the installed version uses a separate queue database. |
| `docs/case-management-business-process.md` | Document durable registration, payloads, retryable steps, idempotency, and test helpers. |
| `docs/generators.md` | Document `strata:events` and existing-case-table arguments. |
| `docs/getting-started.md` | Add the host rollout checklist and supported backend requirements. |
| `README.md` | Call out the breaking `publish` return value and link to the upgrade instructions. |
| `docs/specs/durable-events/spec.md` | Change status only after implementation review confirms the shipped behavior matches the spec. |

Do not claim worker-kill recovery from an in-memory unit test. Add a manual
backend smoke procedure to `docs/getting-started.md`: start Solid Queue, block a
handler after claim, kill the worker, restart it, and verify the same delivery
is attempted and reaches a terminal state. Sidekiq documentation must say OSS
is unsupported and Pro requires `super_fetch`; GoodJob and Sidekiq validation
are configuration-contract tests, not SDK dependencies.

## Order of work and merge gates

Implement each numbered slice as a separate small branch/PR stacked on the
previous accepted slice. Do not begin the next release phase until its gate is
green.

1. **Handler outcomes.** This is behavior-only and has no persistence or job
   dependency. Existing PR #382 may satisfy this slice after it is rebased and
   its diff is checked against the files and proof above.
2. **Synchronous transition safety.** Land atomically with the temporary
   boundary rescue. Never merge exception propagation without that rescue.
3. **Schema and generators.** Review migration shape and rollback separately
   from runtime behavior. Run the generated migration in a temporary host and
   the dummy app.
4. **Records, serialization, and configuration.** Keep dormant behind the
   default-off flag. Gate: missing migrations do not break boot.
5. **Subscriber registry and synchronous recording.** Gate: an opted-in host
   gets durable rows and current in-process behavior, with no jobs yet.
6. **Asynchronous delivery and durable scheduling.** Gate: all enqueue gaps,
   retries, and duplicates are represented by tests before changing delivery
   from synchronous to ActiveJob.
7. **Concurrency and step retry policy.** Gate: Postgres concurrency tests prove
   only a CAS winner runs effects and cyclic workflows reject stale versions.
8. **Sweeper, operator tasks, and testing API.** Gate: every operator repair
   action uses the same replay/dispatcher code as normal delivery.
9. **Backend proof and documentation.** Gate: full suite, migration smoke,
   Solid Queue worker-kill smoke, and host upgrade instructions are complete.

Release Phase 1 after slices 1-2, Phase 2 after slices 3-5, and Phase 3 after
slices 6-9. Keep durability default-off throughout this plan. Flipping the
default is a later release with its own adoption evidence and release note.

## Tests that prove it

### Per-slice commands

Run the focused specs named in each slice first, then:

```sh
bundle exec rubocop <changed Ruby files and specs>
bundle exec rspec <changed spec files>
```

Run these phase gates from the repository root:

```sh
# Phase 1 gate
bundle exec rspec \
  spec/helpers/strata/event_manager_spec.rb \
  spec/models/strata/business_process_instance_spec.rb \
  spec/models/strata/business_process_spec.rb \
  spec/models/strata/application_form_spec.rb \
  spec/models/strata/task_spec.rb

# Phase 2 gate
bundle exec rspec \
  spec/lib/generators/strata/generators/events_generator_spec.rb \
  spec/lib/generators/strata/generators/case_generator_spec.rb \
  spec/models/strata/event_spec.rb \
  spec/models/strata/event_delivery_spec.rb \
  spec/lib/strata/events_spec.rb \
  spec/lib/strata/events/payload_spec.rb \
  spec/lib/strata/events/subscriber_registry_spec.rb \
  spec/lib/strata/events/delivery_runner_spec.rb \
  spec/integration/strata/durable_events_spec.rb

# Phase 3 gate
bundle exec rspec \
  spec/jobs/strata/event_delivery_job_spec.rb \
  spec/jobs/strata/requeue_stranded_deliveries_job_spec.rb \
  spec/lib/strata/events/dispatcher_spec.rb \
  spec/lib/tasks/strata_events_spec.rb \
  spec/lib/strata/testing/event_helpers_spec.rb \
  spec/models/strata/business_process_instance_spec.rb \
  spec/integration/strata/durable_events_spec.rb
```

Every slice also runs the complete regression suite before merge:

```sh
bundle exec rspec
bundle exec rubocop
```

### Required proof matrix

| Guarantee | Automated proof |
| --- | --- |
| Publisher commit creates durable work | Integration spec observes event, one delivery per subscriber, and a job only after outer commit. |
| Publisher rollback creates nothing | Integration spec rolls back and observes no row and no job. |
| `publish` returns `Strata::Event` | Event manager spec asserts the exact class and persisted identity, including no-subscriber publish. |
| Payload compatibility | Payload spec round-trips symbol keys, nested values, timestamps, and a GlobalID record. |
| Deleted GlobalID is terminal | Job spec deletes the referenced record and observes one attempt ending `dead`. |
| Handler state is atomic | Runner/instance specs make a handler write then raise and observe both handler and transition writes rolled back. |
| At-least-once duplicate is safe | Two jobs for one delivery produce one handler effect and one terminal update. |
| Retry schedule survives enqueue failure | Dispatcher raises after failure state commits; row remains due with null `enqueued_at`; sweeper later enqueues it. |
| Slow queues are not amplified | Sweeper spec leaves due rows with non-null `enqueued_at` untouched. |
| Attempts exhaust visibly | Job spec reaches runtime `max_attempts` and observes `dead`, count, error, and no next schedule. |
| Non-retryable step stops immediately | Job spec observes first failure transition directly to `dead`. |
| Competing transitions do not both apply | Postgres thread/barrier spec observes one CAS winner and no losing pre-CAS side effect. |
| Cyclic stale work cannot win | Instance spec moves A-to-B-to-A, then proves the version-1 A transition cannot update version 3. |
| Partial multi-case result is visible | Business-process spec observes overall `:transitioned` and one structured log per case with both outcomes. |
| Replay does not republish | Task/integration spec resets the same delivery ID and creates no new event or sibling delivery. |
| Pruning is safe | Task spec deletes an old event and observes database-cascaded deliveries. |
| Missing migrations fail safely | Engine spec gets one warning and legacy synchronous delivery. |
| Unsupported adapters fail closed | Engine/config spec rejects inline, async, inappropriate test, and Sidekiq OSS adapters. |
| Claimed job survives worker death | Manual Solid Queue smoke described above; attach output to the Phase 3 PR. |

## Risks and review focus

1. **The transaction callback is the highest-risk boundary.** Test nested
   transactions and savepoints, not just a single top-level transaction. A job
   must never appear for rolled-back work.
2. **Queue acceptance and `enqueued_at` cannot be atomic.** The intentional
   enqueue-before-stamp race can duplicate a job. Row locking and terminal
   checks must make that duplicate harmless.
3. **Database work and external effects cannot share one transaction.** Every
   retryable external callback needs an idempotency key. The delivery ID is the
   recommended key. Unsafe callbacks must use `retryable: false`.
4. **Subscriber keys are persisted API.** Renaming a class or method strands
   historical deliveries. Document a deploy sequence or temporary compatibility
   method before merging any subscriber rename.
5. **Retries can reorder events.** This implementation intentionally provides
   no publication order. Operators need `no_match` monitoring and deliberate
   replay, not automatic ordering assumptions.
6. **The transition-version migration touches host-owned tables.** Require an
   explicit table list, reversible migration, and host review before enabling
   durability.
7. **Phase 2 synchronous failures need visible state.** They must leave the
   publisher committed and the delivery `failed`; they must not silently mimic
   a successful delivery.
8. **Backend validation can drift with adapter versions.** Fail closed on an
   unknown adapter and include its class name in the error rather than guessing
   that it has orphan recovery.

## Rejected alternatives

- **ActiveJob `retry_on` for handler errors:** rejected because the retry
  schedule would not be durable in `strata_event_deliveries`; a worker can die
  after recording failure and before enqueueing the retry.
- **One delivery per case:** rejected because start events create their case at
  delivery time and it would duplicate routing logic. A delivery remains per
  event/subscriber, with per-case structured logs.
- **A generic Rails `lock_version`:** rejected because unrelated host updates
  would create workflow conflicts. The monotonic field is scoped to business
  process transitions.
- **Queue-specific same-database shortcuts:** rejected because all supported
  adapters must follow the same commit-then-enqueue protocol and sweeper rule.
- **Persisting callable objects:** rejected because closures cannot be safely
  reconstructed across deploys and processes.
- **Inferring publisher identity from payload keys:** rejected because
  `case_id`, `task_id`, and `application_form_id` are neither uniform nor proof
  of which record initiated publication.
- **Automatic replay of `no_match`:** rejected because events are unordered and
  replay may create real-world side effects. Replay remains an operator action.

## Definition of done

- Every acceptance scenario in `spec.md` maps to a passing automated test or
  the explicit Solid Queue worker-kill smoke.
- Every new public behavior and breaking change is documented.
- The generated migration runs forward and backward in the dummy app and a
  clean temporary host.
- The full RSpec and RuboCop suites pass.
- Durability remains default-off, and missing tables use the legacy synchronous
  path with one warning.
- The final implementation diff contains no behavior that is absent from the
  spec or this reviewed plan; any departure is documented here before merge.
