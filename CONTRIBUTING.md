# Contributing to my-crd

A specific CR-rendering library built on `crdkit`. Thin: supplies
apiVersion/kind, locked/default tokens, its own target-escalation
taxonomy, and an integration chain.

## Layout

- `templates/` — the library.
- `harness/` + `tests/` — local dev/test harness exercising
  `mycrd.render` end to end (and transitively `crdkit`).

Dependency chain: `my-crd` → `crdkit`, via `file://../crdkit` — requires
the two repos to stay siblings on disk. The harness adds one more
`file://../` hop (`harness → my-crd → crdkit`).

**`file://` dependencies are copied/packaged, not symlinked, and `helm
dependency update` is NOT transitive** — it only refreshes a chart's own
*direct* dependencies, packaging each target's current on-disk state
as-is, including whatever's already in that target's own `charts/`
folder. Editing `crdkit` and testing via `harness` requires, in
order:

1. `helm dependency update` — repackages crdkit into
   `charts/crdkit-<version>.tgz`.
2. `cd harness && helm dependency update` — repackages `my-crd`
   into `harness/charts/my-crd-<version>.tgz`.

Skipping step 1 doesn't error — step 2 silently bundles whatever stale
crdkit copy is in `charts/`. **The `Makefile` does both steps
automatically for every target** (`update-deps`, which
`dev`/`render`/`test`/`test-diagnostics` all depend on) — the manual
sequence above is for understanding the mechanism, not something to do
by hand.

**Release tags**: `v<chart version>` (e.g. `v0.0.7`). Release order:
bump `version` in `Chart.yaml` → `make docs` (the generated `$id` embeds
the version) → commit → tag `v<version>`. `tests/diagnostics_test.sh`
fails on stale committed docs.

`make` may be shadowed in some shells — if `make dev`/`make test` fail
with `function definition file not found`, use `command make <target>`
instead.

## Documentation conventions

Applies to CONTRIBUTING.md/README.md files and every template's doc comment.

**Style**
- Write all documentation in English (CONTRIBUTING.md, READMEs, doc
  comments, specs, plans).
- Be concise: short bullet/numbered points, not prose paragraphs.
- Document the CURRENT design only — no history (no "used to be X,"
  "an earlier version did Y," "removed because Z"). State the decision
  and, if needed, its rationale — drop everything about what came
  before it.
- This includes IMPLICIT history: don't describe a shape by what it
  ISN'T or NO LONGER HAS (e.g. "no 'value' key exists here") — describe
  only what it IS. A negation is fine only as an actionable warning at
  a call site (e.g. "never read `.value` here — resolve via X instead"),
  never as scene-setting about a shape's design.
- Give a short "why" for non-obvious architectural/implementation
  decisions; skip the rationale when the decision is self-evident.
- Never label a template or file as "new" (e.g. "(public, new)",
  "new `templates/_paths.tpl`") — in docs, specs, plans or doc comments.
  Name it plainly; specs and plans describe the target state.

**Per-template doc comments** — structure every `define`'s comment as:
1. **Header line**: `<template name> (<scope>)` — long comments push the
   `define` line out of view. The scope here is authoritative (see
   "Template scopes" below).
2. **Purpose**: a short plain-prose paragraph (no heading, no bullet)
   saying what the template is for; a `callback` also says what invokes
   it (e.g. "Invoked by crdkit's integration chain.").
3. **Interface**: exact parameter shape and return shape only.
4. **Implementation notes** (omit if nothing non-obvious applies):
   corner cases, warnings, invariants a caller must respect.

**Template scopes** (by audience):
- `public` — consumer API; the only template a consuming chart may
  include (`mycrd.render`).
- `protected` — helpers a service type handler or chain integration is
  meant to call: `mycrd.service.addVar`, `addFile`, `value`,
  `referenceService`, `referenceVar`, `referenceMount`,
  `referenceFile`; a stable contract for extension authors. Every other `mycrd.service.*` template is
  `internal`.
- `callback` — implemented here, invoked by the framework under a fixed
  name and signature, never called directly: chain entries
  (`mycrd.integrations.*`), type handlers (`mycrd.serviceType.*`) and
  their schemas (`mycrd.serviceType.*.schema`), `mycrd.parentTarget`
  (crdkit's `parentTargetTemplate`).
- `internal` — implementation detail; never called from handlers or
  integrations.

Boundary cases (each also noted in the template's doc comment):
- `mycrd.service.add` is `internal`, not `protected` — the dispatcher
  calls it before each type handler; a handler never does.
- `mycrd.paths.*` are `internal` — handlers never build model
  locations; the `protected` helpers do, so a node can move without
  touching handlers.
- `mycrd.serviceTypes` is `internal` — nothing calls it from a
  handler, but adding a type means adding its name there (position =
  run order) plus its `mycrd.serviceType.<type>` and
  `mycrd.serviceType.<type>.schema` callbacks.

**`.internal` name suffix**: not used — consumers call only
`mycrd.render`, so nearly every template is internal and the suffix
would carry no information.

**Inline comments** (inside the template body): one short line per
non-obvious "why" — never restate what the code already does.

Example skeleton:
```gotemplate
{{/*
mycrd.example (internal)

Resolves X for Y.

Interface:
- Params (dict): { "a": <string>, "b": <dict> }
- Returns: <shape>

Implementation notes:
- <corner case, only if non-obvious>
*/}}
{{- define "mycrd.example" -}}
...
{{- end -}}
```

## Template code conventions

- Static data a YAML-returning `define` emits (fixed lists/dicts) is
  written as literal YAML, not built with `list`/`dict` + `toYaml`:
  ```gotemplate
  value:
  - service
  - targetContainer
  ```
  Keep `| toYaml` for values built at render time; under a `value:`
  wrapper use `| toYaml | nindent 2` (a bare `value: {{ x | toYaml }}`
  is invalid YAML for a list, and `fromYaml` then silently returns an
  error dict).

## Purpose

A specific CR-rendering library on `crdkit`. Supplies `apiVersion`/`kind`
(via a preamble integration), locked/default tokens, its own
target-escalation taxonomy (`mycrd.parentTarget`), its token annotations
(`service`, `targetContainer`), its service types, and its integration
chain. Deliberately thin — generic code belongs in `crdkit` instead.

## Design decisions

- "my-crd"/"mycrd" is a placeholder name — not permanent. Rename (chart
  name, `mycrd.*` prefix, directory) once the target CRD is known.
- `apiVersion: @API_GROUP@/v1` / `kind: SomeCR` are placeholders — real
  CRD shape is out of scope until known. Set by
  `mycrd.integrations.preamble`, always first in `chain`. `apiVersion` is
  a literal `@API_GROUP@/v1` marker (a locked token), resolved by
  crdkit's substitution pass after the chain runs. Change both only in
  this one define.
- `mycrd.integrations.preamble` is load-bearing, must stay first in
  `chain` — it's the only thing giving the rendered CR a shape
  (`apiVersion`/`kind`, `metadata.name`, `metadata.labels`, an empty
  `spec`). Without it, a render is `{}`.
  - Input is never copied verbatim (exception: `metadata.labels`, read
    from the normalized input): every node under `spec` is built by an
    integration from the input DSL. Unknown root keys (consumer keys,
    `global`, root `spec`/`services`) are ignored silently; unknown keys
    under `metadata`, `application` or a service → schema WARNING.
  - Labels: three ordered `crdkit.dictMerge` calls into
    `ctx.model.metadata.labels` — order IS the precedence policy:
    consumer's own `metadata.labels` first, `crdkit.standardLabels`
    second (overwrites accidental consumer collisions), library-version
    label third. The chain runs after, so a real integration can still
    override any of it.
  - Consumer label values resolve per target (a marker or a token
    declaration): each goes through `crdkit.schema.node` +
    `crdkit.schema.value` (same path as `mycrd.service.value`) before the
    first `crdkit.dictMerge`; a marker to a token that does not exist yet
    stays for the final substitution pass.
  - Library-version label (`platform.company.io/library-version`) is
    my-crd's own responsibility — crdkit knows its own version but not
    that "my-crd" exists.
- Chain: `[preamble, services, references, schema]`. `references`
  runs after every handler: a referenced node may be created by a
  handler that runs after the one referencing it. `schema` is always
  last: per-target values may reference tokens a handler generates.
- Values schema: `mycrd.schema` (`templates/_schema.tpl`, root open:
  `values: {type: any}`) — `target`, `renderMode`, `metadata.labels`
  (values per target), `application.services` (a switch `by: type`, cases
  generated by `range` over `mycrd.serviceTypes`, each case
  `mycrd.serviceType.<type>.schema` including
  `mycrd.schema.serviceBase`: `type`, `enabled` (default `true`),
  `environment` (values `{type: scalar}`)). `target`, `renderMode`,
  `type` and `enabled` are `static: true`.
  - `mycrd.render` runs the structural pass (`crdkit.schema.validate`),
    then `mycrd.serviceFields` (see "Field references"), then
    `mycrd.serviceTokens` (which gets the rewritten `input` directly),
    and seeds `ctx.mycrd.schema`/`ctx.mycrd.input` (rewritten)/
    `ctx.mycrd.templates` through crdkit.render's `state`. Everything after reads `ctx.mycrd.input`
    (`mycrd.values.*` take `ctx`), never `.Values` (exceptions:
    `target`, `renderMode`, read by `mycrd.render`/`mycrd.renderMode`).
  - `mycrd.integrations.schema` runs the value pass with
    `ctx.mycrd.validated` as the shared `seen` dict, on a copy of the
    input: disabled services dropped, each `environment` variable
    replaced by `@<NAME>@` (only names whose token the service owns).
    Why: a variable is checked as the token it became — library and
    generated values included, a resolution problem reported once.
  - `mycrd.service.value` (protected, `{ctx, id, field, target?}`) is
    how a handler reads a field: `crdkit.schema.node` +
    `crdkit.schema.value`, path from `mycrd.values.serviceKeys` +
    `crdkit.schema.path`. Markers are substituted at call time: a
    handler sees tokens from types EARLIER in `mycrd.serviceTypes`
    only; a later type's marker stays and is resolved, unchecked, by
    the final substitution pass. A resolved string of an `int` /
    `number` / `bool` field comes back converted (crdkit's
    `resolveAndCheck.internal`).
  - Every schema node has a `doc` (except a switch case's `type`),
    enforced by `tests/docs_test.yaml`.
- Individual integration templates live in `templates/integrations/_<name>.tpl`
  — one file per integration, each defining `mycrd.integrations.<name>`.
  The leading underscore goes on the FILE, not the folder — Helm's
  "don't render this as a manifest" check keys off a file's own
  basename, not any parent directory name.
- `env` is not a crdkit concept — my-crd owns it entirely. `target` is
  opaque to crdkit; my-crd recognizes `<env>` or `<env>-<seq>` (e.g.
  `prod-01`). `templates/_target.tpl`: `mycrd.matchSequence` (regex
  primitive on `crdkit.matchRules`), `mycrd.deriveEnv` (computes locked
  `ENV`), `mycrd.parentTarget` (taxonomy: `<env>-<seq> → env → family →
  tier → "default"`). An empty `target` only produces a lazy
  `# ERROR:` if something resolves against it (see
  `harness/ci/test-values/missing-target.yaml`). Fixtures set
  `target:`.
- Locked/default tokens (`API_GROUP`, `LIBRARY_VERSION`, `ENV`,
  `COS_BUCKET_PATH`, `COS_TOKEN` / `LOG_LEVEL`, `TIMEOUT`) are
  illustrative placeholders; `COS_*` are library templates used by the
  `cos` type (see "Library templates").
  `API_GROUP`/`LIBRARY_VERSION` are referenced directly by
  `mycrd.integrations.preamble` — don't rename/remove without updating
  it.
- `ownership.yaml` is an example/placeholder, not wired into CI.

## Services and annotations

- Consumer input is `application.services.<ID>` (reserved keys `type`,
  `environment`, `enabled`, plus type-specific keys). Variables live only under
  `application.services.<ID>.environment`; a root `tokens:` key is not read (a
  non-empty one records a WARNING).
- `mycrd.values.services` (`templates/_values.tpl`, internal) is the only
  place that knows the input path: `{ctx}` → `{value: <services map>}`
  from `ctx.mycrd.input`, `{}` when absent; records nothing.
  `serviceTokens` (passing `{mycrd: {input}}` as `ctx`), the dispatcher,
  `mycrd.service.add` and `mycrd.integrations.schema` read services
  through it; `mycrd.values.serviceKeys` (`{id}` →
  `{value: [application, services, <id>]}`) is the same location as keys.
- Names: schema `keys.pattern` — service IDs `^[A-Z0-9_]+$`,
  `environment` keys `^[A-Z][A-Z0-9_]*$` (ERROR, key dropped; the only
  name check — crdkit checks no token names). Convention (not checked):
  a service's variables prefixed `<ID>_`.
- Token annotations (`templates/_services.tpl`, `mycrd.tokenAnnotationNames`):
  `service` (owning service ID) and `targetContainer`
  (`main`/`side-car`/`both`/`none`; absent = `none`). Passed to
  `crdkit.render` as its `tokenAnnotations`; crdkit stores them, my-crd owns
  every rule about them.
- Shape checks belong to the structural schema pass (all WARNING,
  dropped from the input: `application`/`application.services`/a
  service/`environment` not a map, missing/unknown `type` — whole
  service skipped; ERROR: non-boolean `enabled`, dropped so the default
  `true` applies).
- `mycrd.serviceTokens` runs before `crdkit.render` (called by
  `mycrd.render` with the normalized `input`, recording into the shared
  `diag` seed):
  - library `system`/`defaults` scalars → `{default: <v>}`;
  - a disabled service (see "Disabled services") is skipped silently;
  - services in alphabetical ID order;
  - each variable: scalar → `{default: <v>}`, `service: <ID>` set (an
    explicit one is overwritten with a WARNING);
  - a name already declared by an earlier service → ERROR, first kept;
  - `targetContainer` outside the accepted set → ERROR, corrected to
    `none`;
  - library-owned names go through the annotation policy (below).
- `mycrd.annotationPolicy` is a pure function
  (`{name, library, requested, diag}` → `{value: <annotations>}`):
  - a library-set annotation is locked (change → WARNING); a missing
    one is filled in from the consumer;
  - `targetContainer` only widens: none→any, `main`→`main`/`both`,
    `side-car`→`side-car`/`both`, `both`→`both`; narrowing → WARNING;
  - `defaults` names: consumer values override the library's, the
    policy decides annotations;
  - `system` names (scalar or dict): the consumer declaration is removed
    from `tokens`, its policy-approved annotations are written onto the
    library declaration, value keys → WARNING `only annotations were
    applied`. Why: this is the only way a consumer can export a locked
    token without being able to change its value.
  - Library tokens carry no annotations today, so locks and narrowing
    are reachable only through the policy probe (see Testing).
- Service types: `mycrd.serviceTypes` is the ORDERED list (`{value:
  [...]}`: `environment`, `greeter`, `leader`, `db`, `cos`); order = handler call
  order. Each type has `templates/serviceTypes/_<type>.tpl` defining
  `mycrd.serviceType.<type>` (params `{ctx, id, service}`).
  `mycrd.integrations.services` is the dispatcher (types in list order,
  services of a type alphabetically): per service it calls
  `mycrd.service.add`, then the handler.
  - `environment` has no handler logic (its variables arrive via
    `serviceTokens`).
  - `greeter` (example type): needs `greeting` (absent → nothing
    generated); `addVar <ID>_GREETER = <ID>` (main) and `addFile` mount
    `<ID>-config`, source `configMap`, file `message` = greeting
    (through `mycrd.service.value`).
  - `leader` (example type): needs `greeter` (a service ID, read through
    `mycrd.service.value`: a marker or per-target value resolves; absent →
    nothing generated); `addVar <ID>_SEED = "5"` (main),
    `referenceVar` of the greeter's `<greeter>_GREETER`, `referenceFile`
    `message` of the mount `<greeter>-config`.
  - `db` (example type, field references): `instance`, `host`, `port`
    (int) required, `password` (default `secret://@.instance@/password`),
    `url`, `options` (list); `addVar <ID>_PASSWORD` / `<ID>_PORT` (main)
    from `password` / `port`, each through `mycrd.service.value` and only
    when present.
  - `cos` (example type, library templates): `instance`, `bucket`
    (string, required); `addVar <ID>_TOKEN = "@COS_TOKEN@"` (main),
    unconditionally — a missing field is the structural ERROR plus a
    "possible typo" WARNING.
  - New type: add the handler and its `.schema` define, add its name to
    `mycrd.serviceTypes`, add a service of the type to
    `harness/documentation/example.yaml` (its generated output becomes
    the type's `sections`; a missing one fails `diagnostics_test.sh`),
    run `make docs`.
- Disabled services: `enabled: false` (YAML boolean only; static, no
  target ladder, no markers) removes a service from the output.
  - `mycrd.service.enabled` (`{id, service}` → `true` or an EMPTY string,
    never `false`: a non-empty string is truthy) is the one check;
    `serviceTokens`, `mycrd.integrations.services` and
    `mycrd.integrations.references` use it; the structural pass reports
    a non-boolean value (`'application.services.<ID>.enabled' must be
    of type 'bool' — ignored`) and the default `true` applies.
  - The dispatcher skips a disabled service (no `service.add`, no
    callback) and records it in `ctx.mycrd.disabled.<ID>`; a callback of
    an enabled service still sees `enabled` in `.service`.
  - Its `environment` is never declared: a marker to it stays unresolved
    ("possible typo" WARNING), no collision with an enabled service's
    variable of the same name, a library token it lists stays unexported.
  - A disabled service is checked by the structural pass only, never by
    the value pass.
- Output is written by the handlers through helpers in
  `templates/_services.tpl` (all take `ctx` and `id`):
  - `mycrd.service.add` (dispatcher only): writes
    `spec.application.services.<id>.type` and every exported variable the service
    declares, marks the service added.
  - `mycrd.service.addVar` (`name, value, targetContainer?`) →
    `crdkit.token.underlay` annotated `{service: <ID>}`: generated
    values rank below every consumer-declared source (their `default`
    included). A token already owned by another service → ERROR, value
    ignored. When the token's final `targetContainer` is
    `main`/`side-car`/`both` the helper writes
    `environment.<NAME>: {value: "@<NAME>@", targetContainer}` and
    records the owner.
  - `mycrd.service.addFile` (`mount, source, file, content`): creates
    the mount `{source}` if absent; mounts are shared. A different
    `source` → ERROR, file not added; an existing file → ERROR naming
    its owner, first kept.
  - `mycrd.service.referenceService|Var|Mount|File`: record a reference
    only; validation happens in `mycrd.integrations.references`.
  - Any helper other than `add` for an `id` that was not added → ERROR
    `service '<id>' was not added — helper '<helper>' ignored`
    (`mycrd.service.guard`).
  - Any other code adding an exported token (e.g. via
    `crdkit.token.add`) is not written to the model; exported output
    goes through `addVar`.
- Registry `ctx.mycrd` (`mycrd.service.registry`, each key created on
  first use; `schema`/`input`/`templates` seeded by `mycrd.render`):
  `{schema, input, templates: [<template name>], added: {<id>: true}, disabled: {<id>: true}, owners:
  {<pointer>: <id>}, contributors: {<mount pointer>: {<id>: true}},
  references: {<id>: {<pointer>: {segments, var?}}}, validated:
  {<path>|<target>: true}}`. Internal bookkeeping, never emitted; crdkit must
  never use the key `mycrd`. Why a descriptor and not `true` for a
  reference: the integration checks the node by its segments and needs
  the variable's service and name for the not-exported message, without
  decoding a pointer.
- `mycrd.paths.service|var|mount|file` (`templates/_paths.tpl`) are the
  only place that knows where a node lives in the model
  (`spec.application.services`, `spec.application.volumeMounts`); each
  returns `{value: [segments]}`.
  `mycrd.paths.pointer` encodes segments as an RFC 6901 JSON Pointer
  (`~` → `~0` first, then `/` → `~1`).
- `mycrd.integrations.references`: per service (alphabetical) and
  pointer (sorted): self-reference (own service node, a node owned by
  the service, a mount whose only contributor is the service) →
  WARNING, dropped; pointer under a disabled service (`ctx.mycrd.disabled`,
  service and variable targets) → ERROR `... which belongs to disabled
  service '<disabled>' — dropped`, checked before the existence check
  (a mount/file target carries no service and falls under the next
  rule); node missing (`crdkit.model.hasPath` on the
  segments) → ERROR, dropped (a variable whose token exists with the
  service but is not exported has its own message); the rest →
  `spec.application.services.<id>.references`, unique and sorted, key omitted when
  empty. References are metadata for the controller: nothing is copied
  or mounted.
- Read `.Values` via `.Values | toYaml | fromYaml` before `dig`/map
  operations (Helm's `chartutil.Values` fails `dig`'s type assertion).

## Field references

- Consumers write `@.<path>@` (relative, same service only);
  `mycrd.fieldMarkers` (`templates/_fields.tpl`, `{id, value}` →
  `{value}`) rewrites it to `@<ID>.<path>@` and `@.@` to the plain
  text `<ID>` in every string leaf. It tokenizes like crdkit (leftmost,
  non-overlapping markers): only a marker starting with `@.` is
  rewritten, so `@AT@` escapes stay. The absolute form is an implementation
  detail: not documented, not checked.
- `mycrd.serviceFields` (`{input, schema, system?, defaults?, diag}` →
  `{input, tokens, templates}`; templates: see "Library templates")
  runs after the structural pass (defaults applied, so a default's
  markers are rewritten too) and before `mycrd.serviceTokens`:
  - rewrites every key of each enabled service except `type`/`enabled`
    (`environment` included); a disabled service is left as is;
  - declares every key except `type`/`enabled`/`environment` as token
    `<ID>.<path>` (`mycrd.serviceFields.declare`, recursive), by the
    node's `type` from `crdkit.schema.node` — never crdkit's
    `shape.internal`: `map` → its keys, never itself (a dict there is
    ambiguous); `any` → `{default: v}`; every other type → a dict as
    written (token declaration), else `{default: v}`;
  - annotation keys are dropped from a field declaration: a field token
    is never exported;
  - records nothing.
- Field token names hold a `.`, which no variable, library token or
  service ID can — no collision check needed; `mycrd.render` merges
  them into the consumer `tokens`.
- `mycrd.service.addVar` (`value`) and `addFile` (`content`) rewrite
  through `mycrd.fieldMarkers` with their `id`: a handler may generate
  values referencing its service's fields.
- No diagnostics of their own: typo/absent/disabled → crdkit's
  "possible typo" WARNING (only when the marker reaches the model), a
  self-reference → the cycle ERROR, a marker in a `static: true`
  field → the structural ERROR. Messages name the absolute form
  (`LOOP.greeting`).

## Library templates

- Template (`mycrd.templates`, `templates/_fields.tpl`, `{system,
  defaults}` → `{value: [<names, sorted>]}`): a library declaration
  with a relative marker (`@.<path>@` or `@.@`) in any string leaf (markers found by
  `mycrd.markerNames`, tokenized like crdkit), or a marker to another
  template — iterated to a fixed point. A cycle between templates is
  left to crdkit's cycle ERROR at resolution.
- Used by the library only (handlers, integrations): consumers never
  reference, export or override one — not supported, not checked.
- `mycrd.serviceFields` takes `system`/`defaults` and returns
  `templates` too; per enabled service and template `T` it declares
  `<ID>..<T>` (`mycrd.serviceFields.instantiate`): the declaration
  normalized (scalar → `{default: v}`, `system` replaces `defaults`),
  annotation keys dropped, `mycrd.fieldMarkers` with `<ID>`, then
  `mycrd.templateMarkers` (`{id, templates, value}`: `@T@` →
  `@<ID>..T@`). Why the empty path segment: a copy never collides with
  a field token `<ID>.<path>`. Unused copies cost nothing (lazy
  resolution) and report nothing.
- `mycrd.render` seeds the list as `ctx.mycrd.templates`;
  `mycrd.service.addVar` (`value`) and `addFile` (`content`) run
  `mycrd.templateMarkers` after `mycrd.fieldMarkers`.
- The library declaration stays as written: a template used outside
  `addVar`/`addFile` is unbound — an integration's job when one needs
  it.
- A field the using service lacks → crdkit's "possible typo" WARNING
  naming `@<ID>.<field>@`; no diagnostics of their own.

## Render mode

- Values key `renderMode`: `validate` or `deploy` (default). Resolved
  by `mycrd.renderMode` (internal); any other value records the ERROR
  `values key 'renderMode' must be 'validate' or 'deploy' — rendering in
  deploy mode` and means `deploy`, so a typo aborts instead of passing.
- `mycrd.render` seeds `diag`, resolves the mode, captures
  `crdkit.render`'s output (crdkit appends to the seed in place, so the
  seed holds every diagnostic afterwards), then:
  - `validate` — prints the output (errors stay `# ERROR:` comments);
    never fails, CI greps `^# ERROR:`;
  - `deploy` with errors — `fail` with `mycrd.controlData` (internal):
    summary line, context line (release, namespace, target, library
    version via `crdkit.dependencyVersion`), de-duplicated errors then
    warnings in crdkit's `# ERROR:`/`# WARNING:` format, hint line;
  - otherwise — prints the output (warnings stay comments).
- Why `fail` only here: it always exits 1 and empties stdout, so it is
  reserved for the single final decision; this is the deliberate exception to
  "Diagnostics never call `fail()`".
- Tests: `harness/values.yaml` sets `renderMode: validate` (merged into
  every fixture); deploy fixtures override it. helm-unittest drops the
  first line of a multi-line `fail` message before matching, so the
  summary line is asserted in `diagnostics_test.sh` (`check_fails`), the
  rest in `tests/render_mode_test.yaml` (`failedTemplate`; target
  `call.yaml` explicitly).

## Cross-repo contract

Depends on `../crdkit` via `file://../crdkit` (see "Layout" for the
staleness gotcha). Consumers call `mycrd.render` with their own root
context (`.`); values live at the consumer's root (`target`,
`application`, `metadata`, `renderMode`; see `README.md`).

## Testing

`harness/` (`type: application`, depends on `file://../`) +
`tests/` mirror crdkit's own harness/tests split, but call the
real entry point `mycrd.render` (`templates/call.yaml` is
`{{ include "mycrd.render" . }}`), exercising the real preamble, chain,
and crdkit underneath.

- Test mechanisms, each covering something the others can't:
  - `helm unittest` — targeted per-path assertions:
    `token_resolution_test.yaml` (resolution), `services_test.yaml`
    (`application.services` → tokens, greeter type,
    `spec.application.services` / `spec.application.volumeMounts`
    output, library-token handling),
    `references_test.yaml` (leader type, reference validation, disabled
    targets),
    `field_references_test.yaml` (field references end to end, db
    type),
    `library_templates_test.yaml` (library templates end to end, cos
    type),
    `helpers_test.yaml` (service helpers through the probe),
    `paths_test.yaml` (node locations, pointer escaping),
    `values_test.yaml` (input location),
    `annotation_policy_test.yaml` (policy lattice, locks, fill-in),
    `docs_test.yaml` (values reference snapshot, every node documented).
  - `matchSnapshot` (`tests/snapshot_test.yaml`) — full rendered
    documents, committed as snapshots; both a regression test and a
    browsable example. Review the diff before ever running `helm
    unittest -u`.
  - `tests/diagnostics_test.sh` — greps for `# ERROR:`/`# WARNING:`
    comments, which helm-unittest can't see (comments don't survive
    YAML parsing). Its header maps the diagnostics that need probes.
- Probes in `harness/templates/`: `annotation_policy_probe.yaml`
  (`.Values.policyProbe`), `paths_probe.yaml` (`.Values.pathsProbe`),
  `values_probe.yaml` (`.Values.valuesProbe`) and
  `helpers_probe.yaml` (`.Values.helpersProbe`: builds a `ctx` with
  `mycrd.schema`/`mycrd.input` seeded, runs a list of `mycrd.service.*`
  calls, optionally the references and schema integrations; `fields:
  true` runs `mycrd.serviceFields` first, over the library tokens or
  `library: {system, defaults}`; `ctx.mycrd.templates` is seeded from
  the same declarations; `resolve` resolves tokens after the calls;
  `fieldMarkers` / `serviceFields` / `templates` / `templateMarkers`
  entries call those directly) call
  internals directly for paths no end-to-end input reaches.
  `documentation.{json,html,md}.yaml` (`.Values.documentation`, set by
  `make docs` as `--set documentation=true` together with
  `-f harness/documentation/example.yaml`) follow the same guard; each
  calls `crdkit.schema.document` through `harness/templates/_documentation.tpl`
  over `mycrd.schema`, the example file and `sections` (the example
  rendered through `mycrd.render`: per service type, generated
  variables, references and the rendered node), and also emits
  `undocumented`, `errors` and `missingTypes`. `make docs` writes
  `input.schema.json` (editors), `VALUES.html` (viewer) and `VALUES.md`.
  The `id` passed to `crdkit.schema.document` is
  `https://raw.githubusercontent.com/mswinoga/my-crd/v<version>/input.schema.json`
  (URL base only in `harness.documentation.document`; `<version>` is
  my-crd's chart version via `crdkit.dependencyVersion`; no `id` when
  `unknown`).
  The example file holds one service of every type in
  `mycrd.serviceTypes` and must render without diagnostics. They render only when their values key is set — never add
  those keys to `harness/values.yaml` (merged into every fixture) or to
  a `harness/ci/test-values/` fixture (`make dev` would print the probe
  document). Fixtures that set a probe key live in
  `harness/ci/probe-values/`, which `make dev` does not scan.
- helm-unittest runs a test without `template:` against every template
  listed in its suite, so a probe's tests live in a suite that lists only
  that probe.
- `make dev` plain-renders every `harness/ci/test-values/*.yaml`
  fixture; `make render VALUES=path/to/wip.yaml` renders one arbitrary
  file. Neither is a pass/fail test.
- Fixtures use `target:` and `application.services:`, upper-case
  service IDs and `<ID>_`-prefixed variables (except fixtures about an
  ID edge case or a name collision).
- A token is made "used" (and so checked) through an exported variable
  of a `PROBE` service, e.g. `PROBE_X: {targetContainer: main, default:
  "@X@"}`; assertions read
  `spec.application.services.PROBE.environment.PROBE_X.value`.
- `harness/values.yaml` is deep-merged into every fixture: keep it
  minimal.
- `harness/ci/failure-cases/` is deliberately NOT scanned by `make dev`
  — holds fixtures expected to make `helm template` abort outright:
  `malformed-match-regex.yaml` (invalid regex) and the deploy-mode
  `render-deploy-errors.yaml` / `render-mode-invalid.yaml`.
- `diagnostics_test.sh` asserts every `harness/ci/test-values/` fixture
  renders without `# ERROR: schema invalid` — the check that
  `mycrd.schema` passes crdkit's self-check — and that the committed
  `input.schema.json`, `VALUES.html` and `VALUES.md` match the
  documentation templates (`make docs` regenerates them), that the
  example renders with empty `errors`/`missingTypes`/`undocumented`,
  and (with `node` available) that the viewer script parses.
- Helm parses values files as YAML 1.1: a service ID `OFF`/`ON`/`YES`/
  `NO` becomes the key `false`/`true` before my-crd sees it — avoid such
  IDs in fixtures.
- The chart root and `harness/` each have a `.helmignore` excluding
  `harness/`/`tests/` from downstream packaging.
