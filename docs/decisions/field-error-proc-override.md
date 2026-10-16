# ADR-002: Disable Rails `field_with_errors` wrapper engine-wide

## Status

Accepted

## Date

2026-05-19

## Context

When an attribute on a form object has validation errors, Rails wraps the
rendered input in a `<div class="field_with_errors">`. The wrapper is
injected by `ActionView::Base.field_error_proc`, a class-level lambda that
runs around every form helper output for an errored attribute.

Strata's form builders already supply their own USWDS error markup
(`usa-input--error`, `usa-form-group--error`, `usa-error-message`) on every
helper, so the Rails wrapper duplicates the error signal. Worse, it actively
breaks USWDS components that rely on adjacent-sibling or direct-child CSS
selectors. For example, `.usa-input-prefix + input` supplies the input's
`padding-left`, and a wrapper between the prefix and the input breaks that
adjacency. The same shape of bug applies to character counters, date
pickers, combo boxes, and any future USWDS component using selectors like
these.

PR #337 worked around the prefix/suffix case with a scoped regex strip in
`Strata::FormBuilder#text_field`, but that fix doesn't generalize — it
would need to be re-applied by hand in every helper.

## Decision

Set `ActionView::Base.field_error_proc` to a pass-through at the engine
level, and remove the scoped regex strip from `Strata::FormBuilder#text_field`.

The override lives in [lib/strata/engine.rb](../../lib/strata/engine.rb) as a
new `strata.field_error_proc` initializer that uses
`ActiveSupport.on_load(:action_view)` to defer until ActionView is loaded:

```ruby
initializer "strata.field_error_proc" do
  ActiveSupport.on_load(:action_view) do
    ActionView::Base.field_error_proc = ->(html_tag, _instance) { html_tag }
  end
end
```

This makes the `field_with_errors` wrapper disappear from every Strata-rendered
form, errored or not.

## Consequences

- The `field_with_errors` div is removed for *every* form helper output in
  applications that mount the Strata engine — not just the helpers Strata
  itself defines. Strata-rendered forms already convey error state through
  USWDS-aligned classes; any CSS hooking onto `.field_with_errors` was
  working around Rails' default rather than expressing intent.
- The scoped regex strip in `text_field` is removed, simplifying the helper
  and eliminating a piece of code whose existence was non-obvious unless you
  knew the prefix-adjacency story.
- Hosts that explicitly want the wrapper back can restore it from their own
  initializer (`ActionView::Base.field_error_proc = ActionView::Base::DEFAULT_FIELD_ERROR_PROC`);
  Strata's runs first, so the host's assignment wins.

## Alternatives considered

### Keep the scoped regex strip

Patch individual helpers as new adjacent-sibling components are added.
This choice scales linearly with the number of components, leaves the wrapper
in place everywhere else, and depends on Rails' internal wrapper format not
changing.

### Gate the override behind a `Strata.config` flag

Add a Strata setting like `Strata.config.disable_field_error_wrapper = true`.
Hosts have full control via the Rails escape hatch above; a Strata flag
would be an alternate spelling of the same lever.

### Override only inside Strata form builders

Wrap `field_error_proc` in a per-render block that's only active while a
`Strata::FormBuilder` is rendering. More code and state for no practical 
benefit — applications using Strata form builders get the same effective
behavior from the engine-wide override.
