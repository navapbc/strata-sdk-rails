# Durable events implementation plan

## Status

Draft for engineering review. [`spec.md`](./spec.md) defines the behavior; this
plan defines the implementation order and proof. Keep this branch plan-only.

This plan produces **six stacked implementation PRs**, one for each numbered
section below. Including this plan-only PR, the stack contains **seven PRs in
total**. Every implementation PR must pass its focused tests and the full suite
before the next one starts. If implementation changes the design, update the
spec and this plan first.

This supersedes the earlier durable events plan on
[PR #379](https://github.com/navapbc/strata-sdk-rails/pull/379), which was
closed unmerged. Its code reconnaissance is carried forward in
[Known corrections and house style](#known-corrections-and-house-style);
nothing else from it is still current.

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

## Known corrections and house style

`spec.md` was distilled before it merged and no longer carries DDL or generator
detail, so the following is settled here. Each item was verified against the
code on `main`.

- **The generator precedent is `strata:audit_log`, not `strata:task`.**
  `lib/generators/strata/audit_log/audit_log_generator.rb` is a
  `Rails::Generators::Base` whose only job is installing a migration, with the
  model shipped by the engine — exactly this case. `strata:task` is a
  `NamedBase` that also writes a model, so it is the wrong pattern to copy.
- **Declare columns raw and add the cascade separately.** No `strata_*`
  migration or generator template in this repo uses `t.references`. The house
  form is `t.uuid :event_id` plus an explicit
  `add_foreign_key :strata_event_deliveries, :strata_events, on_delete: :cascade`
  after the `create_table` block, as in
  `spec/dummy/db/migrate/20250327160205_create_passport_cases.rb:14`. The
  cascade is load-bearing: pruning raises `ActiveRecord::InvalidForeignKey`
  without it.
- **Append-only rows carry one timestamp.** `strata_audit_lines` and
  `strata_determinations` declare a bare `t.datetime :created_at, null: false`
  rather than `t.timestamps`. `strata_events` follows them. Deliveries are
  mutable, so their `t.timestamps` is correct.
- **UUID keys carry their default:**
  `id: :uuid, default: -> { "gen_random_uuid()" }`, as in
  `create_strata_audit_lines.rb`. `create_strata_determinations.rb` omits the
  default and the engine's own `create_strata_tasks.rb.tt` does too, so follow
  `spec/dummy/db/schema.rb` rather than the nearest template.
- **Factories are named `*_factory.rb`.** Every file in
  `spec/factories/strata/` and `spec/dummy/spec/factories/` follows it, and
  engine factories are registered from `lib/strata/engine.rb`. Strata models use
  the `strata_` prefix (`strata_task_factory.rb`,
  `strata_audit_line_factory.rb`).
- **There is no ActiveJob infrastructure to build on.** No `perform_later`
  exists in the engine or the dummy app, no environment configures a queue
  adapter, no background-job gem is in `Gemfile` or `strata.gemspec`,
  `Strata::ApplicationJob` is an empty subclass, and `ActiveJob::TestHelper` is
  not included anywhere — so `perform_enqueued_jobs` is unavailable until
  Implementation PR 6 adds it. Implementation PR 5 must assume none of it
  exists.
- **`handle_event` is public despite appearances.**
  `app/models/strata/business_process.rb` writes `private` and then opens
  `class << self`. `private` governs instance methods, so `handle_event`,
  `create_case_from_event`, and `start_event?` are all public class methods.
  Durable subscriber keys depend on that, so make the visibility explicit
  rather than leaving it resting on a coincidence that a later cleanup could
  remove.
- **Derive subscriber keys from the receiver, not the method owner.** Every
  business process inherits `handle_event`, so
  `PassportBusinessProcess.method(:handle_event).owner` is
  `Strata::BusinessProcess`, not `PassportBusinessProcess`. A key built from
  `owner` collapses every process onto one string: two processes subscribed to
  the same event name then write two delivery rows with the same
  `subscriber_key`, the unique index rejects the insert inside the publisher's
  transaction, and the originating form or task save fails. Use
  `method.receiver.name`, and have the registry reject duplicate keys for one
  event name at registration time.
- **Configuration cannot live in an autoloaded constant.** `app/lib` is an
  autoload path, so a `Strata::Events` defined there is unloaded on every
  reload and a host's `Strata::Events.durable = true` in an initializer is
  discarded on the first code change in development. It belongs in
  `lib/strata/events.rb`, required from `lib/strata.rb`, the way
  `lib/strata/auth.rb` already is. The rest of the namespace stays in `app/lib`
  and Zeitwerk attaches it to the module that `require` already defined.
- **The test helper constant is `Strata::Testing::EventHelpers`**, matching
  `Strata::Testing::ApiAuthHelpers`, and hosts must `require` it explicitly —
  it is not autoloaded. `spec.md`'s upgrade checklist step 10 says
  `Strata::Events::TestHelpers`; that is the spec's error and the follow-up
  spec PR corrects it.

## Implementation sequence

### Implementation PR 1: Handler outcomes

Return `:transitioned` or `:no_match`, aggregate multi-case results, and emit
one structured outcome log per resolved case. Existing PR #382 supplies most
of this PR; add the structured logging if it is not already present.

Proof:

- Start events return `:transitioned`.
- No matching transition returns `:no_match`.
- Mixed multi-case results return `:transitioned` and log every case outcome.

### Implementation PR 2: Safe synchronous transitions

Wrap step mutation and execution in one transaction. Do the same for start-case
creation and first-step execution. Stop swallowing `StandardError`, but add the
temporary publish-boundary rescue so a failed handler does not roll back the
form or task that published the event.

Proof:

- A failed step leaves the case at its prior step and rolls back step writes.
- A failed start leaves no partial case.
- The publishing form or task remains committed.
- Non-`StandardError` exceptions still propagate.

### Implementation PR 3: Durable records with synchronous delivery

Generate the two tables from the spec and add
`business_process_transition_version` to explicitly named existing case tables.
New case migrations must also create that column with database-level
`null: false, default: 0`; updating the model attribute alone is not enough.

Use `ActiveJob::Arguments` for payloads. Register only named class/module
methods in durable mode, keying them off the subscribing constant rather than
the defining one (see the subscriber-key correction above). Persist one event
and one delivery per subscriber in the publisher transaction, return
`Strata::Event`, and run the delivery synchronously at this stage. Missing
tables warn once and use the legacy path.

Proof:

- Generated migrations run forward and backward and contain every constraint,
  index, and cascade from the spec.
- Symbol keys, nested values, timestamps, and GlobalID values round-trip.
- Anonymous subscribers are rejected only in durable mode.
- Commit persists the event and deliveries; rollback persists nothing.
- Synchronous outcomes become `succeeded`, `no_match`, or visible `failed`.

### Implementation PR 4: Concurrency and retry policy

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

### Implementation PR 5: ActiveJob delivery and recovery

After the publisher's outermost commit, dispatch each pending delivery and set
`enqueued_at` only after the adapter accepts it. The job locks the delivery,
returns for terminal work, and runs the subscriber plus terminal status update
in one transaction.

A job that wakes before its `next_attempt_at` must clear `enqueued_at` before
returning. The sweeper ignores stamped rows, so returning early while stamped
leaves the delivery due, unqueued, and invisible to recovery for good. Clock
skew between hosts makes this reachable on ordinary retries, not just on
duplicates.

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

### Implementation PR 6: Supported backend and rollout documentation

Use Solid Queue in the dummy app only; do not add a queue backend to the gemspec.
Document the generator, host-provided payload samples, subscriber migration,
idempotency, `retryable: false`, operator tasks, test helpers, supported queue
backends, and the breaking `publish` return value.

Proof:

- Start a Solid Queue worker, block a handler after claim, kill the worker,
  restart it, and verify the delivery is attempted again.
- Document Solid Queue and GoodJob as the supported backends; both recover a
  job claimed by a worker that dies, which is what the guarantee rests on.
- Reject `inline`, `async`, and unknown adapters at boot when durable mode is
  enabled, naming the adapter class in the error.
- Sidekiq OSS and Sidekiq Pro present the same adapter class, so the boot check
  cannot separate them by class alone. Either probe for Pro and an enabled
  `super_fetch`, or accept Sidekiq with a loud warning and carry the
  restriction in documentation — decide which before writing the check, and
  keep the test honest about what it proves.

## Test gates

Run the focused specs for the work in hand, then run before every merge:

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

## Test environment facts

None of these are visible from the suite, and each one constrains the work
above:

- **The suite uses transactional fixtures** (`spec/rails_helper.rb:68`), not
  DatabaseCleaner. Confirm that `ActiveRecord.after_all_transactions_commit`
  fires under them before Implementation PR 5 is built on it. A negative result
  invalidates the dispatch path, so spike it first.
- **`spec/support` is not glob-loaded.** The glob at `spec/rails_helper.rb:45`
  is commented out, so new matchers and helpers must be required per spec, the
  way `publish_event_with_payload` is today.
- **`PassportBusinessProcess` is subscribed for the whole suite.**
  `spec/dummy/config/application.rb:40` starts it listening inside
  `config.after_initialize`, so any spec that saves a `PassportApplicationForm`
  creates a `PassportCase` through the event path whether it asserts on it or
  not. Changing delivery timing therefore reaches well beyond the specs any
  one PR above is about — model, policy, view, and controller specs across
  both the engine and the dummy app all run through it today. Budget for that
  rather than discovering it at the end; the engine's test case factory
  already works around the same coupling with `find_or_create_by!`.

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
