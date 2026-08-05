# CLAUDE.md — my-crd

## Purpose

A specific CR-rendering library built on top of `../crdkit`. Supplies
everything crdkit can't know on its own: this CR's `apiVersion`/`kind`,
its locked/default tokens, and its integration chain. Deliberately thin
— see `../crdkit/CLAUDE.md` for the reasoning behind that split. This
file covers decisions and assumptions that aren't visible just by
reading the templates.

## Decisions worth knowing before changing this repo

- **"my-crd" / "mycrd" is a placeholder name**, chosen while working out
  the crdkit/specific-library split, not a real product decision. Don't
  treat the literal string as permanent — rename it (chart name,
  `mycrd.*` template prefix, and the sibling directory itself) once the
  actual CRD this library targets is known.
- **`apiVersion: platform.company.io/v1` / `kind: SomeCR` are
  placeholders**, inherited from the original single-chart task spec,
  not a real CRD design. The real shape is explicitly out of scope
  until it's known — see crdkit's `TODO` about wiring `model` fields
  into `spec`.
- **Why this library is thin**: a deliberate choice (confirmed during
  design discussion, not an accident of scope-cutting) to keep every
  reusable mechanism in `crdkit` and let `my-crd` be just:
  `mycrd.render` (the one-line wrapper), `mycrd.systemTokens`/
  `mycrd.defaultTokens`, and integration defines + the chain list. If
  new code here is generic (not CRD-specific), it probably belongs in
  `crdkit` instead.
- **`mycrd.integration.demo` is a proof-of-mechanism stub, not real
  business logic.** It exists only to demonstrate the chain dispatcher
  works end-to-end (it appends one label). Real integrations (database,
  cos, messaging, outbound http, shared low-level objects like a common
  truststore) are intentionally unbuilt. Don't extend `demo` into real
  functionality — add new `mycrd.integration.*` defines instead, and
  read `../crdkit/CLAUDE.md`'s ctx/chain notes first (don't fold
  `chain` into `ctx`; don't mutate `ctx.tokens` with an unresolved
  `@ref@` still inside it, since there's no second fixed-point pass
  after the chain runs; remember chain order = wrapping order).
- **`env` is no longer a settable value at all — it's derived from
  `target`.** Consumers set a root `target` value, typically via
  `--set target=...` at the CLI rather than committed to a values
  file. For most CRDs `target` just IS `env` directly (e.g. `target:
  prod`); optionally `target` can be `<env>-<seq>` (env + a 2-digit
  sequence number, e.g. `prod-01`) for the minority needing multiple
  numbered instances of the same env — both forms are accepted by the
  same rule automatically, no per-CRD configuration to pick one (an
  earlier version of crdkit *required* the sequenced form and errored
  on anything else, which broke the common case — don't reintroduce
  that). `mycrd.render` passes `target` straight through to
  `crdkit.render`, which derives `env` internally
  (`crdkit.deriveTargetEnv`) and exposes it as a reserved, always-wins
  `@ENV@` token — see `../crdkit/CLAUDE.md` for the derivation
  mechanics and the "match:" regex tier this reuses. Only a completely
  unset `target` records an `# ERROR:` diagnostic (rather than failing
  the render); the token dicts throughout this repo's fixtures assume
  `target:`, not `env:`.
- **Locked/default token set (`API_GROUP`, `LIBRARY_VERSION` /
  `LOG_LEVEL`, `TIMEOUT`) is illustrative**, carried over from the
  original task spec — not validated against real requirements for
  whatever CRD this ends up being. Named UPPER_SNAKE_CASE per crdkit's
  naming-convention rule (see `../crdkit/CLAUDE.md`) — this library's
  own tokens are expected to already comply, not exempt from the
  warning they'd otherwise trigger.
- **`ownership.yaml` is an example/placeholder**, not wired into any CI
  enforcement — a future diff-checker script is explicitly out of
  scope.

## Cross-repo contract

- Depends on `../crdkit` via `file://../crdkit` — assumes sibling
  checkout layout on disk. See `../my-crd-test/CLAUDE.md` for the same
  assumption one level further out.
- Consumers call `mycrd.render` with their own root context (`.`) —
  this chart is never a normal subchart with values nested under
  `.Values.myCrd.*`. Values live at the consumer's root (`env`,
  `tokens`, and whatever else — see `README.md` for the full shape).
