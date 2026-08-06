# my-crd

A Helm **library chart** that renders a single Kubernetes Custom
Resource from a standardized, env-aware `values.yaml` shape. It is
meant to be consumed by application repos as a pinned dependency — never
deployed on its own.

This chart does **not** render Deployments/Services/etc. It only
produces the CR manifest that a separate controller reconciles.

Built on top of [`crdkit`](../crdkit), which provides the generic token
resolution / diagnostics / integration-chaining engine. `my-crd` supplies
everything crdkit can't know on its own: this CR's `apiVersion`/`kind`
(set via a "preamble" integration, first in the chain below — not a
param, crdkit doesn't accept one), its locked/default tokens, its own
target-escalation taxonomy, and its integration chain.

## Usage

In a consuming chart:

```yaml
# Chart.yaml
dependencies:
  - name: my-crd
    version: "0.0.0"        # pin to the version you've validated against
    repository: "file://../my-crd"   # or a real chart repo once published
```

```gotemplate
{{/* templates/cr.yaml */}}
{{ include "mycrd.render" . }}
```

`mycrd.render` is always called with the consuming chart's own root
context (`.`) — values live at the root of `.Values`, not nested under
`.Values.myCrd`. See the worked example in
[`harness/values.yaml`](harness/values.yaml) and the fixtures in
[`harness/ci/test-values/`](harness/ci/test-values/).

### Values shape

```yaml
target: prod      # required if you reference any token that needs it (no
                  # proactive check otherwise — see "Diagnostics" below).
                  # An opaque string as far as crdkit is concerned; THIS
                  # library recognizes it as either a bare env name, as
                  # here, or "<env>-<seq>" (seq = 2 digits, e.g. "prod-01")
                  # if this CRD needs multiple numbered instances of the
                  # same env — see "Target escalation" below. Typically
                  # supplied via --set target=... at the CLI rather than
                  # committed to a values file.

tokens:
  TOKEN1: "val1"                         # scalar: same for every target
  TOKEN2:                                # dict: a literal key per target/rung
    default: "nonprod"
    prod: "prod"
  TOKEN3: "this @TOKEN1@ is nice"        # tokens can reference other tokens
  TOKEN4:
    default: "generic"
    match:                               # regex against the full target string,
      - "prod-0[1-3]": "canary-@AT@1"    # tried once, wins over any literal
                                          # key — see "Target escalation" below
  DB_HOST:
    value: "db.internal"                 # same dedicated-attribute/match/escalation resolution as any token
    targetContainer: main                # opt-in: main/side-car/both (default "none") —
                                          # see "Token model" below

some:
  other:
    part:
      attr: "@TOKEN3@ resolves here"     # @NAME@ markers work anywhere
                                          # outside of tokens: itself
      env: "@ENV@"                       # this library's own env-equivalent
                                          # token (see "Library-owned tokens"
                                          # below) — NOT a crdkit built-in
```

Token names must be `UPPER_SNAKE_CASE` (`^[A-Z][A-Z0-9_]*$`) — a
non-conforming name still resolves and renders, but records a
`# WARNING:` (see `../crdkit/CLAUDE.md`; this applies to every token,
including the library's own locked/default ones, not just yours).

`@AT@` is crdkit's one reserved built-in marker — it always resolves to
a literal `@`, and `tokens.AT` is discarded with a `# WARNING:` if a
consumer tries to redefine it. `@ENV@`, by contrast, is NOT a crdkit
concept at all — it's an ordinary LOCKED token this library defines
itself (see "Library-owned tokens" below); it behaves the same way
(consumers can't override it) but for a different reason (it's in
`system`, not because crdkit reserves the name).

### Token model

Every resolved token is `{value, targetContainer}`, not a bare string.
A plain scalar or the env-varying dict (as `TOKEN1`–`TOKEN4` above) is
shorthand for `{value: <that>}` with `targetContainer` implied `"none"`
— nothing changes for a token that doesn't care about this. Declare
`targetContainer` explicitly (as `DB_HOST` above) when a token should
be picked up by the downstream k8s controller as a container env var:
one of `main`, `side-car`, `both`, or `none` (default). my-crd/crdkit
don't create the env var themselves — only resolve the value and carry
`targetContainer` through to the rendered output for the controller to
read. See `../crdkit/CLAUDE.md` for the full mechanics.

### Target escalation

crdkit itself has no concept of "env"/"family"/"tier" — `target` is an
opaque string to it (see `../crdkit/CLAUDE.md`/`README.md`). This
library owns the entire taxonomy, via `templates/_target.tpl`. A
token's value is looked up in this order, first match wins:

1. a literal key equal to the EXACT `target` string (a "dedicated
   attribute") — works at any granularity: `"prod-01"`, `"prod"`,
   `"PROD"`, whatever you used as `target`.
2. `match:` — an ordered list of `{regex: value}` rules evaluated
   against the full `target` string, full-string anchored, tried
   ONCE regardless of what `target` looks like. `value` may reference
   the pattern's own capture groups (`$1`, `$2`, ...). Lets a token
   vary by something finer-grained than a single target — a family of
   instances by sequence number — without enumerating every target
   string as its own dict key.
3. walk this library's own escalation chain (`mycrd.parentTarget`),
   one rung at a time, checking a literal key at each: `<env>-<seq> ->
   env -> family (qa/qam1/qap1 all collapse to "QA") -> "NONPROD"/
   "PROD" tier -> "default"`. Every rung visited gets cached, so a
   later target sharing any of them is instant.

If nothing matches anywhere along that chain, rendering does not fail
— it emits an `# ERROR:` comment (see Diagnostics below) and leaves
that value empty. A malformed regex under `match:` is the one exception
in this whole library that **does** abort the render outright (a Helm
template error, not a diagnostic comment) — see `../crdkit/CLAUDE.md`
for why that's an accepted, deliberate departure from the "never
fail()" rule.

### Library-owned tokens

- **locked** (`templates/_tokens.system.tpl` → `mycrd.systemTokens`):
  `API_GROUP`, `LIBRARY_VERSION`, `ENV`. Consumers cannot override
  these — an attempt is discarded with a `# WARNING:` and the library's
  value wins.
- **default** (`mycrd.defaultTokens`): `LOG_LEVEL`, `TIMEOUT`. Consumers
  *can* override these by defining the same key under their own
  `tokens:`.

`LIBRARY_VERSION` reports **this library chart's own version** (via
`crdkit.dependencyVersion`), not the consuming chart's version — library
charts don't get their own root context, so a naive `.Chart.Version`
would report the wrong thing. `ENV` is this library's own
`@ENV@`-equivalent (`mycrd.deriveEnv`, `templates/_target.tpl`) — NOT a
crdkit built-in; crdkit has no such concept anymore (see "Target
escalation" above).

### Integrations

`mycrd.render` (`templates/_render.tpl`) wires a fixed integration chain
into `crdkit.render`: `mycrd.integration.preamble` ALWAYS first — it's
the ONLY thing that gives the rendered CR a shape at all, since
`crdkit.render` itself doesn't read `Values` or assume anything about
`ctx.model` (see `../crdkit/CLAUDE.md`/`README.md`). It sets
`apiVersion`/`kind`, `metadata.name`, `metadata.labels` (consumer's own,
then `crdkit.standardLabels`, then this library's own library-version
label — see `templates/_integration.preamble.tpl`'s doc comment for why
that order is the precedence policy), and `spec` (copied straight from
the consumer's own `Values.spec`) — then `mycrd.integration.demo`, a
placeholder proving the chain mechanism end-to-end beyond the preamble
(see `templates/_integrations.tpl`);
real integrations (database, cos, messaging, outbound http, ...) land
there as this library grows, each contributing low-level fields (env
vars, volumes, secretRefs, ...) to the shared model that
`crdkit.render` assembles. Every integration, `preamble` included, must
emit no literal text of its own — only mutate `ctx.model`/`ctx.tokens`
via helpers that are themselves empty-returning
(`crdkit.ensureDictKey`/`dictMerge`/`listExtend`/`addToken`), then
recurse into `crdkit.integrations.chain`. See `../crdkit/CLAUDE.md` for
why mixing real text output into an integration's body is exactly the
kind of thing that has corrupted render output here before.

### Diagnostics

Problems are never fatal (`fail()` is never called from resolution
logic) — they're collected and emitted as YAML comments at the top of
the rendered manifest, so a mistake in one consumer repo can't wedge
CI-wide re-renders:

```
# ERROR: no value found for 'SOME_TOKEN' — target chain exhausted at 'PROD' starting from 'prod-01'
# WARNING: token 'API_GROUP' is reserved by the library and was overridden back to the library value
```

Downstream tooling greps for the exact prefixes `# ERROR:` / `# WARNING:`.

**Only a token that's actually referenced somewhere gets checked at
all.** A token declared under `tokens:` but never used anywhere in the
rest of your values (no `@NAME@` marker referencing it) is never
resolved, so a mistake in it (e.g. no matching rung anywhere along the
escalation chain) produces no diagnostic — it's simply never looked at.
If you want a token validated even when nothing currently references
it, reference it somewhere rather than relying on it being checked just
because it's declared.

## Local dev / testing

`harness/` (a `type: application` chart depending on `file://../`) +
`tests/` mirror crdkit's own harness/tests split, and exercise
`mycrd.render` end to end — real preamble, real integration chain, real
crdkit underneath.

```sh
make test              # helm unittest harness -f '../tests/*_test.yaml'
                        # (targeted per-path assertions, tests/token_resolution_test.yaml)
make test-diagnostics   # ./tests/diagnostics_test.sh — greps raw output
                        # for "# ERROR:"/"# WARNING:" comments, which
                        # helm-unittest can't see (comments don't
                        # survive YAML parsing)
make dev                # plain-renders every harness/ci/test-values/*.yaml
                        # fixture for quick manual/visual inspection
make render VALUES=path/to/wip.yaml   # render one arbitrary values
                        # file — e.g. a work-in-progress one that isn't
                        # checked in as a fixture yet
```

`tests/snapshot_test.yaml` additionally commits full end-to-end rendered
examples via helm-unittest's `matchSnapshot` (starting with
`minimal.yaml`) — both a regression test (an unexpected drift fails the
test) and an always-current, browsable example of real output, in one
artifact. Review the diff before ever running `helm unittest -u` to
regenerate a snapshot.

This harness sits on top of a two-level `file://` dependency chain
(`harness → my-crd → crdkit`) — `helm dependency update` is NOT
transitive, so running it only at the harness level would silently
bundle a stale crdkit copy if `my-crd`'s own hadn't been refreshed
first. Every target above (`update-deps`, which `dev`/`render`/`test`/
`test-diagnostics` all depend on) refreshes both levels, bottom-up,
automatically — you don't need to remember to `cd` anywhere yourself.
See `../CLAUDE.md`'s "Layout" section for the full story.

## Out of scope for now

ArgoCD CMP wiring, GitLab CI pipeline files (env-parity matrix render,
ownership diff-checker), full `values.schema.json` generation,
`helm-docs` integration, real integration implementations (database/cos/
messaging/http), and the real CRD's `apiVersion`/`kind`/`spec` shape
(currently a placeholder — see `templates/_integration.preamble.tpl`,
the one place that decision lives now that crdkit has no opinion on it
at all).
