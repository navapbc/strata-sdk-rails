# Strata SDK Documentation

Welcome to the Strata SDK documentation. This index provides an organized overview of all available documentation.

## Getting Started

- [Getting started guide](./getting-started.md) - Begin here to create your first Strata application

## Core concepts

- [Strata SDK components](./strata-sdk-components.md) - Overview of available SDK components
- [USWDS components](./uswds-components.md) - ViewComponent wrappers for U.S. Web Design System components
- [Authorization](./authorization.md) - Built-in base policies for secure authorization patterns
- [API Authentication](./api-authentication.md) - Secure API endpoints using the ApiAuthenticator and HMAC strategies
- [Strata Data Modeler](./strata-data-modeler.md) - Learn how to define data models using Strata Attributes and generate migrations using the Strata Migration Generator.
- [Strata Form Builder](./strata-form-builder.md) - Build frontend form views with USWDS markup.
- [Strata View Helpers](./strata-view-helpers.md) - View helpers like `strata_link_to` and `strata_button_to` that wrap Rails primitives with USWDS-aware styling.
- [Multi-Page Form Flows](./multi-page-form-flows.md) - Create complex forms that span multiple pages
- [Business process family tree](./business-process-family-tree.md) - Understanding business process hierarchies
- [Strata Rules Engine](./strata-rules-engine.md) - Introduction to the rules engine for business logic
- [Strata Audit Log](./strata-audit-log.md) - Record an immutable trail of actions, atomic with the surrounding domain writes

## Implementation guides

- [Implementing tasks views](./implementing-tasks-views.md) - Guide for implementing prebuilt views

## Intent and specs

Captured intent for proposed work — what we want and why, recorded before any design or implementation — and the design specs that follow from it.

- [Durable events (intent)](./intent/durable-events.md) - Make events survive the process that published them
- [Durable events (spec)](./specs/durable-events/spec.md) - Requirements and design for the above
- [Durable events (plan)](./specs/durable-events/plan.md) - Sequenced implementation PRs and proof for the above

## Miscellaneous

- [Leaving a project](./leaving-a-project.md) - Guidelines for when a Nava project team transitions off the project

## Reference

- [Strata attributes](./strata-attributes.md) - Detailed documentation on all Strata attributes
- [Generators](./generators.md) - Generate boilerplate code with Strata generators
