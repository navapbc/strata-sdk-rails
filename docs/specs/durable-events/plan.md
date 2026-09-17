# Implementation Plan: Durable events

## Status

Draft — for engineering review. No implementation has started.

**Revised 2026-09-17** against the amended spec (commit `f555a75` on
[PR #378](https://github.com/navapbc/strata-sdk-rails/pull/378)). That revision
added FR-11, §5.5a, §5.5b, §5.6a and §6.4, moved §6.1's exception propagation
out of Phase 1, and settled four decisions in §13. Everything it forced on this
plan is listed in
[What the amended spec changed here](#what-the-amended-spec-changed-here).

**Seven further questions were settled the same day.** Five are recorded in
§13 — the `no_match` mechanism, the retention default, target resolution
timing, `retryable: false`, and `publish`'s return value — and two more in the
spec body: the generator is `strata:events` (D1, §10) and the dummy app
configures Solid Queue ([3.9](#39-dummy-app-queue-backend), §5.8). **Nothing in this plan is
blocked on a design question any more** — Phase 2's merge gate is lifted and
Phase 1's caveat is closed. What remains open needs a named owner rather than a
decision; see [Phase 0](#phase-0--decisions).

## Date

2026-09-15, revised 2026-09-17

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
- **One PR per phase, minimum.** Phase 1 is a single PR — items 1.1 and 1.2
  are one change and must not be split. Phase 2 is now large enough to split;
  the migration and models are separately reviewable from the router and the
  publish path. Phase 3 should be split at least three ways.
- **Each work item carries** what changes, which files, the tests to write
  first, acceptance criteria, and the spec section it implements.
- **`make lint` and `make test` must both pass before every push**
  (CLAUDE.md hard rule). CI runs `lint-ci` and `test` as a matrix; both legs run
  `make setup`, so both need the Postgres container.

---

## What the amended spec changed here

Nine things. The first is the largest, and it inverts what Phase 1 does.

| # | Amendment | Effect on this plan |
| --- | --- | --- |
| 1 | **§6.1's exception propagation moved from Phase 1 to Phase 3**, replaced in Phase 1 by a publish-boundary rescue (§9.1, §13) | The old 1.1 — "propagate exceptions out of step execution" — is **withdrawn as written**. Phase 1 is now [1.1](#11-let-the-step-raise-and-roll-back-the-step-change-with-it)+[1.2](#12-rescue-at-the-publish-boundary) shipping together, and propagation becomes [3.3a](#33a-remove-the-publish-boundary-rescue) |
| 2 | **§6.4 added as a fourth blocking defect**, placed in Phase 1 | New item [1.3](#13-report-an-outcome-from-transition_to_next_step) |
| 3 | **FR-11 and §5.5b added** — the sweeper is required, not optional | New item [3.2a](#32a-stranded-delivery-sweeper-fr-11), plus `stranded_after` config and a `stranded` scope |
| 4 | **§5.5a added** — `targets_for` became `Strata::Events::Router`, with a start-event rule and `target_key` as a NOT NULL discriminator | New item [2.4b](#24b-target-resolution-router), new DDL column and a changed unique index in [2.2](#22-migration-generator), and a sequencing conflict recorded as [D8](#deltas-from-the-spec) |
| 5 | **§5.6a added** — handlers return `:transitioned` / `:no_match` | Drives [1.3](#13-report-an-outcome-from-transition_to_next_step) and `EventDelivery.status_for` in [2.4](#24-models) |
| 6 | **NFR-4 tightened and §5.8 refuses to boot on `:async`** | **Supersedes decision 0.4.** [3.9](#39-dummy-app-queue-backend) is rewritten; the engine still ships no queue gem but is no longer indifferent to the adapter |
| 7 | **FR-8's lock moved to the case row** (§5.6, §13) | The old 3.3's `Case.lock.find` claim is corrected to `EventDelivery#with_locked_target` |
| 8 | **§11.2 answered the audit-log ADR question** and dropped `payload_filter` for identifier-only payloads enforced in development and test | **Closes decision 0.2**, differently than this plan had it. New item [2.5a](#25a-identifier-only-payload-enforcement) replaces a review-agenda item |
| 9 | **§9.2 withdrew "Phase 2 is behavior-free"** and §10 gained a pre-flight check | Phase 2's framing and its definition of done are corrected; `check_payloads` lands in [2.8](#28-operator-rake-tasks--status-prune-and-check_payloads) and runs *before* the phase |

Two things the amendment left disagreeing with this plan, **both since
resolved in the spec's favour of this plan's position**:

- **Retention.** §5.8 defaulted `retention_period` to `90.days` while §11.1
  made the policy owner's sign-off a Phase 2 merge blocker. Settled 2026-09-17:
  the default is `nil`, pruning is opt-in, and §11.1 no longer gates the merge.
  This plan's 0.1 recommendation is now the spec's position.
- **`retryable: false`.** §12 had it open and §11.3 called it "not yet
  designed" while this plan had it in scope. Settled: it ships with Phase 3,
  §11.3 now carries what is left to design, and §9.3 names it.

---

## Deltas from the spec

Reconnaissance against the current code turned up nine places where the spec's
design is right but its detail is wrong, or where it contradicts itself. Fix
these in the spec as part of Phase 2, or carry them as known corrections.

**D1 — `strata:audit_log` is the generator precedent, not `strata:task`.**
Spec §5.2 says "following the `strata_tasks` precedent." The closer match is
`lib/generators/strata/audit_log/audit_log_generator.rb`: a
`Rails::Generators::Base` whose only job is installing a migration, with the
model shipped by the engine. That is exactly this case. The task generator is
`NamedBase` and writes a model plus a migration only if the user accepts a
prompt.

Relatedly, the spec named the generator two ways — §5.2 implied
`strata:events` while §10 step 2 said `strata:events_migration`. Both patterns
exist in `lib/generators/strata/` (`audit_log` installs a migration under a
bare name; `income_records_migration` carries the suffix). **Settled:
`strata:events`**, matching the `audit_log` precedent this delta already points
at; §10 is corrected.

**D2 — the DDL is off house style, but the cascade FK is not.** Spec §5.2
writes `t.references :strata_event, null: false, type: :uuid, foreign_key: { on_delete: :cascade }`.
No `strata_*` migration in this repo uses `t.references`; all of them declare
raw `t.uuid :foo_id` plus `t.string :foo_type` and add explicit named indexes
after the `create_table` block.

The foreign key itself is a different matter, and the earlier version of this
delta was wrong to lump them together. There *is* precedent for exactly the
cascade the spec needs:
`spec/dummy/db/migrate/20250327160205_create_passport_cases.rb:14` does
`add_foreign_key :passport_application_forms, :passport_cases, column: :case_id, primary_key: :id, on_delete: :cascade`,
and `20250523152845_add_strata_tasks_to_users_relationship.rb:5` does the same
with `on_delete: :nullify`. So the house form is raw `t.uuid` columns plus an
explicit `add_foreign_key ..., on_delete: :cascade` after the block — which
keeps §5.2's load-bearing cascade (FR-10's `prune` raises
`ActiveRecord::InvalidForeignKey` without it) and house style at the same time.
See [2.2](#22-migration-generator).

**D3 — `strata_events` carries both `t.timestamps` and `published_at`, which is
one column too many.** The house rule is `t.timestamps` for mutable rows
(`strata_tasks`) and a bare `t.datetime :created_at, null: false` for
append-only rows (`strata_audit_lines`, `strata_determinations`). Spec §5.2
gives `strata_events` both `published_at, null: false` *and* `t.timestamps`,
so every row carries two timestamps that are always equal and an `updated_at`
that never changes. Events are append-only; collapse to one column. Deliveries
are mutable, so their `t.timestamps` is correct as written.

If `published_at` is kept over `created_at`, note that §5.9's `stranded` and
`stale` scopes and §5.2's `[:status, :created_at]` index are all written
against `created_at` — pick one name and use it everywhere.

**D4 — there is no ActiveJob infrastructure of any kind to build on, and the
amendment widened what has to exist.** No job in the engine or dummy app does
work; there is no `perform_later` anywhere, no queue adapter configured in any
environment (`spec/dummy/config/environments/production.rb:73` leaves it
commented out, so the dummy app inherits `:async`), and no background-job gem
in either `Gemfile` or `strata.gemspec`. `Strata::ApplicationJob` is an empty
subclass. Spec §7's test plan assumes `perform_enqueued_jobs` is available; it
is not — `ActiveJob::TestHelper` is not included anywhere.

Phase 3 now additionally needs a *scheduled* job (§5.5b) and a boot-time
adapter deny-list (§5.8) on top of that, so the gap is wider than it was.
See [3.7](#37-test-helpers) and [3.9](#39-dummy-app-queue-backend).

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

**D6 — resolved 2026-09-17; kept for the record.** §5.8 set
`retention_period = 90.days` while §11.1 made the policy owner's confirmation a
**Phase 2 merge blocker**, so the spec gated a phase on an answer engineering
cannot produce. §5.8, §8.1 and §11.1 now carry the `nil` default and opt-in
pruning this plan recommended, and §11.1 gates a host enabling pruning instead
of gating the merge. Nothing to fix; noted because the reasoning is the reason
[2.8](#28-operator-rake-tasks--status-prune-and-check_payloads) must report
that it pruned nothing rather than exiting silently.

**D7 — `id: :uuid` alone does not match house style.** Spec §5.2 writes
`create_table :strata_events, id: :uuid`. Every table in
`spec/dummy/db/schema.rb` is `id: :uuid, default: -> { "gen_random_uuid()" }`,
and `create_strata_audit_lines.rb` writes it that way. Note the engine's own
`create_strata_tasks.rb.tt` template omits the default, so the templates are
already inconsistent; follow the schema and the audit-log migration.

**D8 — the router (Phase 2) needs a registry the spec builds in Phase 3.**
§5.5a's `Router` calls `Strata::EventManager.durable_subscribers_for(event_key)`
and `Strata::EventManager.owner_of(subscriber_key)`. Neither exists, and
neither can be built from today's registry: `@@subscriptions` is a **flat
array** of opaque `ActiveSupport::Notifications` subscriber objects
(`app/helpers/strata/event_manager.rb:21,30-38`) with no event key, no callback
reference, and no owner. There is nothing to look a `subscriber_key` up from.

That registry is the §5.4 work, which §9.3 puts in Phase 3 — but §9.2 puts the
router in Phase 2. As written, Phase 2 cannot be built.

Recommended split, and the one this plan assumes: **the registry moves to Phase
2, the registration split stays in Phase 3.** Phase 2 adds a keyed registry
recording `event_key => [{ subscriber_key:, callback:, owner: }]` plus
`durable_reference?`, while *still* registering every subscriber with
`ActiveSupport::Notifications` exactly as today. Delivery timing is unchanged,
the registry only supplies names for the delivery rows, and Phase 3's job is
then just to stop registering durable subscribers with Notifications. See
[2.4a](#24a-durable-subscriber-registry) and [3.1](#31-durable-vs-legacy-subscriber-split).

**D9 — `handle_event` and `start_event?` look private and are not.**
`app/models/strata/business_process.rb:131` writes `private` and line 133 opens
`class << self`. `private` applies to instance methods of the enclosing class,
so it has no effect on the singleton methods defined in that block —
`handle_event`, `create_case_from_event` and `start_event?` are all public
class methods. The router's `process.respond_to?(:start_event?)` guard (§5.5a)
therefore works as written, and `process.case_class`
(`business_process.rb:63`) is public too. Worth noting because the code reads
as though the router is reaching into a private API, and because the ineffective
`private` is itself worth a separate cleanup.

---

## Phase 0 — Decisions

**All four are settled, and no phase is gated on a design question.**

| # | Question | State | Notes |
| --- | --- | --- | --- |
| 0.1 | Retention and encryption for `strata_events.payload` | **Closed 2026-09-17, in the spec.** `retention_period` defaults to `nil`; pruning is opt-in; §11.1 is no longer a Phase 2 merge blocker | The `nil` default is now §5.8's, so [2.6](#26-configuration-module) and [2.8](#28-operator-rake-tasks--status-prune-and-check_payloads) can be written and merged. The retention *obligation* and encryption-at-rest are still open and still need the data-policy owner — but they now block a **host enabling pruning**, not this work. Say so in the upgrade notes ([3.10](#310-upgrade-notes)) |
| 0.2 | Does a framework-written payload store reopen [audit-log-pii-redaction.md](../../decisions/audit-log-pii-redaction.md)? | **Closed by the spec.** §11.2 answers it: separate features, that ADR does not govern this one, and `payload_filter` is dropped | Closed differently than this plan had it — there is no longer a Phase 2 review-agenda item, there is a **work item**: [2.5a](#25a-identifier-only-payload-enforcement), the development-and-test check that makes NFR-7 real |
| 0.3 | Does `retryable: false` per step ship with Phase 3? | **Yes, and the spec now says so too.** §11.3 and §9.3 name it, and §12 no longer lists it | [3.5](#35-per-step-retryable-false) is in scope. §11.3 now carries the design sketch this plan's item was ahead of, so the two documents agree |
| 0.4 | What queue backend? | **Superseded by the amended spec.** NFR-4 requires a *durable* backend, §5.8 refuses to boot on `:async`/`:inline`/`:test`-outside-test, and §13 prefers a same-database backend | "Adapter-agnostic" survives only in the narrow sense that the engine ships no queue gem and hosts choose. It is no longer indifferent: it refuses adapters, prefers Solid Queue or GoodJob, and requires the FR-11 sweeper regardless. [3.9](#39-dummy-app-queue-backend) is rewritten |

Two more questions this plan flagged were closed the same day and are recorded
in §13:

- **The `no_match` mechanism** (§13) — return value, not a
  `NoMatchingTransition` exception. This was the only thing gating Phase 1;
  [1.3](#13-report-an-outcome-from-transition_to_next_step) can proceed as
  written.
- **Target resolution timing** (§13) — publish time. So
  [2.4b](#24b-target-resolution-router) exists as specified, and `target_key`
  keeps its uniqueness role.

Two were answered from the code rather than decided, and both removed work
rather than adding it:

- **`publish` can return the `Strata::Event`** (§13). None of the
  twelve `EventManager.publish` call sites in the engine, the dummy app or the
  suite reads the current return value, so [2.7](#27-publish-writes-rows) needs
  no compatibility shim and no confirmation step.
- **`rake strata:events:publish_case_event` has no user in this repo** (§6.5,
  and §12 narrows to host usage) — no caller outside the task, no doc, and a
  spec that only checks argument validation against a stubbed `EventManager`,
  which is why §6.5's no-op went unnoticed.

  **Still open, deliberately, and it blocks nothing.** Whether a *host* calls
  it is the one question here nobody in this repo can answer, and it is also
  the one that answers itself if left alone: the task resolves no target, so
  [2.4b](#24b-target-resolution-router) writes an `"unmatched"` delivery row
  and it is recorded `no_match`, which means a host still running it finds out
  from the mechanism this work adds. Worth asking whoever added it (`06ba5eb`,
  Michael Crawford, 2025-06-09) before Phase 3 ships, and deleting rather than
  porting it if nothing depends on it.

**Still open, and none of it blocks a phase.** Four things now need a named
owner rather than a decision: the retention obligation, encryption-at-rest for
`payload`, who watches the `no_match` number (§11.4), and how long
`legacy_publish` lives. The first two gate a host turning pruning on; the third
decides whether the diagnostic this work adds is read by anyone; the fourth is
the only path by which FR-6 becomes unconditional.

---

## Phase 1 — Fix the blocking defects

No new behavior, no migration, no ActiveJob. **Everything after this is unsound
without it.** Ships on its own merits: it fixes real bugs in today's system.

Per §9.1 and §13, this phase is §6.2, §6.4, and a **publish-boundary rescue** —
*not* §6.1's full exception propagation. That waits for Phase 3
([3.3a](#33a-remove-the-publish-boundary-rescue)), because `publish` is called
from `after_create`/`after_update` and subscribers run inline, so a propagating
error today does not merely become visible: it rolls back the claimant's
submission. §6.1 has the full reasoning.

### 1.1 Let the step raise, and roll back the step change with it

**Ships in the same PR as [1.2](#12-rescue-at-the-publish-boundary). Neither is
safe alone** — see the note at the end of this item.

**What.** Two coupled changes in
`app/models/strata/business_process_instance.rb`:

1. `execute_current_step` (`:71-83`, the `rescue` at `:79`) wraps the step in
   `rescue Exception`, logs, and swallows. Log and re-raise instead. Narrow the
   rescue to `StandardError` so `SignalException` and `Interrupt` are never
   caught — a step currently resists Ctrl-C and absorbs the very termination
   signal this project exists to survive.
2. `transition_to_next_step` (`:59-67`) sets `current_step` and calls `save!`
   *before* `execute_current_step`. If the process dies between them, the case
   has advanced but the work never ran — and a retry computes the next step
   from the already-advanced step, finds no transition, and silently no-ops.
   Wrap both in one transaction so they commit or roll back together.

`start_from_event` (`:52-57`) has the same save-then-execute shape and needs
the same treatment.

Use `Strata::AuditLog.record` (`app/models/strata/audit_log.rb:59-65`) as the
house pattern for a transaction wrapping caller work.

**The transaction needs `requires_new: true`.** Events are published from
`after_create`/`after_update` and subscribers run inline, so in the path that
matters this runs inside the caller's open transaction — and a nested
`transaction` without it joins the outer one rather than opening a savepoint,
so the rollback undoes nothing. The failure mode is nasty: a spec that calls
`transition_to_next_step` directly gets a real transaction and passes, so the
fix looks correct and does nothing in production. This is the same trap as the
misleading `Strata::AuditLog` YARD note below.

**No row lock in this phase.** An earlier revision of this item called for one
per the aggregate-root guidance in
[data-modeling-guidelines.md](../../contributing/data-modeling-guidelines.md).
Deferred to [3.3](#33-idempotency-and-per-case-serialization): a lock changes
concurrency behavior, which this phase is explicitly meant not to do, and
FR-8's only test that proves a lock works — two concurrent jobs on one case —
lands there. Shipping it here would mean shipping a line no test in this phase
exercises.

**Files.** `app/models/strata/business_process_instance.rb`.

**Tests first.** A step that raises mid-execution leaves `current_step`
unchanged; a subsequent retry applies the transition correctly; a successful
transition still commits both; the error is still logged; `Interrupt` is not
swallowed. Add an explicit regression test for the "advanced but never
executed, retry no-ops" scenario — that is the bug.

**Acceptance.** No `rescue Exception` remains in the file, and no observable
state in which `current_step` has advanced but the step never ran.

**Spec.** §6.1, §6.2.

> **Why these are one change.** §6.2's transaction accomplishes nothing while
> the exception is still swallowed — nothing escapes, so nothing rolls back and
> the step change commits either way. And removing the swallow without
> [1.2](#12-rescue-at-the-publish-boundary) is the Phase 3 change landing
> early, which unwinds the caller's `save!`. Landing 1.1 and 1.2 together is
> strictly better than today with no new failure mode; landing either alone is
> not.

> **Note.** While here: the YARD note on `Strata::AuditLog`
> (`audit_log.rb:27-31`) claims an inner `transaction` becomes a savepoint under
> an outer one. It does not — `record` passes no `requires_new: true`, so the
> inner call joins the outer transaction. Out of scope for this work, but worth
> filing; it is a misleading contract on a shipped API.

### 1.2 Rescue at the publish boundary

**Ships in the same PR as [1.1](#11-let-the-step-raise-and-roll-back-the-step-change-with-it).**

**What.** With 1.1 in place, an exception from a step now escapes
`execute_current_step`, travels back through `transition_to_next_step` and
`BusinessProcess.handle_event`, and reaches
`ActiveSupport::Notifications.instrument` inside
`EventManager.publish` — which is running inside the transaction saving the
`ApplicationForm` or `Task` that published the event. Left alone it aborts that
`save!` and 500s the controller.

Rescue `StandardError` at the publish boundary in
`EventManager.publish`: log it with the event name and the subscriber, and
return. The step transaction from 1.1 has already rolled back, so the case is
not falsely advanced; the domain write survives.

**This rescue is temporary by design** and comes out in
[3.3a](#33a-remove-the-publish-boundary-rescue). Say so in a comment naming
§6.1, so it is not read as the intended end state.

**Files.** `app/helpers/strata/event_manager.rb`.

**Tests first.** A step that raises leaves the `ApplicationForm` saved and the
case not advanced; the error is logged once with the event name; a raising
subscriber does not prevent other subscribers to the same event from running;
`publish` still returns normally. This is the guard against
[3.3a](#33a-remove-the-publish-boundary-rescue) landing early.

**Acceptance.** A raising step no longer rejects a submission and no longer
leaves a falsely advanced case.

**Spec.** §6.1, §9.1, §11.5.

### 1.3 Report an outcome from `transition_to_next_step`

**What.** `transition_to_next_step` returns early and returns nothing
meaningful when no transition matches
(`app/models/strata/business_process_instance.rb:59-61`), so a caller cannot
distinguish "applied a transition" from "did nothing". That makes `no_match`
unreachable and would have the Phase 3 delivery job file every no-op as
`succeeded`.

Return `:no_match` / `:transitioned`, and aggregate in
`BusinessProcess.handle_event` (`business_process.rb:149-161`) over the cases
the event resolved to — `:transitioned` if any case moved, `:no_match` if none
did. An empty `for_event` result is `:no_match`, not a vacuous success. §5.6a
carries the pseudocode.

In Phase 1 nothing consumes the return value; this is the contract landing
ahead of the consumer, in the phase that already edits both methods.

**Files.** `app/models/strata/business_process_instance.rb`,
`app/models/strata/business_process.rb`.

**Tests first.** A matching transition returns `:transitioned`; a non-matching
event returns `:no_match` and leaves the case untouched; a start event returns
`:transitioned`; `handle_event` over several cases returns `:transitioned` when
any one moved; `handle_event` with an empty `for_event` result returns
`:no_match`.

**Acceptance.** A caller can tell a no-op from applied work.

**Spec.** §6.4, §5.6a, §13 — the return-value mechanism is settled, so this
item's contract is fixed. The rejected alternative, a `NoMatchingTransition`
exception, is argued in §5.6a; do not reintroduce it at review.

### 1.4 Pin the symbol-key contract in `Case.for_event`

**What.** `Case.for_event` (`app/models/strata/case.rb:75-88`) tests
`event[:payload].key?(:case_id)` with symbol keys. Any serialization that
stringifies keys makes it return `none` for every event — all deliveries
succeed, no case moves, silently. Phase 2 must not break this, and §5.5a's
router depends on it too. Add a characterization test now, before anything
touches serialization.

**Files.** `spec/models/strata/case_spec.rb` (test only — no source change).

**Tests first.** This item *is* the test. Cover: symbol keys match;
string keys do **not** match today (documenting current behavior); `nil`
`case_id` raises `ArgumentError`; unrecognized payload shape returns `none`.

**Acceptance.** A failing test if someone changes the key contract without
noticing.

**Spec.** §6.3.

### 1.5 Release notes for Phase 1

**What.** Phase 1 changes two things hosts can observe. Say both plainly:

- A step that used to fail silently and leave the case advanced anyway now
  leaves the case where it was and logs the error at the publish boundary. The
  failure was always happening; it is now visible and no longer corrupts the
  case's step.
- A step that raises no longer takes `Interrupt` or `SignalException` with it.

What Phase 1 does **not** do is reject the domain write — that is the change
deliberately held back to Phase 3 (`3.3a`), and the notes should say so, so a
host reading "errors are now visible" does not brace for rejected submissions a
release early.

**Files.** `docs/case-management-business-process.md`, and the PR description.
There is no `CHANGELOG.md` in this repo; if one is added, it belongs there too.

**Spec.** §11.5.

---

## Phase 2 — Durable recording, delivery unchanged

Events get written down. Delivery stays synchronous and in-process, so **timing**
is unchanged for hosts.

**This phase is not behavior-free, and the spec no longer claims it is** (§9.2).
`publish` now serializes the payload, and a payload `ActiveJob::Arguments`
cannot serialize raises inside the caller's `after_create` — which for
`ApplicationForm#publish_created` means rejecting a submitted form. For the
SDK's own identifier-only payloads the risk genuinely is near zero; for a host
publishing arbitrary objects it is a rejected domain write. That is why
`check_payloads` ([2.8](#28-operator-rake-tasks--status-prune-and-check_payloads))
runs *before* this phase reaches a host, not after.

**Gated at the merge by 0.1.** Work can start; per §11.1 it cannot merge until
the retention and encryption position is confirmed. [D6](#deltas-from-the-spec)
carries the recommendation that closes it.

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

**What.** `strata:events` generator (name settled — see D1) installing both
tables, modelled on
`lib/generators/strata/audit_log/audit_log_generator.rb` (D1):
`Rails::Generators::Base`, `source_root File.expand_path("templates", __dir__)`,
a `create_migration_file` writing a hand-rolled
`Time.now.utc.strftime("%Y%m%d%H%M%S")` timestamp, then a
`--skip-migration-check` guarded `table_exists?` check offering `db:migrate`.
Nothing in this repo uses `Rails::Generators::Migration`; do not introduce it.

DDL per D2, D3 and D7 — raw `t.uuid`/`t.string`, explicit named indexes and the
foreign key after the block, `id: :uuid, default: -> { "gen_random_uuid()" }`:

```ruby
create_table :strata_events, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
  t.string :name, null: false
  t.jsonb  :payload, null: false, default: {}
  t.uuid   :publisher_id
  t.string :publisher_type
  t.datetime :created_at, null: false        # events are append-only (D3)
end

create_table :strata_event_deliveries, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
  t.uuid   :strata_event_id, null: false
  t.string :subscriber_key,  null: false
  t.string :target_key,      null: false     # delivery identity; never NULL
  t.uuid   :target_id                        # nil for start / unmatched / unrouted
  t.string :target_type
  t.integer :status,   null: false, default: 0
  t.integer :attempts, null: false, default: 0
  t.string :from_step
  t.text   :last_error
  t.datetime :completed_at
  t.timestamps                               # deliveries are mutable
end

add_foreign_key :strata_event_deliveries, :strata_events,
                column: :strata_event_id, primary_key: :id, on_delete: :cascade
```

Indexes: `strata_events` on `name`, `created_at` and `[:name, :created_at]`;
`strata_event_deliveries` unique on
`[:strata_event_id, :subscriber_key, :target_key]` named
`index_strata_event_deliveries_uniqueness`, plus `[:status, :created_at]`.

**`target_key` and the cascade are both load-bearing, for different reasons.**

- **`target_key`.** The obvious index —
  `[:strata_event_id, :subscriber_key, :target_type, :target_id]` — enforces
  nothing for the rows that need it most. Start events and
  `rake strata:events:publish_event` resolve no target, so those columns are
  NULL, and Postgres treats NULLs as distinct in a unique index: two rows with
  the same event and subscriber are both accepted, permitting exactly the
  duplicate case creation FR-7 rules out. `target_key` is a NOT NULL
  discriminator written by the model — `"PassportCase/<uuid>"`, or the
  sentinels `"start"`, `"unmatched"`, `"unrouted"` from
  [2.4b](#24b-target-resolution-router). `nulls_not_distinct: true` is the
  other fix and is Postgres 15+ only, which the SDK cannot assume.
- **`on_delete: :cascade`.** Rails' `foreign_key: true` gives
  `ON DELETE NO ACTION`, and `prune`
  ([2.8](#28-operator-rake-tasks--status-prune-and-check_payloads)) deletes
  `strata_events` rows that still have delivery rows pointing at them. Without
  the cascade, FR-10 raises `ActiveRecord::InvalidForeignKey` the first time it
  runs. `dependent: :delete_all` on the model does not help, because prune uses
  `delete_all` and skips callbacks.

**Files.** `lib/generators/strata/events/events_generator.rb`,
`templates/create_strata_events.rb.tt`, `USAGE`.

**Tests first.** Copy
`spec/lib/generators/strata/generators/audit_log_generator_spec.rb` — it is the
closest template (`Dir.mktmpdir` root, `invoke_all`, stub
`ActiveRecord::Base.connection.table_exists?`, glob `db/migrate/*` and regex the
content). Assert: UUID pk with the `gen_random_uuid()` default, jsonb default,
`target_key` NOT NULL, the unique index on `target_key` (**not** on
`target_type`/`target_id`), the cascade FK, `t.timestamps` on deliveries but not
events, `--skip-migration-check` short-circuits, the decline path warns.

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

Scopes per §5.9: `dead`, `unresolved`, `stranded(older_than)`, `stale(cutoff)`,
`for_target(record)`, `pending`, `latest_first`. `stranded` is new with FR-11
and is what [3.2a](#32a-stranded-delivery-sweeper-fr-11) queries.

Behavior the delivery job depends on, defined here rather than in the job:

- `EventDelivery.status_for(outcome)` — `:no_match` maps to `no_match`,
  **anything else including an unrecognized value maps to `succeeded`**, so a
  host subscriber returning its own value is never mislabelled (§5.6a).
- `EventDelivery#with_locked_target` — `FOR UPDATE` on the target case row,
  a plain `yield` when `target_id` is blank. This is where FR-8 lives; see
  [3.3](#33-idempotency-and-per-case-serialization).
- `EventDelivery#resolve_subscriber` — constantizes `subscriber_key` back to a
  callable, against the registry from [2.4a](#24a-durable-subscriber-registry).
- `Event#to_callback_hash` — deserializes `payload` and returns
  `{ name:, payload: }`, the shape NFR-1 promises subscribers.
- `Event#deliveries` — the association `publish` and the sweeper both use.

**`no_match` is a distinct state, not a success.** Today an event that does not
match the case's current step returns early and vanishes
(`business_process_instance.rb:60-61`). Recording it is what makes "why didn't
my case move?" answerable, and [1.3](#13-report-an-outcome-from-transition_to_next_step)
is what makes it reachable.

**Files.** `app/models/strata/event.rb`, `app/models/strata/event_delivery.rb`,
`spec/factories/strata/strata_event_factory.rb`,
`spec/factories/strata/strata_event_delivery_factory.rb`.

**Tests first.** Validations, every scope, the enum, immutability of
`Strata::Event`, and the unique-index constraint surfacing as a caught
violation rather than a 500. `status_for` data-driven across `:transitioned`,
`:no_match`, `nil` and an unrecognized value. `with_locked_target` with a
blank `target_id` yields without querying.

**Spec.** §5.2, §5.6, §5.6a, §5.9.

### 2.4a Durable subscriber registry

**New item — see [D8](#deltas-from-the-spec).** [2.4b](#24b-target-resolution-router)
cannot be built without it, and today's registry cannot supply it.

**What.** `@@subscriptions` is a flat array of opaque Notifications subscriber
objects (`event_manager.rb:21`) — no event key, no callback, no owner. Replace
it with a keyed registry recording, per event key, the
`subscriber_key` (`"PassportBusinessProcess.handle_event"`), the callback, and
its owner, and add:

- `durable_reference?(callback)` — true when the callback is a `Method` bound
  to a named class or module, so the receiver and method name can be rebuilt in
  any process. `Strata::BusinessProcess` passes `method(:handle_event)`
  (`business_process.rb:114`), so every SDK subscriber qualifies with no
  call-site changes.
- `durable_subscribers_for(event_key)` and `owner_of(subscriber_key)` — what
  the router reads.

**In this phase every subscriber is still registered with
`ActiveSupport::Notifications`, exactly as today.** The registry only supplies
names for the delivery rows; it changes no delivery behavior. Splitting
registration is [3.1](#31-durable-vs-legacy-subscriber-split).

`unsubscribe` must keep accepting what `subscribe` returns (NFR-1), and
`unsubscribe_all` must clear the new registry as well so the Zeitwerk reload
hook (`lib/strata/engine.rb:51-55`) stays correct. Note §6.5's observation that
`@@subscriptions` is a thread-shared class variable — the new registry should
not repeat that pattern.

**Files.** `app/helpers/strata/event_manager.rb`.

**Tests first.** `durable_reference?` across `method(:x)` on a named class, on
an anonymous class, a lambda, a proc, a callable object, and `nil`;
`durable_subscribers_for` returns subscriber keys for a business process and
`[]` for an unknown event; `owner_of` round-trips to the class;
`unsubscribe` and `unsubscribe_all` clear both structures; **every existing
`EventManager` spec and the `publish_event_with_payload` matcher pass
unchanged**, which is the whole point of doing this without the split.

**Spec.** §5.4 (registry half), §5.5a.

### 2.4b Target resolution (router)

**New item — spec §5.5a, added in the amendment.** `Strata::Events::Router`
and `targets_for` exist nowhere in the engine today; both are proposed for the
first time in the amended spec.

**What.** A `Strata::Events::Router` that yields one hash per delivery row to
write: `{ subscriber_key:, target:, target_key: }`. Four branches, and the
start branch is not an edge case:

| Branch | `target_key` | Why |
| --- | --- | --- |
| Subscriber is not a business process | `"unrouted"` | The `respond_to?(:start_event?)` guard is the whole mechanism; without it any non-process durable subscriber raises **inside the publisher's transaction** |
| Start event | `"start"` | The handler *creates* the case, so there is deliberately nothing to resolve |
| `for_event` matched cases | `"<Class>/<uuid>"` per case | One row per case, which is what makes FR-7 per-case and `for_target` work |
| `for_event` matched nothing | `"unmatched"` | One row, so the `no_match` is recorded instead of vanishing |

**The start branch is the one that matters most.**
`ApplicationForm#publish_created` (`after_create`,
`app/models/strata/application_form.rb:51,101`) publishes `<Class>Created`, a
start event (`business_process_builder.rb:57-62`) whose handler creates the
case. A router that resolves targets by looking up cases finds none, writes no
delivery row, and `create_case_from_event` (`business_process.rb:135`) never
runs — **zero cases for every new application**, the entire intake path failing
quietly.

The three sentinels must stay distinct: collapsing them would make a start
delivery and an unmatched delivery collide on the unique index.

**Depends on [2.4a](#24a-durable-subscriber-registry).** Per D9, the methods
the router calls on a business process (`start_event?`, `case_class`) are public
despite appearances.

**Files.** `app/lib/strata/events/router.rb`.

**Tests first.** Data-driven over `each_delivery` across: a start event, a
transition event matching one case, matching several, matching none, and a
durable subscriber that is not a business process. **Assert the `target_key`
each branch produces**, since that column is the uniqueness invariant. Plus:
two start-event deliveries for one (event, subscriber) violate the unique
index; the router sees unserialized symbol keys and so depends on
[1.4](#14-pin-the-symbol-key-contract-in-casefor_event).

**Spec.** §5.5a, §13 — publish-time resolution is settled, so this item exists
as specified. One consequence is now an accepted cost rather than an open
question: **a case created between publish and delivery receives nothing.**
That is fine for transition events, which key on a case that already exists,
and it is why start events resolve no target at all.

### 2.5 Payload serialization

**What.** `ActiveJob::Arguments.serialize` / `.deserialize` rather than raw
JSON. It preserves symbol keys via `_aj_symbol_keys` (which is what keeps
`Case.for_event` working — see 1.4), turns ActiveRecord objects into GlobalIDs,
and stores a reference rather than a snapshot of the record's attributes. That
last property is also a security argument for this choice over the obvious one:
`{ kase: kase }` from `rake strata:events:publish_case_event`
(`lib/tasks/strata_events.rake:24`) serializes to `gid://dummy/PassportCase/<uuid>`
instead of persisting every column.

Note there is no GlobalID or `ActiveJob::Arguments` usage anywhere in the repo
today (D4) — this is new ground, so the tests matter more than usual.

Three behaviors to handle explicitly, not discover at runtime:

- **Serialization runs before any transaction opens, and it raises into the
  caller's `save!`** — deliberately (§5.3). A host publishing a `Struct`, an IO
  object, or any non-GlobalID custom class works today and has its record
  rejected after this change. **This is the NFR-2 exception** and the reason
  `check_payloads` exists.
- **A replayed event sees current state, not publish-time state.** Correct for
  ID-keyed transition events, wrong for any payload meant to capture a value at
  a point in time. Document it.
- **A deleted record makes the payload undeserializable** —
  `ActiveRecord::RecordNotFound` from `GlobalID::Locator`. Terminal: mark the
  delivery `dead`, do not retry. A bare `discard_on` records nothing, which is
  why [3.2](#32-delivery-job) uses the block form.

**Files.** `app/helpers/strata/event_manager.rb` or a new
`app/lib/strata/events/payload.rb`.

**Tests first.** Data-driven round trip across: symbol-keyed hash, nested hash,
AR object, `nil`, empty hash, `Time`/`Date`, oversized payload, and a
non-serializable object — which must raise a clear error **at publish**, not at
delivery, and must leave **no event row behind**. Plus the deleted-GlobalID
case.

**Spec.** §5.3.

### 2.5a Identifier-only payload enforcement

**New item.** §11.2 dropped the proposed `Strata::Events.payload_filter` and
replaced it with enforcement, which is what closes decision 0.2 and makes NFR-7
a requirement rather than a convention.

**What.** A check at publish, **in development and test only**: every payload
value must be a scalar, a `GlobalID`-able record, or a collection of those. No
attribute hashes, no value objects carrying names, addresses or dates of birth.
Failing in development is what turns the identifier-only rule from prose into a
constraint.

**Deliberately skipped in production**, so it can never reject a claimant's
submission — unlike [2.5](#25-payload-serialization), where raising is correct
because the payload genuinely cannot be stored at all. The two checks have
opposite failure policies on purpose; the tests should assert that difference
directly.

The SDK's own payloads already comply
(`{ application_form_id: }`, `{ task_id:, case_id: }`).

**Files.** `app/lib/strata/events/payload.rb` (alongside 2.5).

**Tests first.** An identifier-only payload passes in every environment; a
payload carrying an attribute hash raises in development and test and **passes
silently in production**; a `GlobalID`-able record passes; an array of
identifiers passes; `nil` and `{}` pass.

**Spec.** §8.1 control 3, §11.2, NFR-7.

### 2.6 Configuration module

**What.** `Strata::Events` with `mattr_accessor` for `durable`, `queue_name`,
`max_attempts`, `stranded_after`, `retention_period` — following the only
existing configuration precedent in the engine,
`app/services/strata/task_service.rb:14`. There is no `Strata.configure` block
and this work should not invent one.

Two boot-time checks, and §5.8 is explicit that both happen at boot rather than
at run time:

- **Tables absent.** `durable` true with the tables missing warns once and
  falls back to legacy behavior (NFR-3), evaluated at the same moment
  subscriptions register — inside the host's `config.after_initialize`, before
  boot finishes. Not a runtime flip: a flag that changed mid-process would
  leave subscribers on whichever path they chose at boot and deliver nothing.
- **Non-durable queue adapter.** `durable = true` against a deny-list of
  `async`, `inline`, and `test` outside the test environment is **refused at
  boot** (NFR-4). Rails' default is `:async`, an in-process thread pool that
  discards queued jobs on exit, so a host that enables durability without
  configuring a backend would otherwise get event rows, delivery rows, and no
  deliveries. `spec/dummy` is that host today (D4).

`max_attempts` must be read **at delivery time**, not frozen at job
class-definition time — see [3.2](#32-delivery-job). It is the entire
blast-radius mitigation in §11.3, so an operator lowering it has to get what
they asked for.

`stranded_after` defaults to 5 minutes: longer than a normal pending-to-running
transition, short enough that a deploy-time loss is recovered within one sweep.

**`retention_period` defaults to `nil`** (0.1, §5.8). Pruning is opt-in, so
nothing is deleted until a host sets it deliberately — which is what took this
line off Phase 2's merge gate. It is still the one line in Phase 2 that a wrong
default makes destructive, so the test asserting the default is `nil` is not
box-ticking.

**Files.** `app/lib/strata/events.rb`.

**Tests first.** Defaults for each setting; the tables-absent fallback warns
exactly once and leaves `durable?` false; `durable = true` on the `:async`
adapter refuses to boot; the same on `:test` inside the test environment does
**not**; a post-boot flip of `durable` raises rather than failing quietly.

**Spec.** §5.8, NFR-3, NFR-4.

### 2.7 `publish` writes rows

**What.** `publish` serializes the payload **outside** any transaction, then
inserts the event and its pending deliveries (via
[2.4b](#24b-target-resolution-router)) inside the caller's transaction, and
registers the enqueue for after commit. Returns the `Strata::Event` instead of
`nil` — confirmed additive rather than assumed: none of the twelve
`EventManager.publish` call sites in the engine, the dummy app or the suite
reads the current return value, which is the `instrument` result.

This is what fixes the `after_create`/rollback hazard: `ApplicationForm` and
`Task` publish from `after_create`/`after_update`, which run *inside* the
enclosing transaction, so a rollback today fires handlers for a write that never
happened.

**`legacy_publish` stays where it is — inside the caller's transaction,** after
the delivery rows are written. That is today's behavior and keeping it is the
choice §5.5 argues for: moving it to after-commit would extend FR-6 to lambdas
but break NFR-5 and the `publish_event_with_payload` matcher that host apps
inherit. **So FR-6 is scoped to durable deliveries**, and the carve-out is
stated, not papered over. In this phase every subscriber still runs through
`legacy_publish`, so delivery timing does not change at all.

Keep the [1.2](#12-rescue-at-the-publish-boundary) boundary rescue in place
around it.

**Depends on 2.1, 2.4, 2.4a, 2.4b, 2.5.**

**Files.** `app/helpers/strata/event_manager.rb`.

**Tests first.** FR-1 (row plus pending deliveries exist after publish); FR-6
(publish inside a rolled-back transaction leaves no event and no enqueue, while
a lambda subscriber still fired — the carve-out, asserted); a non-serializable
payload leaves no event row; publish outside any transaction still works;
**a start event under `durable = true` produces exactly one delivery row with
`target_key` `"start"` and still creates the case**; the existing
`publish_event_with_payload` matcher still passes unchanged.

**Spec.** §5.5, §5.5a.

### 2.8 Operator rake tasks — status, prune and `check_payloads`

**What.** Extend `lib/tasks/strata_events.rake` with
`strata:events:status[event_id]`, `strata:events:prune[days]` (FR-10), and
`strata:events:check_payloads[event_name]` (§5.9, §10 step 3). Backed by the
model scopes from 2.4, per the data-modeling guideline that queries live in
scopes.

`check_payloads` is the pre-flight for [2.5](#25-payload-serialization): it
runs a host's own publishers past `ActiveJob::Arguments.serialize` and reports
what would raise, so a host finds out from a rake task rather than from a
claimant's failed submission. **§10 puts it before this phase, not after** —
ship it with Phase 2 and document it as step 3 of the upgrade.

`prune` deletes `strata_events` rows and relies on the cascade from
[2.2](#22-migration-generator) to take their deliveries. Per 0.1 it must be
**a no-op with a clear message when `retention_period` is `nil`** — it must say
it did nothing and why, not exit silently. A prune task that quietly does
nothing is its own trap, and opt-in pruning means that is the state every host
starts in.

**Files.** `lib/tasks/strata_events.rake`,
`spec/lib/tasks/strata_events_spec.rb`.

**Tests first.** Prune with `retention_period` set deletes only rows older than
the cutoff, **and succeeds on an event that still has delivery rows** (fails
without the cascade); prune with it `nil` deletes nothing and reports why; an
explicit `[days]` argument overrides the configured value; `check_payloads`
reports a non-serializable payload and exits non-zero; `status` prints every
delivery state for an event.

**Spec.** §5.9, §8.1, §10.

### 2.9 Documentation

**What.** A `docs/strata-events.md` covering the event API, the identifier-only
payload rule and the fact that it is **enforced** in development and test
(§8.1, NFR-7), the serialization contract and its NFR-2 exception, and the
operator tasks. Add it to `docs/README.md`. Add `strata:events` to
`docs/generators.md` in the house format (`### strata:events`, one sentence,
`[See full usage guide](...)`, then a bash block).

> Note: `docs/generators.md` currently omits `strata:audit_log` and
> `strata:determination` entirely. Worth fixing separately — not this work.

Also fold the outstanding [D1–D9](#deltas-from-the-spec) corrections back into
`spec.md`. D6 (retention) and D1's generator-name discrepancy (§10 step 2) are
already done; D2, D3, D7 and D8 are the ones still to land, and D8 is the one
that changes §9.2's phase boundary rather than just its detail.

**No PII review-agenda item.** §11.2 answered 0.2: the audit-log ADR does not
govern this feature, and the control is
[2.5a](#25a-identifier-only-payload-enforcement) rather than a judgement call
at review. What remains open is narrower and belongs to 0.1 — whether a
permanent store of identifiers and timestamps warrants a retention and
encryption position of its own.

---

## Phase 3 — Durable delivery

Delivery moves to ActiveJob. **This is where behavior changes for hosts.**

0.3 and 0.4 are settled — 0.4 by the spec rather than by this plan, which
rewrites [3.9](#39-dummy-app-queue-backend).

### 3.1 Durable vs. legacy subscriber split

**What.** With the registry already in place from
[2.4a](#24a-durable-subscriber-registry), this item is only the split:
`subscribe` stops registering durable callbacks with
`ActiveSupport::Notifications`, so each callback runs down **exactly one**
path. Registering a durable subscriber both ways would run it twice per event —
once inline from `legacy_publish`, once from its delivery job.

Because `Strata::BusinessProcess` passes `method(:handle_event)`
(`business_process.rb:114`), **every SDK subscriber becomes durable with no
call-site changes.** Host lambdas take the legacy branch and behave exactly as
they do today (NFR-5).

The `durable?` flag is read at **subscribe** time, so it must be set before the
host's `config.after_initialize { XBusinessProcess.start_listening_for_events }`
(`spec/dummy/config/application.rb:40`). Raise on a post-registration flip
rather than failing quietly.

**Ship the deprecation timeline §5.5 commits to**, since it is the only path by
which FR-6 ever becomes unconditional: this phase warns once at `subscribe`
when a lambda is registered with `durable` on; the next release makes that a
deprecation warning naming the replacement; the release after removes
`legacy_publish` and raises instead.

**Files.** `app/helpers/strata/event_manager.rb`.

**Tests first.** A durable subscriber is **not** registered with Notifications
and fires exactly once per event; a lambda still fires synchronously; both
handle types survive `unsubscribe` and `unsubscribe_all`; a post-registration
flag flip raises; registering a lambda with `durable` on warns once.

**Spec.** §5.4, §5.5.

### 3.2 Delivery job

**What.** `Strata::EventDeliveryJob < Strata::ApplicationJob`.
`Strata::ApplicationJob` is an empty subclass today and gains no shared
behavior from this. Four details the amended spec is specific about, each of
which is a bug if done the obvious way:

- **`retry_on StandardError, wait: :polynomially_longer, attempts: :unlimited`**,
  with the real ceiling enforced in the job's own rescue against
  `Strata::Events.max_attempts`. `attempts: Strata::Events.max_attempts` is
  evaluated **once at class-definition time**, which makes `max_attempts` a
  control operators believe they have and do not — and it is the entire
  blast-radius mitigation in §11.3.
- **`discard_on ActiveJob::DeserializationError` in block form**, writing
  `status: :dead` with the error and `completed_at`. A bare `discard_on` runs no
  code and records nothing, leaving the delivery `failed` forever — retried by
  any operator replaying failures, for the one cause retrying cannot fix.
- **`find_by`, not `find`.** A delivery removed by `prune` while its job sat in
  the queue is nothing to record and nothing to retry; `find` would raise and
  retry pointlessly.
- **The rescue is scoped to the private `deliver` method**, where `delivery` is
  guaranteed non-nil. Rescuing in `perform` would dereference nil whenever the
  lookup itself raised, so a connection error during `find_by` would surface as
  `NoMethodError` and lose the real cause.

**Files.** `app/jobs/strata/event_delivery_job.rb`.

**Tests first.** `max_attempts = 2` puts the delivery in `dead` after two
executions (this fails against a hardcoded `attempts: 5`); a deleted GlobalID
target lands in `dead`, not `failed` and not an infinite retry; a job whose
delivery row was pruned returns quietly **and surfaces no `NoMethodError`**; a
connection error during lookup surfaces as itself.

**Spec.** §5.6, §5.8.

### 3.2a Stranded-delivery sweeper (FR-11)

**New item, and required — not optional.** §13 settled this: the sweeper is
required and carries FR-1's guarantee, because Sidekiq stays supported.

**What.** A SIGKILL between COMMIT and `after_all_transactions_commit` —
a deploy, an OOM kill, the exact scenario this work exists to survive — leaves
the event and its deliveries committed at `pending` with no job anywhere.
ActiveJob's retries cannot cover it: no job was ever enqueued, so there is
nothing to retry. §5.5b has the full argument; the consequence for this plan is
that **without this item FR-1 is unmet, and FR-1 is the whole point of the
work.**

Ship `Strata::RequeueStrandedDeliveriesJob` re-enqueueing
`EventDelivery.stranded(Strata::Events.stranded_after)`, plus
`rake strata:events:requeue_stranded` so a host can schedule it with plain
`cron`. Re-enqueueing is safe because FR-7's status check makes a redundant run
a no-op.

**The SDK ships the job and the task, not the schedule** — hosts wire it to
whatever already runs their recurring work. Say so in the upgrade notes
([3.10](#310-upgrade-notes)); a host that skips it never recovers a
deploy-stranded delivery. A same-database backend closes the window outright
and is why §13 prefers one, but it cannot be assumed.

**Files.** `app/jobs/strata/requeue_stranded_deliveries_job.rb`,
`lib/tasks/strata_events.rake`.

**Tests first.** Commit an event and its deliveries **without enqueueing
anything** — the stranded state — then run the sweeper and assert delivery.
This is the FR-1 test that actually exercises the crash window; the FR-1 test
in [2.7](#27-publish-writes-rows) does not. Plus: `stranded` excludes
deliveries newer than `stranded_after`; excludes `succeeded` and `dead`; a
sweep over an already-succeeded delivery is a no-op.

**Spec.** §5.5b, FR-11, §13.

### 3.3 Idempotency and per-case serialization

**What.** The job locks the delivery row, returns early if already `succeeded`
(FR-7), resolves the subscriber from `subscriber_key`, calls it, maps the
outcome through `EventDelivery.status_for`, and writes the status — all in one
transaction, so the case's step change and the "this was applied" record commit
together. That is what closes the gap from
[1.1](#11-let-the-step-raise-and-roll-back-the-step-change-with-it) at the
delivery layer.

**FR-8 needs a lock on the case row, not the delivery row.** This plan
previously said per-case serialization "comes from `Case.lock.find` inside
`BusinessProcessInstance`", which §5.6 corrects:
`BusinessProcessInstance#initialize` receives an already-loaded case and never
locks (`business_process_instance.rb:28-30`), and two events for one case are
two *different* delivery rows, so delivery-row locks do not serialize them
against each other at all.

FR-8 therefore lives in `EventDelivery#with_locked_target`
([2.4](#24-models)): `target_type.constantize.lock.find(target_id)`, a `FOR
UPDATE` held by the surrounding transaction, and a plain `yield` for the
target-less `"start"` / `"unmatched"` / `"unrouted"` rows. Locking a different
Ruby object than the handler uses is fine — the lock is on the database row.

**Watch `default_scope { includes(:tasks) }`** on `Strata::Case`
(`case.rb:73`). It is a preload today, so `FOR UPDATE` is safe; if a future
change turns it into an eager load, Postgres rejects `FOR UPDATE` on the
nullable side of an outer join. §5.6 asks for a regression test rather than a
comment; write the test.

§5.6 weighs and rejects four alternatives — advisory locks, optimistic locking,
queue-level concurrency keys, dropping FR-8. Read it before proposing one.

**Tests first.** Running the same job twice produces one step advance and one
task; two concurrent jobs on **one case** serialize — asserted against the
*case* lock, since a test that only proves two delivery rows were processed
serially would pass on the rejected design; a `no_match` is recorded rather
than vanishing, and the case does not move; `FOR UPDATE` on a case with the
`includes(:tasks)` default scope does not raise.

**Spec.** §5.6, §5.6a, §5.7.

### 3.3a Remove the publish-boundary rescue

**New item — this is §6.1's real fix, held back from Phase 1.**

**What.** Delete the rescue added in
[1.2](#12-rescue-at-the-publish-boundary). By this point
`execute_current_step` runs inside `EventDeliveryJob`, where there is no domain
write to unwind and a raise is precisely what drives the retry. Until this
lands, [3.4](#34-retry-and-dead-letter-policy) cannot work: a swallowed
exception means every job reports success, every delivery is marked
`succeeded`, and nothing is ever retried — a durable pipeline that durably
records failures as successes.

**Sequence it after [3.1](#31-durable-vs-legacy-subscriber-split).** While
legacy subscribers still run inline inside the publisher's transaction, a raise
from one of them still unwinds the caller's `save!`. The rescue can only come
out once durable subscribers have left that path — and it must stay for the
lambda path as long as `legacy_publish` exists.

**Files.** `app/helpers/strata/event_manager.rb`.

**Tests first.** A raising step inside a delivery job propagates and drives a
retry; a raising **lambda** subscriber still does not reject the domain write;
the Phase 1 assertion from 1.2 is updated rather than deleted, so the change in
policy is explicit in the suite.

**Spec.** §6.1, §9.3, §11.5.

### 3.4 Retry and dead-letter policy

**What.** Failed deliveries retry with backoff, then land in `dead` with
`last_error` populated and `attempts` recorded. Never silently dropped (FR-3).
`dead` is assigned for **both** terminal causes — exhausted retries and an
undeserializable payload (§13, §5.9) — so `unresolved` stays meaningful and an
operator can tell *this will never succeed* from *this has not succeeded yet*.

**Tests first.** A raising subscriber retries then dead-letters — **this test
fails until [3.3a](#33a-remove-the-publish-boundary-rescue) lands**, so it is
the regression guard for that item rather than for Phase 1. Raising
`max_attempts` after a delivery is `dead` does not resurrect it.

**Spec.** §5.6, §5.9, §11.3.

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
reads it and dead-letters on the first failure for a non-retryable step.

**Files.** `app/models/strata/business_process_builder.rb`,
`app/models/concerns/strata/step.rb`, `app/models/strata/system_process.rb`,
`app/jobs/strata/event_delivery_job.rb`.

**Tests first.** A retryable step that raises retries then dead-letters; a
`retryable: false` step that raises dead-letters immediately with `attempts` at
1; the default is retryable when the option is omitted; the flag survives a
business process definition round trip.

**Acceptance.** A host can mark a step non-idempotent and trust it will not be
called twice by the retry machinery.

**Spec.** §11.3, §9.3, §13 — in scope for Phase 3. §11.3 carries the design
sketch (the `retryable:` option across the four step helpers, the flag on
`Strata::Step`, first-failure dead-lettering in the job); this item implements
it.

### 3.6 Replay

**What.** `strata:events:replay[delivery_id]` and
`strata:events:replay_dead[event_name]` (FR-5). Rake-only — replay re-executes
a business process step and can create tasks, close cases, or call an external
system. If it is ever exposed over HTTP it needs a Pundit policy and an audit
entry.

**Tests first.** Replaying a `dead` delivery re-runs it and can move it to
`succeeded`; replaying a `succeeded` delivery is a no-op (FR-7); `replay_dead`
scopes to one event name; a replayed event sees **current** state, not
publish-time state (the §5.3 consequence, asserted rather than documented).

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

**Rewritten — decision 0.4 is superseded by NFR-4 and §5.8.**

**What.** The engine still ships no background-job gem and takes no dependency
on one; hosts choose. But it is no longer indifferent to the choice:

- **NFR-4 requires a durable backend** — Solid Queue, GoodJob, or Sidekiq.
- **§5.8 refuses to boot** when `durable = true` runs on `async`, `inline`, or
  `test` outside the test environment. That check is
  [2.6](#26-configuration-module)'s; this item is what makes the dummy app
  satisfy it.
- **§13 prefers a same-database backend** where a host can run one, because
  `perform_later` then commits with the event row and the FR-11 window closes
  outright.

For the suite, wire the `:test` adapter into `spec/rails_helper.rb` alongside
the [3.7](#37-test-helpers) helpers — allowed by the deny-list's test-environment
carve-out, and the reason that carve-out exists.

**And configure Solid Queue in `spec/dummy`.** Decided rather than left to
Phase 3 review: `spec/dummy/config/environments/production.rb:73` leaves
`queue_adapter` commented out, so the dummy app inherits `:async` and would be
**refused at boot** under `durable = true` — the repo's only host app fails the
requirement the repo is adding. Without a real backend here, retry,
dead-lettering and FR-11 recovery are validated only in some host app that
happens to have one, which is how a requirement becomes aspirational.

Concretely, and the first point is the one that matters:

- **The gem goes in the root `Gemfile`'s `:development, :test` group**,
  alongside `pg`, `pundit` and `factory_bot_rails` — **not in
  `strata.gemspec`.** There is no separate dummy Gemfile; the dummy app uses
  the root one, which is exactly the seam that lets the dummy app have a queue
  while the engine declares none. Putting it in the gemspec would make it a
  hard dependency for every host and contradict NFR-4's "hosts choose".
- Install Solid Queue's migration into `spec/dummy/db/migrate/` and let
  `db:migrate` regenerate `schema.rb` (never edit it — CLAUDE.md hard rule).
  Note this adds a substantial number of tables to a checked-in, reviewed
  `schema.rb`; if that is unwelcome, GoodJob is the lighter-schema
  same-database alternative and satisfies NFR-4 identically.
- Set `config.active_job.queue_adapter = :solid_queue` in the dummy app's
  development and production environments. Leave test on `:test`.
- **Use Solid Queue's recurring tasks to schedule
  [3.2a](#32a-stranded-delivery-sweeper-fr-11)**, which is the part that most
  needs exercising: the sweeper is the mechanism carrying FR-1, and a scheduled
  job that has never actually run on a schedule is not evidence of anything.

Being a same-database backend, this also closes the FR-11 window outright in
the dummy app (§5.5b) — so the stranded state has to be **constructed** in the
test rather than waited for, which [3.2a](#32a-stranded-delivery-sweeper-fr-11)
already calls for.

**Tests first.** `durable = true` with `:async` refuses to boot; with `:test`
inside the test environment it does not; an end-to-end publish-to-delivery run
against Solid Queue; the sweeper recovers a delivery committed `pending` with
no job enqueued.

**Spec.** NFR-4, §5.8, §5.5b, §13.

### 3.10 Upgrade notes

**What.** Ship §10's eight-step path as host-facing upgrade notes. Three
things this plan adds to it rather than restating:

- **Steps 3 through 6 are prerequisites, not follow-ups.** Each is a distinct
  way for durability to look enabled and deliver nothing:
  `check_payloads` unrun (rejected submissions), idempotency unaudited
  (duplicate payments), a non-durable adapter (refused at boot), the sweeper
  unscheduled (FR-1 does not hold). Order them that way and say why.
- **Step 4 is the loudest line, and it is worth quoting verbatim:**

  > At-least-once delivery means a callback that calls an external system and
  > fails *after* the call but before commit will call again on retry. The
  > transaction rolls back the database; it cannot roll back an HTTP request
  > that already happened. In a benefits context that is a duplicate payment.

  [3.5](#35-per-step-retryable-false) is the structural opt-out; step 4 is how
  a host finds out it needs one.
- **Add the deployment note from §5.10**, which §10 omits: the worker must boot
  the **same application**, or `subscriber_key` constantizes to nothing and
  resolves no subscriber.
- **Add a retention step**, which §10 also omits. `retention_period` defaults
  to `nil` deliberately (0.1) and pruning stays off until a host sets it. Say
  that the value is a **retention obligation, not a disk-space preference**,
  and that §11.1's questions — the obligation itself, and encryption at rest —
  are answered before it is set, not after. This is the one place the open
  policy question can still do harm.

**Spec.** §10, §5.10, §11.3.

---

## Test strategy

- Tests are written and **approved before implementation** for every non-trivial
  item (CLAUDE.md).
- Follow [testing.md](../../contributing/testing.md): multiple scenarios,
  data-driven where the same assertion repeats over inputs, and explicit `nil`,
  oversize, and error cases. The clearest data-driven candidates are
  serialization ([2.5](#25-payload-serialization)), the router's `target_key`
  branches ([2.4b](#24b-target-resolution-router)), `durable_reference?`
  ([2.4a](#24a-durable-subscriber-registry)) and `status_for`
  ([2.4](#24-models)).
- **Seven tests in spec §7 exist specifically because they fail against the
  pre-amendment design.** Treat them as the acceptance criteria for this
  revision, not as ordinary coverage: the FR-11 stranded-delivery sweep, the
  start-event delivery row **plus case creation**, start-event uniqueness, the
  `no_match` recording, FR-8 asserted against the *case* lock, FR-10 pruning an
  event that still has deliveries, and `max_attempts = 2` taking effect.
- `spec/support` is **not** glob-loaded — the glob at `spec/rails_helper.rb:45`
  is commented out. New matchers and helpers must be `require`d per-spec, as
  `publish_event_with_payload` is today.
- Engine factories live in `spec/factories/strata/` and are registered by
  `lib/strata/engine.rb:27-31`; dummy factories live in
  `spec/dummy/spec/factories/`. Name files `*_factory.rb`.
- The suite uses transactional fixtures, not DatabaseCleaner. See
  [2.1](#21-spike-after-commit-hooks-under-transactional-fixtures) for why that
  matters here.

## Sequencing

Phase 1 can start now, and with 0.1 closed **no phase waits on a decision**.

```
Phase 1   1.1 ══ 1.2  ──►  1.3  ──►  1.4  ──►  1.5  ──►  [Phase 1 ships]
           └──── one PR; neither is safe alone                  │
                                                                │
Phase 2   2.1  ◄────────────────────────────────────────────────┘
           │   (spike first — a negative result invalidates 2.7)
           ├──► 2.2 ──► 2.3 ─────────────┐
           ├──► 2.5 ──► 2.5a ────────────┤
           ├──► 2.6 ─────────────────────┤
           └──► 2.4a ────────────────────┤
                                         └─► 2.4 ─► 2.4b ─► 2.7 ─► 2.8 ─► 2.9
                                                                            │
                                                     [Phase 2 ships] ◄──────┘
                                                             │
Phase 3   3.1 ─► 3.2 ─► 3.3 ─► 3.3a ─► 3.4 ─► 3.5 ─► 3.6 ─► [ships]
 ◄────────┘│       └──► 3.2a
           └──► 3.7 ─► 3.8         3.9 ─► 3.10
```

Parallelizable: within Phase 2, the migration (2.2/2.3), serialization and its
enforcement check (2.5/2.5a), configuration (2.6) and the registry (2.4a) are
all independent once 2.1 answers. 2.4b needs 2.4a; 2.7 needs all of them.
Within Phase 3, 3.7 can start as soon as 3.1 lands, 3.2a needs only 3.2, and
3.9 is independent of the 3.1–3.6 chain.

Hard ordering to respect: **3.3a after 3.1** (a raising lambda still unwinds
the domain write until durable subscribers leave the inline path), and **3.4
after 3.3a** (its central test cannot pass while exceptions are swallowed).

## Risks

| Risk | Phase | Mitigation |
| --- | --- | --- |
| Retries double-fire external side effects — a duplicate payment or notice | 3 | [3.5](#35-per-step-retryable-false) ships the per-step `retryable: false` opt-out (0.1 settled it into §11.3 and §9.3), plus idempotency docs, a `max_attempts` the job actually reads (3.2), and step 4 of the upgrade notes. **Still the sharpest risk in this work** (§11.3), and 3.5 is the only item that prevents rather than mitigates it |
| A deploy strands a committed delivery and nothing recovers it — FR-1 silently unmet | 3 | [3.2a](#32a-stranded-delivery-sweeper-fr-11), required rather than optional (§13). A host that does not schedule it does not have FR-1, which is why it is step 6 of the upgrade notes |
| Start events resolve no target, so `durable = true` creates **zero cases for every new application** | 2 | [2.4b](#24b-target-resolution-router)'s explicit start branch, and the §7 test that asserts both the delivery row and the created case |
| Serialization raises inside `after_create` and rejects a claimant's submission | 2 | `check_payloads` ([2.8](#28-operator-rake-tasks--status-prune-and-check_payloads)) runs **before** the phase reaches a host (§10 step 3); the identifier-only check ([2.5a](#25a-identifier-only-payload-enforcement)) fails in development, never in production |
| Prune deletes records that must be kept | 2 | 0.1 — `retention_period` defaults to `nil`, so pruning is opt-in and cannot fire unreviewed. The residual risk moves to the host: **the retention obligation must be answered before anyone sets it**, which is why it is in the upgrade notes ([3.10](#310-upgrade-notes)) rather than in the SDK's release gate |
| A host enables pruning against an obligation nobody has confirmed | — | The one place the open policy question can still cause harm. Needs a named data-policy owner, and needs the upgrade notes to say plainly that `nil` is deliberate and not a value to fill in casually |
| After-commit hooks do not fire under transactional fixtures | 2 | [2.1](#21-spike-after-commit-hooks-under-transactional-fixtures) spike, first |
| Silent no-ops become visible and the first `no_match` counts look alarming | 2 | Warn teams in advance; it is the first honest measurement, not a regression (§11.4). §12 question 7 asks who owns the number — without an owner the diagnostic argument for recording it evaporates |
| Phase 1 surfaces failures hosts already had | 1 | [1.5](#15-release-notes-for-phase-1) release notes, framed so hosts do not brace for rejected submissions a release early (§11.5) |
| Async breaks host specs in ways we cannot see from here | 3 | [3.7](#37-test-helpers) ships helpers with the change rather than leaving hosts to invent them |

## Definition of done

**Phase 1** — no `rescue Exception` in `business_process_instance.rb`; a raising
step leaves the domain write saved and the case **not** advanced; no state where
a case advanced without its step running; `transition_to_next_step` and
`handle_event` return `:transitioned`/`:no_match` (and nothing raises
`NoMatchingTransition`); characterization test on `for_event`; the boundary rescue carries a comment naming §6.1 as temporary;
release notes written; `make lint` and `make test` green.

**Phase 2** — generator installs both tables with a passing generator spec,
including `target_key` NOT NULL, the unique index on `target_key`, and the
cascade FK; the dummy app is migrated via `db:migrate` (never by editing
`schema.rb`); a start event produces exactly one `"start"` delivery row **and
still creates the case**; publish writes rows inside the caller's transaction
and rollback leaves nothing behind; delivery **timing** is unchanged and every
existing spec — including `publish_event_with_payload` — passes untouched; a
non-serializable payload raises at publish and leaves no event row;
`check_payloads` reports it; the identifier-only check fails in development and
not in production; prune succeeds on an event that still has deliveries;
`retention_period` defaults to `nil` and prune is a **reported** no-op without
it; docs updated and they state that `nil` is deliberate; `make lint` and
`make test` green.

**Phase 3** — a subscriber is registered down exactly one path and fires once;
the same delivery applied twice produces one effect; two jobs on one case
serialize **on the case row**; a delivery stranded with no job is recovered by
the sweeper with no operator action; the boundary rescue is gone for durable
subscribers and still protects the lambda path; a raising subscriber retries
then dead-letters, and `dead` is assigned for both terminal causes; a
`retryable: false` step dead-letters on its first failure; `max_attempts`
changes take effect at delivery time; `durable = true` on `:async` refuses to
boot; replay works from rake; test helpers ship; every SDK spec migrated;
`Strata::Events.durable` defaults **off** for at least one release; upgrade
notes carry the idempotency warning and the sweeper schedule; `make lint` and
`make test` green.
