# Implementation Plan: Durable events

## Status

Draft — for engineering review. No implementation has started.

## Date

2026-09-15

## Source documents

| Document | Role |
| --- | --- |
| [docs/intent/durable-events.md](../../intent/durable-events.md) | Why — the problem and the constraints |
| [docs/specs/durable-events/spec.md](./spec.md) | What and how — requirements and design |
| This plan | When and in what order — sequenced, reviewable work |

Where this plan and the spec disagree, the spec is the design authority and this
plan is wrong — except in [Deltas from the spec](#deltas-from-the-spec), which
records places the spec needs correcting against the code as it actually is.

## How to use this plan

- **Tests first.** Per [CLAUDE.md](../../../CLAUDE.md), every non-trivial item
  needs RSpec tests written and **approved by the team before implementation**.
  Each work item below names its tests separately from its implementation for
  that reason.
- **One PR per phase, minimum.** Phases 1 and 2 are each small enough for a
  single PR. Phase 3 should be split — the subscriber split and the job are
  separately reviewable.
- **Each work item carries** what changes, which files, the tests to write
  first, acceptance criteria, and the spec section it implements.
- **`make lint` and `make test` must both pass before every push**
  (CLAUDE.md hard rule). CI runs `lint-ci` and `test` as a matrix; both legs run
  `make setup`, so both need the Postgres container.

---

## Deltas from the spec

Reconnaissance against the current code turned up six places where the spec's
design is right but its detail is wrong. Fix these in the spec as part of Phase
2, or carry them as known corrections.

**D1 — `strata:audit_log` is the generator precedent, not `strata:task`.**
Spec §5.2 says "following the `strata_tasks` precedent." The closer match is
`lib/generators/strata/audit_log/audit_log_generator.rb`: a
`Rails::Generators::Base` whose only job is installing a migration, with the
model shipped by the engine. That is exactly this case. The task generator is
`NamedBase` and writes a model plus a migration only if the user accepts a
prompt.

**D2 — the DDL is off house style.** Spec §5.2 writes
`t.references :strata_event, null: false, foreign_key: true, type: :uuid`. No
`strata_*` migration in this repo uses `t.references` or `add_foreign_key` — all
of them declare raw `t.uuid :foo_id` plus `t.string :foo_type` and add explicit
named indexes after the `create_table` block. Match the house style; see
[2.2](#22-migration-generator).

**D3 — `strata_event_deliveries` is not append-only, so it takes
`t.timestamps`.** The house rule is `t.timestamps` for mutable rows
(`strata_tasks`) and a bare `t.datetime :created_at, null: false` for
append-only rows (`strata_audit_lines`, `strata_determinations`). Deliveries
change status, so they are mutable. `strata_events` rows never change after
insert, so that table gets the bare `created_at` form — and the spec's separate
`published_at` column is then redundant with it. Collapse to one column.

**D4 — there is no ActiveJob infrastructure of any kind to build on.** No job in
the engine or dummy app does work; there is no `perform_later` anywhere, no
queue adapter configured in any environment, and no background-job gem in either
`Gemfile` or `strata.gemspec`. `Strata::ApplicationJob` is an empty subclass.
Spec §7's test plan assumes `perform_enqueued_jobs` is available; it is not —
`ActiveJob::TestHelper` is not included anywhere and would have to be wired up
first. See [3.7](#37-test-helpers).

**D5 — the async test surface is larger than spec §7 lists.**
`spec/dummy/config/application.rb:40` starts `PassportBusinessProcess`
listening inside `config.after_initialize`, so it is subscribed for the whole
suite. Any spec that saves a `PassportApplicationForm` creates a `PassportCase`
inline through the event path, whether or not it asserts on it. Beyond the three
files the spec names, this also touches
`spec/models/strata/task_spec.rb`, `spec/models/strata/application_form_spec.rb`,
`spec/dummy/spec/models/passport_application_form_spec.rb`,
`spec/policies/strata/application_form_policy_spec.rb`,
`spec/dummy/spec/views/passport_application_forms/show.html.erb_spec.rb`, and
`spec/dummy/spec/controllers/sample_application_forms_controller_spec.rb`.
`spec/factories/strata/strata_test_case_factory.rb` already works around this
with `find_or_create_by!`.

**D6 — the retention decision (0.1) supersedes the spec's default.** Spec §8.1
still specifies a 90-day `retention_period` and §11.1 still calls retention a
Phase 2 merge blocker. Both are now wrong: the default is `nil` and the prune
task ships disabled, so nothing is blocked and nothing is deleted until a host
opts in. Correct both sections.

---

## Phase 0 — Decisions (closed 2026-09-15)

All four are answered. **Nothing in this plan is blocked.** Phase 2 was gated on
0.1 and Phase 3 on 0.3; both are resolved. Phase 1 was never gated and can start
now.

| # | Question | Decision | What it changed |
| --- | --- | --- | --- |
| 0.1 | Retention and encryption for `strata_events.payload`, with the policy unconfirmed | **Ship the prune task, disabled by default.** `retention_period` defaults to `nil`; a host opts in by setting it | The mechanism gets reviewed in Phase 2 without a default that could delete wrongly. No longer gates Phase 2 — a `nil` default cannot delete a record someone must keep |
| 0.2 | Does a framework-written payload store reopen [audit-log-pii-redaction.md](../../decisions/audit-log-pii-redaction.md)? | **Decide at Phase 2 review**, not up front | Added to the Phase 2 review agenda in [2.9](#29-documentation) so it is a checklist item rather than something that quietly lapses |
| 0.3 | Does `retryable: false` per step ship with Phase 3? | **Yes, in scope** | Promoted from open question to work item [3.5](#35-per-step-retryable-false) |
| 0.4 | What queue backend? | **Adapter-agnostic.** The engine declares none; hosts choose. Dummy app uses the `:test` adapter | [3.9](#39-dummy-app-queue-backend) is now small and concrete: no gem, no engine opinion |

**Still open, but blocking nothing.** The actual retention obligation needs an
owner before any host enables pruning, and encryption-at-rest for `payload`
remains undecided. Both are deferred, not resolved — the `nil` default is what
makes deferring them safe.

---

## Phase 1 — Fix the blocking defects

No new behavior, no migration, no ActiveJob. **Everything after this is unsound
without it.** Ships on its own merits: it fixes real bugs in today's system.

### 1.1 Propagate exceptions out of step execution

**What.** `BusinessProcessInstance#execute_current_step`
(`app/models/strata/business_process_instance.rb:71-83`, the `rescue` at `:79`) wraps the step in
`rescue Exception`, logs, and swallows. Log and re-raise instead. Narrow the
rescue so `SignalException` and `Interrupt` are never caught — a step currently
resists Ctrl-C and absorbs the very termination signal this project exists to
survive.

**Files.** `app/models/strata/business_process_instance.rb`.

**Tests first.** A step whose callback raises propagates to the caller; the
error is still logged; `Interrupt` is not swallowed; the case is left in a
defined state.

**Acceptance.** A raising step reaches the publisher. No `rescue Exception`
remains in the file.

**Spec.** §6.1. **Risk.** §11.5 — hosts start seeing failures they already had.
See [1.4](#14-release-notes-for-phase-1).

### 1.2 Make the step change and its execution atomic

**What.** `transition_to_next_step`
(`app/models/strata/business_process_instance.rb:59-67`) sets `current_step`
and calls `save!` *before* `execute_current_step`. If the process dies between
them, the case has advanced but the work never ran — and a retry computes the
next step from the already-advanced step, finds no transition, and silently
no-ops. Wrap both in one transaction so they commit or roll back together.

Use `Strata::AuditLog.record` (`app/models/strata/audit_log.rb:59-65`) as the
house pattern for a transaction wrapping caller work. Take a row lock on the
case per the aggregate-root guidance in
[data-modeling-guidelines.md](../../contributing/data-modeling-guidelines.md).

**Files.** `app/models/strata/business_process_instance.rb`.

**Tests first.** A step that raises mid-execution leaves `current_step`
unchanged; a subsequent retry applies the transition correctly; a successful
transition still commits both. Add an explicit regression test for the
"advanced but never executed, retry no-ops" scenario — that is the bug.

**Acceptance.** No observable state in which `current_step` has advanced but the
step never ran.

**Spec.** §6.2.

> **Note.** While here: the YARD note on `Strata::AuditLog`
> (`audit_log.rb:27-31`) claims an inner `transaction` becomes a savepoint under
> an outer one. It does not — `record` passes no `requires_new: true`, so the
> inner call joins the outer transaction. Out of scope for this work, but worth
> filing; it is a misleading contract on a shipped API.

### 1.3 Pin the symbol-key contract in `Case.for_event`

**What.** `Case.for_event` (`app/models/strata/case.rb:75-88`) tests
`event[:payload].key?(:case_id)` with symbol keys. Any serialization that
stringifies keys makes it return `none` for every event — all deliveries
succeed, no case moves, silently. Phase 2 must not break this. Add a
characterization test now, before anything touches serialization.

**Files.** `spec/models/strata/case_spec.rb` (test only — no source change).

**Tests first.** This item *is* the test. Cover: symbol keys match;
string keys do **not** match today (documenting current behavior); `nil`
`case_id` raises `ArgumentError`; unrecognized payload shape returns `none`.

**Acceptance.** A failing test if someone changes the key contract without
noticing.

**Spec.** §6.3.

### 1.4 Release notes for Phase 1

**What.** 1.1 changes behavior for hosts whose steps currently fail silently:
they will start seeing errors. Those failures are real and already happening —
they are simply invisible. Frame it as "errors you already had, now visible."

**Files.** `docs/case-management-business-process.md`, and the PR description.
There is no `CHANGELOG.md` in this repo; if one is added, it belongs there too.

**Spec.** §11.5.

---

## Phase 2 — Durable recording, delivery unchanged

Events get written down. Delivery stays synchronous and in-process, so nothing
about timing changes for hosts. Satisfies the "replayable history" half of the
intent at low risk, and proves out the payload work before anything depends
on it.

0.1 is decided (Phase 0), so nothing here is gated.

### 2.1 Spike: after-commit hooks under transactional fixtures

**Do this first — it can invalidate 2.7.**

**What.** The outbox depends on `ActiveRecord.after_all_transactions_commit`
firing after the publisher's transaction commits. The suite runs with
`config.use_transactional_fixtures = true` (`spec/rails_helper.rb:68`), which
wraps each example in a transaction that is rolled back. Rails marks that
wrapper non-joinable so commit hooks still fire for inner transactions, but that
interaction has never been exercised in this repo — there are no `after_commit`
callbacks anywhere today.

Timebox it. Write one throwaway spec that opens a transaction, registers an
after-commit hook, and asserts it runs. If it does not fire, 2.7 needs a
different mechanism and the spec needs revising before any more work lands.

**Acceptance.** A documented yes/no, and if no, a named alternative.

### 2.2 Migration generator

**What.** `strata:events` generator installing both tables, modelled on
`lib/generators/strata/audit_log/audit_log_generator.rb` (D1):
`Rails::Generators::Base`, `source_root File.expand_path("templates", __dir__)`,
a `create_migration_file` writing a hand-rolled
`Time.now.utc.strftime("%Y%m%d%H%M%S")` timestamp, then a
`--skip-migration-check` guarded `table_exists?` check offering `db:migrate`.
Nothing in this repo uses `Rails::Generators::Migration`; do not introduce it.

DDL per D2 and D3 — raw `t.uuid`/`t.string`, explicit named indexes after the
block, `t.jsonb :payload, null: false, default: {}`, `id: :uuid, default: -> { "gen_random_uuid()" }`:

```ruby
create_table :strata_events, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
  t.string :name, null: false
  t.jsonb  :payload, null: false, default: {}
  t.uuid   :publisher_id
  t.string :publisher_type
  t.datetime :created_at, null: false        # events are append-only
end

create_table :strata_event_deliveries, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
  t.uuid   :strata_event_id, null: false
  t.string :subscriber_key,  null: false
  t.uuid   :target_id
  t.string :target_type
  t.integer :status,   null: false, default: 0
  t.integer :attempts, null: false, default: 0
  t.string :from_step
  t.text   :last_error
  t.datetime :completed_at
  t.timestamps                                # deliveries are mutable
end
```

Indexes: `strata_events` on `name`/`created_at` and `[:name, :created_at]`;
`strata_event_deliveries` unique on
`[:strata_event_id, :subscriber_key, :target_type, :target_id]` (this is what
makes FR-7 enforceable in the database rather than by convention) plus
`[:status, :created_at]`.

**Files.** `lib/generators/strata/events/events_generator.rb`,
`templates/create_strata_events.rb.tt`, `USAGE`.

**Tests first.** Copy
`spec/lib/generators/strata/generators/audit_log_generator_spec.rb` — it is the
closest template (`Dir.mktmpdir` root, `invoke_all`, stub
`ActiveRecord::Base.connection.table_exists?`, glob `db/migrate/*` and regex the
content). Assert: UUID pk, jsonb default, the unique index, `t.timestamps` on
deliveries but not events, `--skip-migration-check` short-circuits, the decline
path warns.

**Acceptance.** Generator spec green; generated migration matches house style.

**Spec.** §5.2.

### 2.3 Dummy app migration

**What.** Run the generator against `spec/dummy` and commit the result.
`spec/dummy/db/schema.rb` is regenerated by `db:migrate` — **never edit it
directly** (CLAUDE.md hard rule). Run `make db-test-prepare` after.

**Files.** `spec/dummy/db/migrate/<ts>_create_strata_events.rb`,
`spec/dummy/db/schema.rb` (generated).

### 2.4 Models

**What.** `Strata::Event` and `Strata::EventDelivery`, both under
`Strata::ApplicationRecord`, following `app/models/strata/audit_line.rb`:
explicit `self.table_name`, `attribute :payload, :jsonb, default: {}`, scopes
rather than scattered `where` calls, and `readonly?` returning `persisted?` on
`Strata::Event` (events are immutable once published; deliveries are not).

`EventDelivery` uses the engine's enum style (`app/models/strata/task.rb:33`):
`enum :status, pending: 0, succeeded: 1, failed: 2, no_match: 3, dead: 4`
paired with `attribute :status, :integer, default: 0`.

Scopes: `dead`, `unresolved`, `stale(cutoff)`, `for_target(record)`,
`latest_first`.

**`no_match` is a distinct state, not a success.** Today an event that does not
match the case's current step returns early and vanishes
(`business_process_instance.rb:61`). Recording it is what makes "why didn't my
case move?" answerable.

**Files.** `app/models/strata/event.rb`, `app/models/strata/event_delivery.rb`,
`spec/factories/strata/strata_event_factory.rb`,
`spec/factories/strata/strata_event_delivery_factory.rb`.

**Tests first.** Validations, every scope, the enum, immutability of
`Strata::Event`, and the unique-index constraint surfacing as a caught
violation rather than a 500.

**Spec.** §5.2.

### 2.5 Payload serialization

**What.** `ActiveJob::Arguments.serialize` / `.deserialize` rather than raw
JSON. It preserves symbol keys via `_aj_symbol_keys` (which is what keeps
`Case.for_event` working — see 1.3), turns ActiveRecord objects into GlobalIDs,
and stores a reference rather than a snapshot of the record's attributes. That
last property is also a security argument for this choice over the obvious one:
`{ kase: kase }` from `rake strata:events:publish_case_event`
(`lib/tasks/strata_events.rake:24`) serializes to `gid://dummy/PassportCase/<uuid>`
instead of persisting every column.

Note there is no GlobalID or `ActiveJob::Arguments` usage anywhere in the repo
today (D4) — this is new ground, so the tests matter more than usual.

Two behaviors to handle explicitly, not discover at runtime:

- **A replayed event sees current state, not publish-time state.** Correct for
  ID-keyed transition events, wrong for any payload meant to capture a value at
  a point in time. Document it.
- **A deleted record makes the payload undeserializable.**
  `GlobalID::Locator` raises `ActiveRecord::RecordNotFound`. Terminal: mark the
  delivery `dead` with a clear error. Do not retry — retrying cannot help.

**Files.** `app/helpers/strata/event_manager.rb` or a new
`app/lib/strata/events/payload.rb`.

**Tests first.** Data-driven round trip across: symbol-keyed hash, nested hash,
AR object, `nil`, empty hash, `Time`/`Date`, oversized payload, and a
non-serializable object — which must raise a clear error **at publish**, not at
delivery. Plus the deleted-GlobalID case.

**Spec.** §5.3.

### 2.6 Configuration module

**What.** `Strata::Events` with `mattr_accessor` for `durable`, `queue_name`,
`max_attempts`, `retention_period` — following the only existing configuration
precedent in the engine, `app/services/strata/task_service.rb:14`. There is no
`Strata.configure` block and this work should not invent one.

`durable` auto-disables with a one-time warning when the tables are absent, so a
host that upgrades the gem before running the migration keeps working (NFR-3).

**`retention_period` defaults to `nil`, not `90.days`** (0.1). Nothing is pruned
until a host sets it deliberately.

**Files.** `app/lib/strata/events.rb`.

**Tests first.** Defaults — including that `retention_period` is `nil` out of
the box; the tables-absent fallback warns exactly once and leaves `durable?`
false.

**Spec.** §5.8.

### 2.7 `publish` writes rows

**What.** `publish` serializes, inserts the event and its pending deliveries
inside the caller's transaction, and registers the enqueue for after commit.
Delivery itself stays synchronous in this phase. Returns the `Strata::Event`
instead of `nil` — additive, since the previous return value was the
`instrument` result, which no caller uses. Confirm that during implementation.

This is what fixes the `after_create`/rollback hazard: `ApplicationForm` and
`Task` publish from `after_create`/`after_update`, which run *inside* the
enclosing transaction, so a rollback today fires handlers for a write that never
happened.

**Depends on 2.1.**

**Files.** `app/helpers/strata/event_manager.rb`.

**Tests first.** FR-1 (row exists after publish); FR-6 (publish inside a
rolled-back transaction leaves no event and no enqueue); publish outside any
transaction still works; the existing `publish_event_with_payload` matcher
still passes unchanged.

**Spec.** §5.5.

### 2.8 Operator rake tasks — status and prune

**What.** Extend `lib/tasks/strata_events.rake`:
`strata:events:status[event_id]` and `strata:events:prune[days]` (FR-10).
Backed by the model scopes from 2.4, per the data-modeling guideline that
queries live in scopes.

Per 0.1, `prune` is **a no-op with a clear message when `retention_period` is
`nil`** — it must say it did nothing and why, not exit silently. A prune task
that quietly does nothing is its own trap, and the deliberate-opt-in design
means that is the default state every host starts in.

**Files.** `lib/tasks/strata_events.rake`,
`spec/lib/tasks/strata_events_spec.rb`.

**Tests first.** Prune with `retention_period` set deletes only rows older than
the cutoff; prune with it `nil` deletes nothing and reports why; an explicit
`[days]` argument overrides the configured value.

**Spec.** §5.9, §8.1.

### 2.9 Documentation

**What.** A `docs/strata-events.md` covering the event API, the
identifier-only payload rule (§8.1), and the operator tasks. Add it to
`docs/README.md`. Add `strata:events` to `docs/generators.md` in the house
format (`### strata:events`, one sentence, `[See full usage guide](...)`, then a
bash block).

> Note: `docs/generators.md` currently omits `strata:audit_log` and
> `strata:determination` entirely. Worth fixing separately — not this work.

Also fold the D1–D6 corrections back into `spec.md`.

**Phase 2 review agenda.** Per 0.2, closing the audit-log PII ADR question is an
explicit item on the Phase 2 review, not an afterthought. The reviewer should
come out of it with one of: an ADR update reopening the redaction decision, or a
recorded judgement that caller discipline extends to framework-composed
payloads. Either is fine; leaving it undecided is not, because the payload store
ships in this phase.

---

## Phase 3 — Durable delivery

Delivery moves to ActiveJob. **This is where behavior changes for hosts.**

0.3 and 0.4 are decided (Phase 0), so nothing here is gated.

### 3.1 Durable vs. legacy subscriber split

**What.** `subscribe` registers a callback down **exactly one** path — durable
or legacy, never both. Registering a durable subscriber with
`ActiveSupport::Notifications` as well would run it twice per event: once inline
from `legacy_publish`, once from its delivery job.

A callback is durably addressable when it is a `Method` bound to a named class
or module. `Strata::BusinessProcess` passes `method(:handle_event)`
(`app/models/strata/business_process.rb:114`), so **every SDK subscriber becomes
durable with no call-site changes.** Host lambdas take the legacy branch and
behave exactly as they do today.

Both branches return a handle `unsubscribe` accepts, keeping the public
interface unchanged (NFR-1). `unsubscribe_all` must clear both registries so the
Zeitwerk reload hook (`lib/strata/engine.rb:51-55`) stays correct.

The `durable?` flag is read at **subscribe** time, so it must be set before the
host's `config.after_initialize { XBusinessProcess.start_listening_for_events }`
(`spec/dummy/config/application.rb:40`). Raise on a post-registration flip
rather than failing quietly.

**Files.** `app/helpers/strata/event_manager.rb`.

**Tests first.** `durable_reference?` across `method(:x)` on a named class, on
an anonymous class, a lambda, a proc, a callable object, and `nil`; a durable
subscriber is **not** registered with Notifications; `unsubscribe` accepts both
handle types; `unsubscribe_all` clears both; a post-registration flag flip
raises.

**Spec.** §5.4.

### 3.2 Delivery job

**What.** `Strata::EventDeliveryJob < Strata::ApplicationJob`, with
`retry_on StandardError, wait: :polynomially_longer, attempts: Strata::Events.max_attempts`
and `discard_on ActiveJob::DeserializationError` (2.5). `Strata::ApplicationJob`
is an empty subclass today and gains no shared behavior from this.

**Files.** `app/jobs/strata/event_delivery_job.rb`.

**Spec.** §5.6.

### 3.3 Idempotency and per-case serialization

**What.** The job locks the delivery, returns early if already `succeeded`
(FR-7), resolves the subscriber from `subscriber_key`, calls it, and marks the
delivery — all in one transaction, so the case's step change and the
"this was applied" record commit together. That is what closes the gap from 1.2
at the delivery layer.

Per-case serialization (FR-8) comes from `Case.lock.find` inside
`BusinessProcessInstance`.

**Tests first.** Running the same job twice produces one step advance and one
task; two concurrent jobs on one case serialize; a `no_match` is recorded rather
than vanishing.

**Spec.** §5.6, §5.7.

### 3.4 Retry and dead-letter policy

**What.** Failed deliveries retry with backoff, then land in `dead` with
`last_error` populated. Never silently dropped (FR-3).

**Tests first.** A raising subscriber retries then dead-letters — **this test
fails today** because of 1.1, so it is the regression guard for that fix.

**Spec.** §5.6, §11.3.

### 3.5 Per-step `retryable: false`

**What.** A step can declare that it must not be retried, so a delivery that
fails dead-letters on the first failure instead of running the callback again.
This is the main structural guard against the duplicate-payment risk: a
`SystemProcess` callback that issues a payment and fails *after* the external
call but before commit will otherwise be retried, and the transaction rolls back
the database but not the HTTP request that already happened.

Add a `retryable:` option to the step helpers in
`app/models/strata/business_process_builder.rb` (`system_process`, `staff_task`,
`applicant_task`, `third_party_task`), defaulting to `true` so nothing changes
for existing definitions. `Strata::Step` carries the flag; the delivery job
reads it and skips `retry_on` for a non-retryable step.

**Files.** `app/models/strata/business_process_builder.rb`,
`app/models/concerns/strata/step.rb`, `app/models/strata/system_process.rb`,
`app/jobs/strata/event_delivery_job.rb`.

**Tests first.** A retryable step that raises retries then dead-letters; a
`retryable: false` step that raises dead-letters immediately with `attempts` at
1; the default is retryable when the option is omitted; the flag survives a
business process definition round trip.

**Acceptance.** A host can mark a step non-idempotent and trust it will not be
called twice by the retry machinery.

**Spec.** §11.3 (decision 0.3).

### 3.6 Replay

**What.** `strata:events:replay[delivery_id]` and
`strata:events:replay_dead[event_name]` (FR-5). Rake-only — replay re-executes
a business process step and can create tasks, close cases, or call an external
system. If it is ever exposed over HTTP it needs a Pundit policy and an audit
entry.

**Spec.** §5.9, §8.2.

### 3.7 Test helpers

**What.** Ship `Strata::Events::TestHelpers` so host apps have a supported
migration path rather than each inventing one. It ships from the gem alongside
`lib/strata/testing/api_auth_helpers.rb`, which is the existing precedent for a
test helper the engine exports.

This has to include wiring up `ActiveJob::TestHelper` and the `:test` queue
adapter — neither exists in this repo today (D4), and `spec/rails_helper.rb`
has no ActiveJob configuration at all.

**Files.** `lib/strata/testing/event_helpers.rb`, `spec/rails_helper.rb`.

**Spec.** §7.

### 3.8 Migrate the SDK's own specs

**What.** Update every spec that assumes synchronous delivery. Per D5 this is
wider than spec §7 lists — start from the full list there and re-grep before
starting, since the incidental cases do not mention `EventManager` at all.

`spec/support/matchers/publish_event_with_payload.rb` needs particular care: it
subscribes, calls the block, and unsubscribes in an `ensure` immediately
afterwards, so under async `@event_triggered` is still false when evaluated.
**Host apps inherit this matcher, so its behavior is itself a compatibility
surface** — it must keep working for both paths.

Watch `spec/factories/strata/strata_test_case_factory.rb`: its
`find_or_create_by!` exists because the event path may or may not have created
the case. Under async the factory will always create it directly, and the job
may then try again.

Also note `spec/spec_helper.rb` has random ordering disabled — specs run in
defined order, which can mask inter-example coupling that async delivery would
expose.

**Spec.** §7.

### 3.9 Dummy app queue backend

**What.** No queue adapter is configured in any environment and no
background-job gem is in `Gemfile` or `strata.gemspec` (D4). Per 0.4 the engine
stays **adapter-agnostic** — it declares no backend and adds no gem; hosts
choose their own. Wire the `:test` adapter into `spec/rails_helper.rb` alongside
the 3.7 helpers so the suite can run.

**Limitation, stated plainly:** Phase 3 cannot then be exercised against a real
queue locally — only in a host app that has one. Anyone validating the retry and
dead-letter behavior end to end needs to do it somewhere with a real backend.

### 3.10 Upgrade notes

**What.** The upgrade path (spec §10), with step 5 the most prominent line:

> **Audit `SystemProcess` callbacks for idempotency before enabling in
> production.** At-least-once delivery means a callback that calls an external
> system and fails *after* the call but before commit will call again on retry.
> The transaction rolls back the database; it cannot roll back an HTTP request
> that already happened. In a benefits context that is a duplicate payment.

**Spec.** §10, §11.3.

---

## Test strategy

- Tests are written and **approved before implementation** for every non-trivial
  item (CLAUDE.md).
- Follow [testing.md](../../contributing/testing.md): multiple scenarios,
  data-driven where the same assertion repeats over inputs, and explicit `nil`,
  oversize, and error cases. Serialization (2.5) is the clearest data-driven
  candidate.
- `spec/support` is **not** glob-loaded — the glob at `spec/rails_helper.rb:45`
  is commented out. New matchers and helpers must be `require`d per-spec, as
  `publish_event_with_payload` is today.
- Engine factories live in `spec/factories/strata/` and are registered by
  `lib/strata/engine.rb:27-31`; dummy factories live in
  `spec/dummy/spec/factories/`. Name files `*_factory.rb`.
- The suite uses transactional fixtures, not DatabaseCleaner. See 2.1 for why
  that matters here.

## Sequencing

Phase 0 is closed, so nothing below waits on a decision.

```
1.1 ─► 1.2 ─► 1.3 ─► 1.4 ─────────────────────► [Phase 1 ships]
                                                      │
                          2.1 ◄───────────────────────┘
                           │   (spike first — a negative result invalidates 2.7)
       ┌───────────────────┼───────────────────┐
       ▼                   ▼                   ▼
   2.2 ─► 2.3             2.5                 2.6
       └────┴──────► 2.4 ─► 2.7 ─► 2.8 ─► 2.9 ─► [Phase 2 ships]
                                                      │
                                                      ▼
   3.1 ─► 3.2 ─► 3.3 ─► 3.4 ─► 3.5 ─► 3.6 ─────► [Phase 3 ships]
    └──► 3.7 ─► 3.8              3.9 ─► 3.10
```

Parallelizable: 2.2/2.3 (migration), 2.5 (serialization) and 2.6 (config) are
independent once 2.1 answers. 3.7 can start as soon as 3.1 lands, and 3.9 is
independent of the whole 3.1–3.6 chain.

## Risks

| Risk | Phase | Mitigation |
| --- | --- | --- |
| Retries double-fire external side effects — a duplicate payment or notice | 3 | **3.5 ships the per-step `retryable: false` opt-out** (decision 0.3), plus idempotency docs, low `max_attempts`, and a prominent upgrade note. **Still the sharpest risk in this work** (§11.3) |
| Prune deletes records that must be kept | 2 | Decision 0.1 — `retention_period` defaults to `nil`, so pruning is opt-in and cannot fire unreviewed |
| After-commit hooks do not fire under transactional fixtures | 2 | 2.1 spike, first |
| Silent no-ops become visible and the first `no_match` counts look alarming | 2 | Warn teams in advance; it is the first honest measurement, not a regression (§11.4) |
| Phase 1 surfaces failures hosts already had | 1 | 1.4 release notes (§11.5) |
| Async breaks host specs in ways we cannot see from here | 3 | 3.7 ships helpers with the change rather than leaving hosts to invent them |

## Definition of done

**Phase 1** — no `rescue Exception` in `business_process_instance.rb`; no state
where a case advanced without its step running; characterization test on
`for_event`; release note written; `make lint` and `make test` green.

**Phase 2** — generator installs both tables with a passing generator spec; the
dummy app is migrated via `db:migrate` (never by editing `schema.rb`); publish
writes rows inside the caller's transaction; rollback leaves nothing behind;
delivery timing is unchanged and every existing spec passes untouched;
`retention_period` defaults to `nil` and prune is a reported no-op without it;
the audit-log PII ADR question is closed at review (0.2); docs updated;
`make lint` and `make test` green.

**Phase 3** — a subscriber is registered down exactly one path; the same
delivery applied twice produces one effect; a raising subscriber retries then
dead-letters; a `retryable: false` step dead-letters on its first failure
instead of retrying; replay works from rake; test helpers ship; every SDK spec
migrated; `Strata::Events.durable` defaults **off** for at least one release;
upgrade notes carry the idempotency warning; `make lint` and `make test` green.
