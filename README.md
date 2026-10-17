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

services:
  orders:                                # service ID (any string)
    type: environment                    # a type from mycrd.serviceTypes
    environment:                         # variables of this service
      VAR1: "val1"                       # scalar: same for every target
      VAR2:                              # dict: a literal key per target/rung
        default: "nonprod"
        prod: "prod"
      VAR3: "this @VAR1@ is nice"        # variables can reference others
      VAR4:
        default: "generic"
        match:                           # regex against the full target string,
          - "prod-0[1-3]": "canary-@AT@1"  # tried once, wins over any literal
                                         # key — see "Target escalation" below
      DB_HOST:
        targetContainer: main            # export: main/side-car/both (absent = none)
        default: "db.internal"           # same dedicated-attribute/match/escalation
                                         # resolution as any variable
  greeter:
    type: demo                           # demonstration type (see "Service types")
    greeting: "hi @ENV@"

some:
  other:
    part:
      attr: "@VAR3@ resolves here"       # @NAME@ markers work anywhere
                                         # outside of services: itself
      env: "@ENV@"                       # this library's own env-equivalent
                                         # token (see "Library-owned tokens"
                                         # below) — NOT a crdkit built-in
```

Variable names must be `UPPER_SNAKE_CASE` (`^[A-Z][A-Z0-9_]*$`) — a
non-conforming name still resolves and renders, but records a
`# WARNING:` (applies to every token, including the library's own
locked/default ones).

`@AT@` is crdkit's one reserved built-in marker — always resolves to a
literal `@`; a variable named `AT` is discarded with a `# WARNING:`.
`@ENV@` is NOT a crdkit concept — it's an ordinary locked token this
library defines itself (see "Library-owned tokens" below); consumers
can't override it because it's in `system`, not because crdkit reserves
the name.

Variables are declared only under `services.<ID>.environment`; a root
`tokens:` key is not read and records a `# WARNING:`.

### Token model

- Every variable becomes a flat, global token. A DECLARATION is a plain
  scalar (same value everywhere) or a dict, with `targetContainer`/
  `service`/`match` (all optional) coexisting flat alongside however
  many literal target-name keys the token needs.
- `service` and `targetContainer` are ANNOTATIONS: static metadata,
  never resolved. `service` is always the ID of the declaring service
  (an explicit one is ignored with a `# WARNING:`).
- A variable name may be declared by one service only: when two services
  declare it, the alphabetically first service keeps it and an
  `# ERROR:` is recorded.
- A service with a missing or unknown `type` is skipped entirely
  (`# WARNING:`), its `environment` included.
- Malformed shapes record a `# WARNING:` and are ignored: root `services`
  not a map (whole key ignored), `services.<ID>` not a map (service
  skipped), `services.<ID>.environment` not a map (only the environment
  is ignored; the service's type handler still runs).
- `targetContainer` is one of `main`, `side-car`, `both`, `none`
  (default); any other value records an `# ERROR:` and is treated as
  `none`. Tokens with `main`/`side-car`/`both` are EXPORTED into the
  rendered CR (see "Output").
- Resolving a token (`crdkit.token.value`) returns a separate shape,
  `{value}` — the interpolated result for one name+target pair (a
  string, or a structure if the selected entry is itself one).

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
5. A value GENERATED by a service type for the exact `target` (e.g. the
   `demo` type's greeting) — below everything a consumer declared.

If nothing resolves, rendering emits an `# ERROR:` comment (see
Diagnostics below) rather than failing — except a malformed `match:`
regex, which aborts the render outright (a Helm template error, the one
deliberate departure from "never fail()" in this whole system).

### Library-owned tokens

- **locked** (`templates/_tokens.system.tpl` → `mycrd.systemTokens`):
  `API_GROUP`, `LIBRARY_VERSION`, `ENV`. A consumer variable of the same
  name never changes the value.
- **default** (`mycrd.defaultTokens`): `LOG_LEVEL`, `TIMEOUT`. A
  consumer variable of the same name overrides the value.

`LIBRARY_VERSION` reports this library chart's own version (via
`crdkit.dependencyVersion`), not the consuming chart's. `ENV` is this
library's own `@ENV@`-equivalent (`mycrd.deriveEnv`,
`templates/_target.tpl`) — not a crdkit concept.

A consumer variable named like a library token may carry annotations
(e.g. `targetContainer: main`, to export it):
- annotations the library set are locked (a different value records a
  `# WARNING:`); missing ones are filled in;
- `targetContainer` can only widen (`none` → anything; `main` →
  `main`/`both`; `side-car` → `side-car`/`both`; `both` stays);
  narrowing records a `# WARNING:` and keeps the library value;
- for a locked token, value keys are ignored with a `# WARNING:` (`token
  '<NAME>' is reserved by the library — only annotations were applied`),
  the annotations still apply.

### Service types

`type` selects a handler from `mycrd.serviceTypes` (ordered; handlers run
in that order, services of one type alphabetically):

- `environment` — a plain bag of variables (`environment:` only).
- `demo` — demonstration type. `greeting: "<text>"` generates the
  variable `<ID>_GREETING` (ID upper-cased, `-` → `_`), exported to the
  main container. A consumer declaration of the same name under the
  service's `environment` overrides it; its `default` too.

Every type accepts `environment:`. Generated values rank below every
consumer-declared source.

Adding a type:
1. `templates/serviceTypes/_<type>.tpl` defining `mycrd.serviceType.<type>`
   (params `{ctx, id, service}`).
2. Add the name to `mycrd.serviceTypes` (`templates/_services.tpl`).
3. Contribute variables with `mycrd.service.addVar` (`{ctx, id, name,
   value, targetContainer?}`); a name owned by another service records
   an `# ERROR:`.

### Integrations

`mycrd.render` wires a fixed chain into `crdkit.render`:
`mycrd.integrations.preamble` always first — the only thing giving the
rendered CR a shape at all (`apiVersion`/`kind`, `metadata.name`,
`metadata.labels`, `spec`) — then `mycrd.integrations.services` (the
service-type dispatcher), then `mycrd.integrations.serviceOutput`
(always last). Further integrations (database, cos, messaging, outbound
http, ...) land as `mycrd.integrations.*` defines as this library grows.

Every integration must emit no literal text of its own — only mutate
`ctx.model`/`ctx.tokens` via `crdkit.ensureDictKey`/`dictMerge`/
`listExtend`/`token.add`/`token.underlay` (all empty-returning).
`crdkit.integrations.chain` calls each chain entry directly — an
integration never recurses into it itself. A token an integration
exports (`targetContainer` main/side-car/both) must carry
`{service: <ID>}`, or `serviceOutput` records an `# ERROR:`.

### Output

Exported variables land under `spec.services.<ID>`:

```yaml
spec:
  services:
    orders:
      type: environment
      environment:
        DB_HOST:
          value: db.prod          # resolved for the render's target
          targetContainer: main
```

A service without exported variables does not appear.

### Diagnostics

Problems are never fatal — collected and emitted as YAML comments at
the top of the rendered manifest:

```
# ERROR: no value found for 'SOME_TOKEN' — target chain exhausted at 'PROD' starting from 'prod-01'
# WARNING: token 'API_GROUP' is reserved by the library — only annotations were applied
```

Downstream tooling greps for the exact prefixes `# ERROR:` / `# WARNING:`.

Service-level problems (unknown type, a variable declared by two services,
invalid `targetContainer`, an exported token without a service, ...) are
reported the same way.

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

Suites under `tests/`: `token_resolution_test.yaml`,
`services_test.yaml`, `service_output_test.yaml`,
`annotation_policy_test.yaml`, `snapshot_test.yaml`. Two harness probes
(`harness/templates/annotation_policy_probe.yaml` via `policyProbe`,
`service_output_probe.yaml` via `outputProbe`) render only when their
values key is set, and cover paths no end-to-end input reaches.

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
placeholder — see `templates/integrations/_preamble.tpl`).
