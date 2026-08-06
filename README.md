# my-crd

A Helm **library chart** rendering a single Kubernetes Custom Resource
from a standardized, target-aware `values.yaml` shape. Consumed by
application repos as a pinned dependency — never deployed on its own.
Renders only the CR manifest; not Deployments/Services/etc.

Built on [`crdkit`](../crdkit) (generic token resolution / diagnostics /
integration-chaining engine). `my-crd` supplies everything crdkit can't
know: this CR's `apiVersion`/`kind` (via a "preamble" integration, first
in the chain), locked/default tokens, its own target-escalation
taxonomy, and its integration chain.

## Usage

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
`.Values.myCrd`. See [`harness/values.yaml`](harness/values.yaml) and
[`harness/ci/test-values/`](harness/ci/test-values/) for worked
examples.

### Values shape

```yaml
target: prod      # opaque string to crdkit; this library recognizes a
                  # bare env name (as here) or "<env>-<seq>" (e.g.
                  # "prod-01") for CRDs needing multiple numbered
                  # instances of the same env — see "Target escalation"
                  # below. Typically supplied via --set target=... at
                  # the CLI, not committed to a values file. Only
                  # checked lazily, if a token resolution needs it.

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
    targetContainer: main                # opt-in: main/side-car/both (default "none")
    default: "db.internal"               # same dedicated-attribute/match/escalation resolution as any token

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
`# WARNING:` (applies to every token, including the library's own
locked/default ones).

`@AT@` is crdkit's one reserved built-in marker — always resolves to a
literal `@`; `tokens.AT` is discarded with a `# WARNING:` if redefined.
`@ENV@` is NOT a crdkit concept — it's an ordinary locked token this
library defines itself (see "Library-owned tokens" below); consumers
can't override it because it's in `system`, not because crdkit reserves
the name.

### Token model

- A token DECLARATION is a plain scalar (same value everywhere) or a
  dict, with `targetContainer`/`match` (both optional) coexisting flat
  alongside however many literal target-name keys the token needs.
- Resolving a token (`crdkit.resolveValue`) returns a separate shape,
  `{value, targetContainer}` — the interpolated result for one
  name+target pair.
- Declare `targetContainer` (as `DB_HOST` above) when a token should be
  picked up by the downstream k8s controller as a container env var:
  `main`, `side-car`, `both`, or `none` (default). my-crd/crdkit don't
  create the env var themselves — only resolve the value and carry
  `targetContainer` through for the controller to read.

See `../crdkit/README.md`'s "Token model" for the full mechanics.

### Target escalation

`target` is opaque to crdkit; this library owns the taxonomy
(`templates/_target.tpl`). Resolution order, first match wins:

1. A literal key equal to the EXACT `target` string (a "dedicated
   attribute") — any granularity: `"prod-01"`, `"prod"`, `"PROD"`.
2. `match:` — an ordered list of `{regex: value}` rules against the
   full `target` string, full-string anchored, tried once. `value` may
   reference capture groups (`$1`, `$2`, ...).
3. Walk this library's escalation chain (`mycrd.parentTarget`):
   `<env>-<seq> -> env -> family (qa/qam1/qap1 all collapse to "QA") ->
   "NONPROD"/"PROD" tier -> "default"`. Every rung visited gets cached.
4. `default` — a hardcoded, last-resort fallback checked directly,
   regardless of taxonomy.

If nothing resolves, rendering emits an `# ERROR:` comment (see
Diagnostics below) rather than failing — except a malformed `match:`
regex, which aborts the render outright (a Helm template error, the one
deliberate departure from "never fail()" in this whole system).

### Library-owned tokens

- **locked** (`templates/_tokens.system.tpl` → `mycrd.systemTokens`):
  `API_GROUP`, `LIBRARY_VERSION`, `ENV`. Consumers cannot override
  these — an attempt is discarded with a `# WARNING:`.
- **default** (`mycrd.defaultTokens`): `LOG_LEVEL`, `TIMEOUT`. Consumers
  *can* override these.

`LIBRARY_VERSION` reports this library chart's own version (via
`crdkit.dependencyVersion`), not the consuming chart's. `ENV` is this
library's own `@ENV@`-equivalent (`mycrd.deriveEnv`,
`templates/_target.tpl`) — not a crdkit concept.

### Integrations

`mycrd.render` wires a fixed chain into `crdkit.render`:
`mycrd.integration.preamble` always first — the only thing giving the
rendered CR a shape at all (`apiVersion`/`kind`, `metadata.name`,
`metadata.labels`, `spec`) — then `mycrd.integration.demo`, a
proof-of-mechanism stub. Real integrations (database, cos, messaging,
outbound http, ...) land as `mycrd.integration.*` defines as this
library grows.

Every integration must emit no literal text of its own — only mutate
`ctx.model`/`ctx.tokens` via `crdkit.ensureDictKey`/`dictMerge`/
`listExtend`/`addToken` (all empty-returning), then recurse into
`crdkit.integrations.chain`.

### Diagnostics

Problems are never fatal — collected and emitted as YAML comments at
the top of the rendered manifest:

```
# ERROR: no value found for 'SOME_TOKEN' — target chain exhausted at 'PROD' starting from 'prod-01'
# WARNING: token 'API_GROUP' is reserved by the library and was overridden back to the library value
```

Downstream tooling greps for the exact prefixes `# ERROR:` / `# WARNING:`.

Only a token actually referenced somewhere gets checked — a declared
but unused token produces no diagnostic even if broken. Reference it
(e.g. via a spare `@NAME@` marker) to get it validated.

## Local dev / testing

`harness/` (`type: application`, depends on `file://../`) + `tests/`
exercise `mycrd.render` end to end — real preamble, real integration
chain, real crdkit underneath.

```sh
make test              # helm unittest harness -f '../tests/*_test.yaml'
make test-diagnostics   # ./tests/diagnostics_test.sh — greps raw output
                        # for "# ERROR:"/"# WARNING:" (helm-unittest
                        # can't see comments)
make dev                # plain-renders every harness/ci/test-values/*.yaml
                        # fixture for quick manual/visual inspection
make render VALUES=path/to/wip.yaml   # render one arbitrary values file
```

`tests/snapshot_test.yaml` commits full rendered examples via
helm-unittest's `matchSnapshot` — both a regression test and a
browsable example of real output. Review the diff before ever running
`helm unittest -u`.

This harness sits on a two-level `file://` chain (`harness → my-crd →
crdkit`); `helm dependency update` is NOT transitive. Every Makefile
target above depends on `update-deps`, which refreshes both levels,
bottom-up, automatically — see `../CLAUDE.md`'s "Layout" section.

## Out of scope for now

ArgoCD CMP wiring, GitLab CI pipeline files, full `values.schema.json`
generation, `helm-docs` integration, real integration implementations,
and the real CRD's `apiVersion`/`kind`/`spec` shape (currently a
placeholder — see `templates/_integration.preamble.tpl`).
