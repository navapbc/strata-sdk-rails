# Intent: Durable events

- **Author:** Roger Lam (rogerlam@navapbc.com)
- **Date:** 2026-09-11
- **Status:** Draft — awaiting product owner review
- **Affects:** `strata` engine — `Strata::EventManager`, `Strata::BusinessProcess`, and every host app that publishes or subscribes to Strata events

> This is an intent, not a design. It records what we want and why, and the
> constraints a design has to respect. It deliberately stops short of choosing
> an implementation — see [Open questions](#open-questions).
>
> The design that follows from this intent is
> [docs/specs/durable-events/spec.md](../specs/durable-events/spec.md).

## Problem

Strata's event system is `Strata::EventManager`
([app/helpers/strata/event_manager.rb](../../app/helpers/strata/event_manager.rb)),
a thin wrapper over `ActiveSupport::Notifications`. `publish` calls
`ActiveSupport::Notifications.instrument`, which runs every subscriber inline,
in the publishing process, before `publish` returns. Nothing about the event is
written down anywhere.

An event therefore exists only for the duration of the method call that
published it. Two consequences are hurting us:

**1. A deploy or a crash mid-handler loses the event.**

`Strata::BusinessProcess` subscribes to its transition events at boot and
advances the case inside the handler
([app/models/strata/business_process.rb:114](../../app/models/strata/business_process.rb#L114),
[:149](../../app/models/strata/business_process.rb#L149)). So when
`IdentityVerified` moves a passport case from `verify_identity` to
`review_application`, that state change happens inside the subscriber callback,
in the publishing process. If that process is terminated part-way through — the
normal thing that happens during a deploy — the event is gone. There is no
record that it was ever published, no retry, and nothing to reconcile against.
The case stays silently parked on the old step.

The same applies to every event the SDK publishes today:
`Strata::ApplicationForm` publishes `…Created` and `…Submitted`, and
`Strata::Task` publishes `…Completed` on status change.

**2. There is no replayable history.**

Because events are never persisted, we cannot answer basic operational
questions after the fact: was this event published? Did anything handle it? Did
a handler fail? Recovery today means someone republishes the event by hand with
`rake strata:events:publish_case_event`
([lib/tasks/strata_events.rake](../../lib/tasks/strata_events.rake)) — which
requires that a human already knows which event was lost, and for which case.
Usually the first signal is a claimant asking why their application hasn't
moved.

**Why this matters more here than in a typical Rails app.** In Strata, events
*are* the case-management state machine, not a side channel for analytics or
cache invalidation. A lost event is a stuck case, and in a benefits context a
stuck case is a person not getting paid, with no alert and no audit trail
explaining why.

There is a related hazard worth naming while we're here: `ApplicationForm` and
`Task` publish from `after_create` / `after_update` callbacks, which run
*inside* the enclosing transaction. If that transaction later rolls back, an
event has already been published for a write that never happened. Today that
fires handlers for a state that doesn't exist; under any durable scheme it
would *persist* an event for a state that doesn't exist.

## Proposed outcome

An event published through `Strata::EventManager.publish` survives the process
that published it.

Concretely, when this is done:

- Once the publisher's outermost transaction commits, the event is durably
  recorded and **will** be handled even if the publishing process is killed
  immediately afterward — at-least-once delivery rather than best-effort.
- A handler that fails is retried rather than silently dropped.
- Published events are queryable after the fact, so an operator can see what was
  published, what was handled, what failed, and replay what needs replaying —
  without first having to guess what was lost.
- Existing Strata applications upgrade without changing any calling code.

## Affected users and systems

**Inside the engine** — everything that publishes or subscribes today:

| Component | Role |
| --- | --- |
| `Strata::EventManager` | the API being changed |
| `Strata::BusinessProcess` | the only subscriber in the SDK; drives all case transitions |
| `Strata::ApplicationForm` | publishes `…Created`, `…Submitted` |
| `Strata::Task` | publishes `…{Status}` on status change |
| `rake strata:events:*` | publishes ad hoc, including payloads carrying live AR objects |
| `publish_event_with_payload` matcher | test support that subscribes and asserts synchronously |

**Host applications** — any app built on the SDK. Their business processes,
their own `EventManager.publish` call sites, and their specs.

**Host app operators** — whoever deploys and runs these apps. They gain a
working queue backend and a migration as new prerequisites, and gain event
history as a new operational tool.

**Claimants and case workers** — indirectly, and this is the point. They are the
ones currently absorbing the cost of a stuck case.

## Constraints

1. **The public interface does not change.** `publish(event_key, payload = {})`,
   `subscribe(event_key, callback)`, `unsubscribe(subscription)`,
   `unsubscribe_all`, and the `{ name:, payload: }` event hash passed to
   callbacks all stay as they are. Upgrading must not require host apps to
   rewrite call sites.

2. **Prefer ActiveJob if it genuinely fits.** It is Rails-native,
   backend-agnostic, and already available to us — `Strata::ApplicationJob`
   exists ([app/jobs/strata/application_job.rb](../../app/jobs/strata/application_job.rb)).
   This is a preference, not a mandate: if ActiveJob alone cannot deliver the
   guarantee above, the design should say so and say what else is needed.

3. **Handlers may become asynchronous.** Accepted: `publish` no longer has to
   run subscribers inline. Note that this is a *behavioral* break even though no
   signature changes — anything that assumes a side effect is visible
   immediately after `publish` returns will need updating, in the SDK's own
   specs and in host apps. The upgrade notes have to be explicit about this.

4. **A host-app migration is acceptable.** The engine ships no migrations of its
   own; the precedent is `strata_tasks`, shipped as a generator template and run
   by the host. Durable storage may follow that pattern. Requiring hosts to run
   a generator and a migration on upgrade is an accepted cost.

5. **Payloads must survive serialization.** Today payloads are plain in-memory
   hashes that can hold anything, including live ActiveRecord objects — the rake
   task publishes `{ kase: kase }`. Anything durable has to serialize the
   payload. The design has to handle this explicitly rather than discover it at
   runtime.

6. **No new infrastructure requirement beyond what a Rails app already has.** A
   Postgres database and an ActiveJob backend are fair to assume. A dedicated
   message broker is not.

## Open questions

1. **Ordering.** Business process transitions are sequential per case. Do events
   for the same case need to be handled in publication order, or is
   per-case serialization enough? What happens if two events for one case are
   handled concurrently?

2. **Idempotency.** At-least-once delivery means a handler can run twice. Case
   transitions are not obviously idempotent today. Is making handlers idempotent
   the SDK's job, the host's job, or is it avoided some other way?

3. **Failure policy.** How many retries, what backoff, and what happens to an
   event that exhausts them? Is there a dead-letter state, and who gets alerted?
   Today a raising subscriber propagates the exception straight back into the
   publisher's call stack — what replaces that?

4. **Chained events.** A `system_process` publishes the *next* event while
   handling the previous one, so a transition chain currently completes inside
   one call stack ([spec/models/strata/business_process_spec.rb:28](../../spec/models/strata/business_process_spec.rb#L28)).
   Asynchronously that chain becomes several jobs with gaps in between, during
   which the case is observably mid-flight. Is that acceptable, and does anything
   need to be atomic per case?

5. **Testing story.** The `publish_event_with_payload` matcher and
   `business_process_spec` both assume inline execution. What does testing look
   like afterwards — `perform_enqueued_jobs`, an inline test adapter, or a
   Strata-provided helper? Whatever we choose, host apps inherit it, so it should
   ship with the change rather than be left to them.

6. **Scope of durability.** Does every event become durable, or do hosts opt in
   per event? Some events may genuinely not warrant a row and a job.

7. **Transactional boundary.** Should recording an event be atomic with the
   domain write that triggered it (a transactional outbox), the way
   `Strata::AuditLog` already makes audit lines atomic with the caller's writes?
   This is what would fix the `after_create` / rollback hazard described above,
   but it is a design decision, not a given.

8. **Upgrade path for hosts that don't migrate.** If a host upgrades the gem but
   hasn't run the new migration yet, what happens? Does the SDK fall back to
   today's in-memory behavior, or refuse to boot?

## Not in scope

- Cross-process delivery. Today a subscriber only receives events published in
  its own process. Making a web process's event reach a subscriber in a worker
  is a real gap, but it is not what this intent is about, and folding it in
  would change the delivery model rather than just make it durable. Worth its
  own intent.

  *(Update, after design: the ActiveJob design chosen in
  [the spec](../specs/durable-events/spec.md#subscriber-types)
  closes this for durable subscribers as a side effect — a worker handles the
  job regardless of which process published. Only anonymous lambda subscribers
  remain in-process. This was not a goal; it is a consequence, recorded here so
  the scope note isn't read as still-true.)*
- Redesigning the business process DSL or the transition model.
- Changing what events the SDK publishes, or their payload shapes.
