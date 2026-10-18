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
renderMode: deploy  # optional: "deploy" (default) or "validate" — see
                    # "Render mode" below

target: prod      # opaque string to crdkit; this library recognizes a
                  # bare env name (as here) or "<env>-<seq>" (e.g.
                  # "prod-01") for CRDs needing multiple numbered
                  # instances of the same env — see "Target escalation"
                  # below. Typically supplied via --set target=... at
                  # the CLI, not committed to a values file. Only
                  # checked lazily, if a token resolution needs it.

application:
  services:
    ORDERS:                                # service ID (upper case by convention)
      type: environment                    # a type from mycrd.serviceTypes
      enabled: true                        # optional boolean; false disables the
                                           # service — see "Disabled services"
      environment:                         # variables of this service, prefixed
                                           # <SID>_ by convention
        ORDERS_VAR1: "val1"                # scalar: same for every target
        ORDERS_VAR2:                       # dict: a literal key per target/rung
          default: "nonprod"
          prod: "prod"
        ORDERS_VAR3: "this @ORDERS_VAR1@ is nice"  # variables can reference others
        ORDERS_VAR4:
          default: "generic"
          match:                           # regex against the full target string,
            - "prod-0[1-3]": "canary-@AT@1"  # tried once, wins over any literal
                                           # key — see "Target escalation" below
        ORDERS_DB_HOST:
          targetContainer: main            # export: main/side-car/both (absent = none)
          default: "db.internal"           # same dedicated-attribute/match/escalation
                                           # resolution as any variable
        ORDERS_ENV:
          targetContainer: main
          default: "@ENV@"                 # this library's own env-equivalent
                                           # token (see "Library-owned tokens"
                                           # below) — NOT a crdkit built-in
    HELLO:
      type: greeter                        # example type (see "Service types")
      greeting: "hi @ENV@"
    BOSS:
      type: leader                         # example type: references a greeter
      greeter: HELLO

metadata:
  labels:                                  # merged into the CR's labels; @NAME@
    team: "payments-@ENV@"                 # markers resolve here too
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

The rendered CR is built only from these keys — nothing is copied
verbatim. The values are checked against `mycrd.schema` (see "Values
schema"); the reference of every key is [`VALUES.md`](VALUES.md).
Root keys my-crd does not know (the consumer chart's own, `global`, a
root `spec` or `services`) are accepted and ignored; an unknown key
under `metadata`, `application` or a service records a `# WARNING:`.
`@NAME@` markers are resolved in service variables, in type-specific
service keys (e.g. `greeting`) and in `metadata.labels`.

Variables are declared only under
`application.services.<ID>.environment`; a root `tokens:` key is not
read and records a `# WARNING:`.

Conventions (not checked): service IDs are upper case; a service's
variables are prefixed `<SID>_`, as generated variables are.

Reserved service keys: `type`, `environment`, `enabled`. Every other key
belongs to the service type (e.g. `greeting`, `greeter`).

#### Disabled services

`enabled: false` disables a service; absent or `true` enables it.

- Only the YAML boolean `false` disables. Any other non-boolean value
  (`"false"`, `0`, `no-way`) records an `# ERROR:`
  (`'application.services.<ID>.enabled' must be of type 'bool' —
  ignored`) and the default `true` applies.
- The value is static: it is not target-dependent and holds no `@NAME@`
  markers. Per-environment switching uses per-environment values files.
- A disabled service is absent from `spec`: no
  `spec.application.services.<ID>`, no files, no references, and its
  type handler does not run. A type handler of an enabled service sees
  `enabled` (default `true`) in `.service`.
- Its `environment` variables are not declared: a `@NAME@` marker to one
  stays unresolved (the usual "possible typo" `# WARNING:`), a name it
  shares with an enabled service causes no collision, and a library token
  it lists stays unexported.
- A disabled service is still checked by the structural schema pass
  (unknown keys, types), not by the per-target pass.
- A reference to a node under a disabled service (a service or a
  variable of it) is dropped with an `# ERROR:` naming the disabled
  service. See "References".

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
- Malformed shapes record a `# WARNING:` and are ignored (`'<path>' must
  be a map — ignored`): `application`, `application.services`, a
  service (skipped), a service's `environment` (only the environment is
  ignored; the service's type handler still runs).
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
   `greeter` type's `<SID>_GREETER`) — below everything a consumer
   declared.

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
in that order, services of one type alphabetically). `<SID>` is the
service ID upper-cased with `-` replaced by `_`.

- `environment` — a plain bag of variables (`environment:` only).
- `greeter` — `greeting: "<text>"` generates the variable `<SID>_GREETER`
  (value: the service ID, exported to the main container) and the
  configMap mount `<ID>-config` with the file `message` holding the
  greeting. Without `greeting` nothing is generated.
- `leader` — `greeter: "<service ID>"` generates the variable
  `<SID>_SEED` (value `"5"`, exported to the main container) and
  references the greeter's `<GSID>_GREETER` variable and the file
  `message` of its `<greeter>-config` mount. Without `greeter` nothing
  is generated.

A consumer declaration of a generated variable under the service's
`environment` overrides it; its `default` too. Every type accepts
`environment:`. Generated values rank below every consumer-declared
source.

Adding a type:
1. `templates/serviceTypes/_<type>.tpl` defining `mycrd.serviceType.<type>`
   (params `{ctx, id, service}`) and `mycrd.serviceType.<type>.schema`:
   the type's values schema, a map node including
   `mycrd.schema.serviceBase` into its `properties`, every node with a
   `doc` (see "Values schema").
2. Add the name to `mycrd.serviceTypes` (`templates/_services.tpl`).
3. Run `make docs` and commit `VALUES.md`.
4. Read fields through `mycrd.service.value` and contribute output
   through the service helpers (params always include `ctx` and `id`;
   the dispatcher has already added the service):

   | Helper | Extra params | Effect |
   |---|---|---|
   | `mycrd.service.value` | `field, target?` | `{value}`: the service's field (`field` = list of keys) resolved for `target` (default: the render target) and checked against its schema; a violation records an `# ERROR:` naming the target |
   | `mycrd.service.addVar` | `name, value, targetContainer?` | generated variable; exported into `spec.application.services.<id>.environment` when its final `targetContainer` is main/side-car/both; a name owned by another service records an `# ERROR:` |
   | `mycrd.service.addFile` | `mount, source, file, content` | file in a volume mount under `spec.application.volumeMounts`; mounts are shared between services; a different `source` or an existing file records an `# ERROR:` and the file is not added |
   | `mycrd.service.referenceService` | `service` | records a reference to a whole service |
   | `mycrd.service.referenceVar` | `service, name` | records a reference to a variable of a service |
   | `mycrd.service.referenceMount` | `mount` | records a reference to a whole mount |
   | `mycrd.service.referenceFile` | `mount, file` | records a reference to a file in a mount |

   `value` and `content` may hold `@TOKEN@` markers. Node locations
   come from `mycrd.paths.*` (`templates/_paths.tpl`), the only place
   that knows where a node lives in the model.

   `mycrd.service.value` substitutes markers when called: a handler sees
   consumer tokens and tokens generated by types earlier in
   `mycrd.serviceTypes`; a marker to a token a later type generates
   stays in the value (the final substitution pass resolves it,
   unchecked).

### Values schema

`mycrd.schema` (`templates/_schema.tpl`) describes the consumer values in
crdkit's schema DSL (see `../crdkit/README.md`, "Values schema"):
`target`, `renderMode`, `metadata.labels`, and `application.services` —
a switch on `type` with one case per entry of `mycrd.serviceTypes`
(`mycrd.serviceType.<type>.schema`, each including
`mycrd.schema.serviceBase`: `type`, `enabled`, `environment`).

- Structural pass (`mycrd.render`, before the chain): shapes, unknown
  keys, types, defaults (`enabled: true`). Everything after it reads the
  normalized values (`ctx.mycrd.input`), never `.Values`.
- Per-target pass (`mycrd.integrations.schema`, last in the chain): every
  per-target field (e.g. `greeting`, each `environment` variable)
  resolved for the render target and checked; disabled services are
  skipped. A variable is checked as its token.
- `mycrd.service.value` checks a field for any target; each
  `(path, target)` pair is reported once.
- `make docs` writes the Markdown reference to [`VALUES.md`](VALUES.md);
  `make test` snapshots it, `make test-diagnostics` checks the committed
  file is current.

### References

A reference tells the controller that a service depends on a node of the
rendered CR: another service, a variable, a mount, or a file in a mount.
References are metadata — nothing is copied or mounted.

- Written to `spec.application.services.<id>.references` as JSON
  Pointers (RFC 6901) from the CR root, e.g.
  `/spec/application/services/SVC1/environment/SVC1_GREETER`.
  A `/` or `~` inside a name is escaped `~1` / `~0`.
- Recorded by type handlers through the `mycrd.service.reference*`
  helpers; validated after every handler ran, by
  `mycrd.integrations.references` (after the service dispatcher):
  - a reference to a node the service defines itself is dropped with a
    `# WARNING:` (own service, a variable or file it owns, a mount it is
    the only contributor to);
  - a reference to a node under a disabled service is dropped with an
    `# ERROR:` naming it (`which belongs to disabled service '<id>'`);
    a mount or file reference carries no service, so a mount only
    disabled services would have created is reported as a missing node;
  - a reference to a missing node is dropped with an `# ERROR:`; a
    variable whose token exists but is not exported (`targetContainer`
    none) gets a specific message;
  - the remaining pointers are unique and sorted; the `references` key
    is omitted when none remain.

```yaml
application:
  services:
    SVC1: {type: greeter, greeting: hello}
    SVC2: {type: leader, greeter: SVC1}
```

renders

```yaml
spec:
  application:
    services:
      SVC1:
        type: greeter
        environment:
          SVC1_GREETER: {value: SVC1, targetContainer: main}
      SVC2:
        type: leader
        environment:
          SVC2_SEED: {value: "5", targetContainer: main}
        references:
          - /spec/application/services/SVC1/environment/SVC1_GREETER
          - /spec/application/volumeMounts/SVC1-config/files/message
    volumeMounts:
      SVC1-config:
        source: configMap
        files:
          message: hello
```

### Integrations

`mycrd.render` wires a fixed chain into `crdkit.render`:
`mycrd.integrations.preamble` always first — the only thing giving the
rendered CR a shape at all (`apiVersion`/`kind`, `metadata.name`,
`metadata.labels`, an empty `spec`) — then `mycrd.integrations.services` (the
service-type dispatcher), then `mycrd.integrations.references`, then
`mycrd.integrations.schema` (always last: the per-target pass of the
values schema, `mycrd.schema`). Before the chain, `mycrd.render`
validates the values against `mycrd.schema` (structural pass). Further
integrations (database, cos, messaging, outbound
http, ...) land as `mycrd.integrations.*` defines as this library grows.

Every integration must emit no literal text of its own — only mutate
`ctx.model`/`ctx.tokens` via `crdkit.ensureDictKey`/`dictMerge`/
`listExtend`/`token.add`/`token.underlay` (all empty-returning).
`crdkit.integrations.chain` calls each chain entry directly — an
integration never recurses into it itself.

The dispatcher calls `mycrd.service.add` before each type handler. It
writes `spec.application.services.<id>.type` and every exported variable the
service declares. A service helper called for a service that was not
added records an `# ERROR:` and does nothing.

### Output

Every dispatched service lands under `spec.application.services.<ID>`;
mounts under `spec.application.volumeMounts.<mount>`. `spec` is always
present; `spec.application` and below exist only when something is
generated:

```yaml
spec:
  application:
    services:
      ORDERS:
        type: environment
        environment:
          ORDERS_DB_HOST:
            value: db.prod        # resolved for the render's target
            targetContainer: main
    volumeMounts:
      HELLO-config:
        source: configMap
        files:
          message: "hi prod"
```

A service without exported variables appears with its `type` only. A
service of an unknown type, and a disabled service, are skipped.

### Diagnostics

Problems are collected and emitted as YAML comments at the end of the
rendered manifest (in deploy mode, errors abort instead — see "Render
mode"):

```
# ERROR: no value found for 'SOME_TOKEN' — target chain exhausted at 'PROD' starting from 'prod-01'
# WARNING: token 'API_GROUP' is reserved by the library — only annotations were applied
```

Downstream tooling greps for the exact prefixes `# ERROR:` / `# WARNING:`.

Schema problems (`'<values path>' is not a known key — ignored`,
`'<path>' for target '<t>' must be a scalar`, ...) and service-level
problems (a variable declared by two services, invalid
`targetContainer`, a mount `source` conflict, a file defined by two
services, a self-referencing or dangling reference, ...) are reported
the same way.

Every `environment` variable of an enabled service is resolved for the
render target by the per-target schema pass, so a broken one is
reported even when nothing references it.

### Render mode

The values key `renderMode` selects what a render does with errors:

| Value | Mode | Output | Exit |
|---|---|---|---|
| `validate` | validation (CI checking a values file) | rendered object plus `# ERROR:`/`# WARNING:` comments | 0, always |
| absent or `deploy` | deployment (Helm, ArgoCD) | no errors: rendered object (warnings stay as comments); at least one error: the render fails with control data | 0 / 1 |
| anything else | deployment | ERROR `values key 'renderMode' must be 'validate' or 'deploy' — rendering in deploy mode`; the render fails | 1 |

- Only errors abort a deployment; warnings never do.
- Helm cannot set an exit code from a template: `fail` always exits 1
  and empties stdout. Validation mode never fails; CI detects errors by
  grepping `^# ERROR:` in the output:

  ```sh
  helm template … --set renderMode=validate | tee out.yaml; ! grep -q '^# ERROR:' out.yaml
  ```

- The control data (the `fail` message):

  ```
  my-crd: render aborted — <E> error(s), <W> warning(s)
  release: <name>   namespace: <ns>   target: <target>   library: my-crd <version>
  # ERROR: <message>
  # WARNING: <message>
  re-run with renderMode: validate to see the rendered object
  ```

  All errors, then all warnings, de-duplicated.

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
make docs               # writes VALUES.md (the values reference)
```

Suites under `tests/`: `token_resolution_test.yaml`,
`services_test.yaml`, `references_test.yaml`, `helpers_test.yaml`,
`paths_test.yaml`, `values_test.yaml`, `annotation_policy_test.yaml`,
`render_mode_test.yaml`, `docs_test.yaml`, `snapshot_test.yaml`. `harness/values.yaml` sets `renderMode: validate`,
so fixtures with deliberate errors keep rendering; deploy-mode fixtures
override it, and the ones expected to abort live in
`harness/ci/failure-cases/`.
Harness probes (`annotation_policy_probe.yaml` via `policyProbe`,
`paths_probe.yaml` via `pathsProbe`, `values_probe.yaml` via
`valuesProbe`, `helpers_probe.yaml` via `helpersProbe`, `docs_probe.yaml`
via `docsProbe`, all under `harness/templates/`) render only when their
values key is set, and cover paths no end-to-end input reaches. Fixtures
that set a probe key live in `harness/ci/probe-values/`, which
`make dev` does not scan.

`tests/snapshot_test.yaml` commits full rendered examples via
helm-unittest's `matchSnapshot` — both a regression test and a
browsable example of real output. Review the diff before ever running
`helm unittest -u`.

This harness sits on a two-level `file://` chain (`harness → my-crd →
crdkit`); `helm dependency update` is NOT transitive. Every Makefile
target above depends on `update-deps`, which refreshes both levels,
bottom-up, automatically — see `../CLAUDE.md`'s "Layout" section.

## Out of scope for now

ArgoCD CMP wiring, GitLab CI pipeline files, a JSON Schema export of
`mycrd.schema` for editors, real integration implementations,
and the real CRD's `apiVersion`/`kind`/`spec` shape (currently a
placeholder — see `templates/integrations/_preamble.tpl`).
