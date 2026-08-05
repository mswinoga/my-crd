# my-crd

A Helm **library chart** that renders a single Kubernetes Custom
Resource from a standardized, env-aware `values.yaml` shape. It is
meant to be consumed by application repos as a pinned dependency — never
deployed on its own.

This chart does **not** render Deployments/Services/etc. It only
produces the CR manifest that a separate controller reconciles.

Built on top of [`crdkit`](../crdkit), which provides the generic token
resolution / diagnostics / integration-chaining engine. `my-crd` supplies
everything crdkit can't know on its own: this CR's `apiVersion`/`kind`,
its locked/default tokens, and its integration chain.

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
[`../my-crd-test/values.yaml`](../my-crd-test/values.yaml) and the
fixtures in [`../my-crd-test/ci/test-values/`](../my-crd-test/ci/test-values/).

### Values shape

```yaml
target: prod      # required — env is derived from this, not set directly.
                  # Usually just the env name itself, as here; optionally
                  # "<env>-<seq>" (seq = 2 digits, e.g. "prod-01") if this
                  # CRD needs multiple numbered instances of the same env
                  # — see "Env & target" below. Typically supplied via
                  # --set target=... at the CLI rather than committed to
                  # a values file.

tokens:
  TOKEN1: "val1"                         # scalar: same in every env
  TOKEN2:                                # dict: resolved per env
    default: "nonprod"
    prod: "prod"
  TOKEN3: "this @TOKEN1@ is nice"        # tokens can reference other tokens
  TOKEN4:
    default: "generic"
    match:                               # regex against target, first
      - "prod-0[1-3]": "canary-@AT@1"    # match wins, above env/tier/default
                                          # — see "Env & target" below
  DB_HOST:
    value: "db.internal"                 # same env/tier/match/default resolution as any token
    targetContainer: main                # opt-in: main/side-car/both (default "none") —
                                          # see "Token model" below

some:
  other:
    part:
      attr: "@TOKEN3@ resolves here"     # @NAME@ markers work anywhere
                                          # outside of tokens: itself
      env: "@ENV@"                       # env, derived from target, is
                                          # itself a substitutable token
```

Token names must be `UPPER_SNAKE_CASE` (`^[A-Z][A-Z0-9_]*$`) — a
non-conforming name still resolves and renders, but records a
`# WARNING:` (see `../crdkit/CLAUDE.md`; this applies to every token,
including the library's own locked/default ones, not just yours).

`@AT@` is a reserved, built-in marker that always resolves to a literal
`@`. `@ENV@` is a reserved, built-in token holding the env derived from
`target`. Neither is user-definable — `tokens.AT`/`tokens.ENV` are
discarded with a `# WARNING:` if a consumer tries.

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

### Env & target

`env` is derived from `target`. Usually `target` just IS `env` (e.g.
`target: prod` → `env: prod`); if `target` matches `<env>-<seq>` (seq =
2 digits, e.g. `prod-01`) the part before the hyphen is used instead —
both forms are accepted automatically, no configuration needed to pick
one. See `../crdkit/CLAUDE.md` for the exact mechanics. A token's
per-env dict is then looked up in this order, first match wins:

1. `match:` — an ordered list of `{regex: value}` rules evaluated
   against the full `target` string (not just `env`), full-string
   anchored. `value` may reference the pattern's own capture groups
   (`$1`, `$2`, ...). Lets a token vary by something finer-grained than
   env — a specific target instance, or a family of them by sequence
   number — without enumerating every target string as its own dict
   key.
2. the exact `env` value (e.g. `qap1`)
3. its family tier, uppercased: `dev`→`DEV`, `test`→`TEST`,
   `qa`/`qam1`/`qap1`→`QA`, `prod`→`PROD`
4. the family tier's super-tier: `DEV`/`TEST`/`QA`→`NONPROD`, `PROD`→`PROD`
5. `default`

If nothing matches, rendering does not fail — it emits an `# ERROR:`
comment (see Diagnostics below) and leaves that value empty. A
malformed regex under `match:` is the one exception in this whole
library that **does** abort the render outright (a Helm template
error, not a diagnostic comment) — see `../crdkit/CLAUDE.md` for why
that's an accepted, deliberate departure from the "never fail()" rule.

### Library-owned tokens

- **locked** (`templates/_tokens.system.tpl` → `mycrd.systemTokens`):
  `API_GROUP`, `LIBRARY_VERSION`. Consumers cannot override these — an
  attempt is discarded with a `# WARNING:` and the library's value wins.
- **default** (`mycrd.defaultTokens`): `LOG_LEVEL`, `TIMEOUT`. Consumers
  *can* override these by defining the same key under their own
  `tokens:`.

`LIBRARY_VERSION` reports **this library chart's own version** (via
`crdkit.dependencyVersion`), not the consuming chart's version — library
charts don't get their own root context, so a naive `.Chart.Version`
would report the wrong thing.

### Integrations

`mycrd.render` (`templates/_render.tpl`) wires a fixed integration chain
into `crdkit.render`. Today that's just `mycrd.integration.demo`, a
placeholder proving the chain mechanism end-to-end (see
`templates/_integrations.tpl`); real integrations (database, cos,
messaging, outbound http, ...) land there as this library grows, each
contributing low-level fields (env vars, volumes, secretRefs, ...) to
the shared model that `crdkit.render` assembles.

### Diagnostics

Problems are never fatal (`fail()` is never called from resolution
logic) — they're collected and emitted as YAML comments at the top of
the rendered manifest, so a mistake in one consumer repo can't wedge
CI-wide re-renders:

```
# ERROR: no value for env 'prod' and no 'default' defined for 'tokens.SOME_TOKEN'
# WARNING: token 'API_GROUP' is reserved by the library and was overridden back to the library value
```

Downstream tooling greps for the exact prefixes `# ERROR:` / `# WARNING:`.

## Local dev / testing

This chart has no test harness of its own — see
[`../my-crd-test`](../my-crd-test), a separate sibling repo that depends
on this one via `file://../my-crd` and exercises it end-to-end.

## Out of scope for now

ArgoCD CMP wiring, GitLab CI pipeline files (env-parity matrix render,
ownership diff-checker), full `values.schema.json` generation,
`helm-docs` integration, real integration implementations (database/cos/
messaging/http), and the real CRD's `apiVersion`/`kind`/`spec` shape
(currently a placeholder — see the `TODO` in `crdkit`'s
`templates/_render.tpl`).
