{{/*
mycrd.serviceTypes (internal)

The ORDERED list of service types this library knows. Order is the order
in which type handlers run (mycrd.integrations.services).

Interface:
- Params: none (any value is ignored).
- Returns YAML: { "value": [<service type name>, ...] }

Implementation notes:
- Scope is internal: no handler or integration calls it. Adding a
  service type means adding its name here (position = run order) and
  defining its `mycrd.serviceType.<type>` callback.
- Wrapped in `value:` — Helm's `fromYaml` cannot decode a bare list.
*/}}
{{- define "mycrd.serviceTypes" -}}
value:
- environment
- greeter
- leader
{{- end -}}

{{/*
mycrd.normalizeDeclarations (internal)

Normalizes library-owned declarations (`system`/`defaults`) so that
annotations can later be attached and consumer dicts deep-merge onto
them instead of replacing a scalar.

Interface:
- Params (dict): { "decls": <dict of token declarations, each a scalar or a dict> }
- Returns YAML: the same names, every declaration a dict (a scalar
  `v` becomes `{default: v}`); dict declarations are copied.
*/}}
{{- define "mycrd.normalizeDeclarations" -}}
{{- $out := dict -}}
{{- range $name, $decl := (.decls | default dict) -}}
  {{- if kindIs "map" $decl -}}
    {{- $_ := set $out $name (deepCopy $decl) -}}
  {{- else -}}
    {{- $_ := set $out $name (dict "default" $decl) -}}
  {{- end -}}
{{- end -}}
{{- $out | toYaml -}}
{{- end -}}

{{/*
mycrd.annotationNames (internal)

The annotation names this library owns on token declarations: `service`
(the owning service ID) and `targetContainer`. mycrd.render hands the
same list to crdkit.render, which treats each as a reserved key (never a
target entry).

Interface:
- Params: none (any value is ignored).
- Returns YAML: { "value": [<annotation name>, ...] }
*/}}
{{- define "mycrd.annotationNames" -}}
value:
- service
- targetContainer
{{- end -}}

{{/*
mycrd.splitAnnotations (internal)

Splits a token declaration into this library's annotations
(mycrd.annotationNames) and everything else (target entries, `match`),
so the annotation policy can treat the two parts separately.

Interface:
- Params (dict): { "decl": <token declaration dict> }
- Returns YAML: { "annotations": <dict>, "values": <dict> }
*/}}
{{- define "mycrd.splitAnnotations" -}}
{{- $names := (include "mycrd.annotationNames" . | fromYaml).value -}}
{{- $annotations := dict -}}
{{- $values := dict -}}
{{- range $key, $v := (.decl | default dict) -}}
  {{- if has $key $names -}}
    {{- $_ := set $annotations $key $v -}}
  {{- else -}}
    {{- $_ := set $values $key $v -}}
  {{- end -}}
{{- end -}}
{{- dict "annotations" $annotations "values" $values | toYaml -}}
{{- end -}}

{{/*
mycrd.annotationPolicy (internal)

Pure policy function: decides which annotations a token ends up with
when the library and a consumer both declare it.

Interface:
- Params (dict): { "name": <token name, for messages>, "library": <dict
  of annotations set by the library>, "requested": <dict of annotations
  a consumer variable asks for>, "diag": <dict, appended to in place> }
- Returns YAML: { "value": <final annotations dict> }

Implementation notes:
- An annotation the library set is locked; a missing one is filled in
  from `requested`.
- `targetContainer` may only widen. Allowed requests per library value
  (absent behaves like `none`): none -> none/main/side-car/both;
  main -> main/both; side-car -> side-car/both; both -> both. A request
  outside that set (including an unrecognized value) records a WARNING
  and keeps the library value.
- Any other locked annotation differing from the request records a
  WARNING and keeps the library value.
- When the library has no `targetContainer` (or `none`), a request that
  is not one of main/side-car/both/none is ignored without a
  diagnostic: validating consumer values is mycrd.serviceTokens' job.
*/}}
{{- define "mycrd.annotationPolicy" -}}
{{- $name := .name -}}
{{- $diag := .diag -}}
{{- $library := .library | default dict -}}
{{- $requested := .requested | default dict -}}
{{- $widening := dict
      "none" (list "none" "main" "side-car" "both")
      "main" (list "main" "both")
      "side-car" (list "side-car" "both")
      "both" (list "both") -}}
{{- $final := deepCopy $library -}}
{{- range $key := sortAlpha (keys $requested) -}}
  {{- $want := index $requested $key -}}
  {{- if eq $key "targetContainer" -}}
    {{- $have := get $library "targetContainer" | default "none" -}}
    {{- $allowed := get $widening (toString $have) | default (list) -}}
    {{- if has $want $allowed -}}
      {{- $_ := set $final $key $want -}}
    {{- else if ne (toString $have) "none" -}}
      {{- if ne (toString $want) (toString $have) -}}
        {{- $_ := set $diag "warnings" (append $diag.warnings (printf "variable '%s' tries to narrow library targetContainer '%v' to '%v' — library value kept" $name $have $want)) -}}
      {{- end -}}
    {{- end -}}
  {{- else if hasKey $library $key -}}
    {{- if ne (toString (index $library $key)) (toString $want) -}}
      {{- $_ := set $diag "warnings" (append $diag.warnings (printf "variable '%s' tries to change library annotation '%s' — library value kept" $name $key)) -}}
    {{- end -}}
  {{- else -}}
    {{- $_ := set $final $key $want -}}
  {{- end -}}
{{- end -}}
value: {{ $final | toYaml | nindent 2 }}
{{- end -}}

{{/*
mycrd.serviceTokens (internal)

Pre-render step: warns about a non-empty root `tokens:` (a values key
nothing reads), turns `Values.services.<ID>.environment` into token
declarations annotated with `service: <ID>`, and normalizes the
library-owned declarations.

Interface:
- Params (dict): { "context": <consumer root $>, "diag": <dict with
  "errors"/"warnings" lists, appended to in place>, "system": <dict>,
  "defaults": <dict> }
- Returns YAML: { "tokens": <dict>, "system": <dict>, "defaults": <dict> }
  — ready to pass to crdkit.render.

Implementation notes:
- Runs before crdkit builds ctx, so it records into the shared `diag`
  seed itself.
- Services are visited in alphabetical ID order, variables in
  alphabetical name order: the first service declaring a name owns it.
- A service with a missing/unknown `type` is skipped entirely,
  `environment` included.
- Malformed shapes record a WARNING each (absent or null is valid and
  silent):
  - root `services` not a map: `values key 'services' must be a map —
    ignored`.
  - `services.<ID>` not a map: `service '<ID>' must be a map — service
    skipped` (no unknown-type warning on top).
  - `services.<ID>.environment` not a map: `service '<ID>':
    'environment' must be a map — ignored`; the rest of the service
    (type, DSL handler) is processed as usual.
- A scalar variable becomes `{default: <v>}`; `service` is always set to
  the parent service ID (an explicit one is overwritten with a WARNING).
- `targetContainer` outside main/side-car/both/none is corrected to
  `none` with an ERROR.
- A variable named like a `defaults` token keeps the library's locked
  annotations and may widen `targetContainer` / fill in missing ones
  (mycrd.annotationPolicy); its value keys deep-merge over the
  library's in crdkit.
- A variable named like a `system` token is removed from `tokens`; only
  its policy-approved annotations are written onto the system
  declaration (value keys record a WARNING), so a library-owned value
  can be exported without being overridable.
- Read `.Values` through `toYaml | fromYaml` first: Sprig's dict
  functions need plain maps, not Helm's `chartutil.Values`.
*/}}
{{- define "mycrd.serviceTokens" -}}
{{- $diag := .diag -}}
{{- $values := .context.Values | toYaml | fromYaml -}}
{{- $knownTypes := (include "mycrd.serviceTypes" . | fromYaml).value -}}
{{- $containers := list "main" "side-car" "both" "none" -}}

{{- $system := include "mycrd.normalizeDeclarations" (dict "decls" .system) | fromYaml -}}
{{- $defaults := include "mycrd.normalizeDeclarations" (dict "decls" .defaults) | fromYaml -}}

{{- if $values.tokens -}}
  {{- $_ := set $diag "warnings" (append $diag.warnings "values key 'tokens' is not read — declare variables under services.<ID>.environment") -}}
{{- end -}}

{{- $tokens := dict -}}
{{- $owners := dict -}}

{{- $services := dict -}}
{{- if kindIs "map" $values.services -}}
  {{- $services = $values.services -}}
{{- else if not (kindIs "invalid" $values.services) -}}
  {{- $_ := set $diag "warnings" (append $diag.warnings "values key 'services' must be a map — ignored") -}}
{{- end -}}
{{- range $id := sortAlpha (keys $services) -}}
  {{- $svc := index $services $id -}}
  {{- $type := "" -}}
  {{- if not (kindIs "map" $svc) -}}
    {{- $_ := set $diag "warnings" (append $diag.warnings (printf "service '%s' must be a map — service skipped" $id)) -}}
  {{- else -}}
    {{- $type = get $svc "type" | default "" -}}
  {{- end -}}
  {{- if not (kindIs "map" $svc) -}}
  {{- else if not (has $type $knownTypes) -}}
    {{- $_ := set $diag "warnings" (append $diag.warnings (printf "service '%s' has unknown type '%v' — service skipped" $id $type)) -}}
  {{- else -}}
    {{- $env := dict -}}
    {{- $rawEnv := index $svc "environment" -}}
    {{- if kindIs "map" $rawEnv -}}
      {{- $env = $rawEnv -}}
    {{- else if not (kindIs "invalid" $rawEnv) -}}
      {{- $_ := set $diag "warnings" (append $diag.warnings (printf "service '%s': 'environment' must be a map — ignored" $id)) -}}
    {{- end -}}
    {{- range $name := sortAlpha (keys $env) -}}
      {{- $raw := index $env $name -}}
      {{- $decl := dict "default" $raw -}}
      {{- if kindIs "map" $raw -}}
        {{- $decl = deepCopy $raw -}}
      {{- end -}}
      {{- if hasKey $decl "service" -}}
        {{- $_ := set $diag "warnings" (append $diag.warnings (printf "variable '%s' in service '%s' sets 'service' explicitly — ignored" $name $id)) -}}
      {{- end -}}
      {{- $_ := set $decl "service" $id -}}
      {{- if hasKey $owners $name -}}
        {{- $_ := set $diag "errors" (append $diag.errors (printf "variable '%s' is declared by services '%s' and '%s' — keeping '%s'" $name (index $owners $name) $id (index $owners $name))) -}}
      {{- else -}}
        {{- $_ := set $owners $name $id -}}
        {{- if and (hasKey $decl "targetContainer") (not (has $decl.targetContainer $containers)) -}}
          {{- $_ := set $diag "errors" (append $diag.errors (printf "invalid targetContainer '%v' for '%s' — must be one of main/side-car/both/none" $decl.targetContainer $name)) -}}
          {{- $_ := set $decl "targetContainer" "none" -}}
        {{- end -}}
        {{- $_ := set $tokens $name $decl -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/* library-owned names: apply the annotation policy to consumer variables sharing the name. */}}
{{- range $name := sortAlpha (keys $defaults) -}}
  {{- if hasKey $tokens $name -}}
    {{- $mine := include "mycrd.splitAnnotations" (dict "decl" (index $tokens $name)) | fromYaml -}}
    {{- $lib := include "mycrd.splitAnnotations" (dict "decl" (index $defaults $name)) | fromYaml -}}
    {{- $final := include "mycrd.annotationPolicy" (dict "name" $name "library" $lib.annotations "requested" $mine.annotations "diag" $diag) | fromYaml -}}
    {{- $decl := $mine.values -}}
    {{- range $key, $v := $final.value -}}
      {{- $_ := set $decl $key $v -}}
    {{- end -}}
    {{- $_ := set $tokens $name $decl -}}
  {{- end -}}
{{- end -}}
{{- range $name := sortAlpha (keys $system) -}}
  {{- if hasKey $tokens $name -}}
    {{- $mine := include "mycrd.splitAnnotations" (dict "decl" (index $tokens $name)) | fromYaml -}}
    {{- $lib := include "mycrd.splitAnnotations" (dict "decl" (index $system $name)) | fromYaml -}}
    {{- if $mine.values -}}
      {{- $_ := set $diag "warnings" (append $diag.warnings (printf "token '%s' is reserved by the library — only annotations were applied" $name)) -}}
    {{- end -}}
    {{- $final := include "mycrd.annotationPolicy" (dict "name" $name "library" $lib.annotations "requested" $mine.annotations "diag" $diag) | fromYaml -}}
    {{- $decl := deepCopy (index $system $name) -}}
    {{- range $key, $v := $final.value -}}
      {{- $_ := set $decl $key $v -}}
    {{- end -}}
    {{- $_ := set $system $name $decl -}}
    {{- $_ := unset $tokens $name -}}
  {{- end -}}
{{- end -}}

{{- dict "tokens" $tokens "system" $system "defaults" $defaults | toYaml -}}
{{- end -}}

{{/*
mycrd.service.registry (internal)

Ensures the my-crd bookkeeping dict `ctx.mycrd` exists.

Interface:
- Params: ctx (the chain ctx, passed directly).
- Returns: nothing (mutates ctx in place).

Implementation notes:
- `ctx.mycrd` is a my-crd-owned key on crdkit's context:
  { added: {<id>: true}, owners: {<pointer>: <id>}, contributors:
  {<mount pointer>: {<id>: true}}, references: {<id>: {<pointer>:
  <descriptor>}} } (descriptor: see mycrd.service.reference). crdkit
  never uses the key `mycrd`.
- Internal bookkeeping only — never emitted.
- Every helper and integration calls this first, so none depends on
  which one runs first.
*/}}
{{- define "mycrd.service.registry" -}}
{{- $ctx := . -}}
{{- if not (hasKey $ctx "mycrd") -}}
  {{- $_ := set $ctx "mycrd" (dict "added" (dict) "owners" (dict) "contributors" (dict) "references" (dict)) -}}
{{- end -}}
{{- end -}}

{{/*
mycrd.service.enabled (internal)

Tells whether a service is enabled, judged by the `enabled` key of its
raw declaration. Shared by every check that skips disabled services.

Interface:
- Params (dict): { "id": <service ID>, "service": <raw service
  declaration under Values.services> }
- Returns: the plain string "true" when the service is enabled, an EMPTY
  string when it is disabled.

Implementation notes:
- Never return "false": a non-empty string is truthy in Go templates.
  Use as `{{ if include "mycrd.service.enabled" (dict ...) }}`.
- Only the YAML boolean `false` disables. An absent key, `true` and any
  non-boolean value (`"false"`, `0`, `no-way`) count as enabled;
  mycrd.serviceTokens reports the non-boolean ERROR, so this define
  stays silent and records nothing.
- `id` is part of the interface for call-site symmetry; the decision
  reads `service` only.
*/}}
{{- define "mycrd.service.enabled" -}}
{{- $off := false -}}
{{- if kindIs "map" .service -}}
  {{- $v := get .service "enabled" -}}
  {{- if and (kindIs "bool" $v) (not $v) -}}
    {{- $off = true -}}
  {{- end -}}
{{- end -}}
{{- if not $off -}}
true
{{- end -}}
{{- end -}}

{{/*
mycrd.service.guard (internal)

Checks that a service was added before one of the service helpers acts
for it.

Interface:
- Params (dict): { "ctx": <chain ctx>, "id": <service ID>, "helper":
  <helper's template name, for the message> }
- Returns: the plain string "true" when the service was added, an EMPTY
  string otherwise (and records an ERROR: `service '<id>' was not added
  — helper '<helper>' ignored`).

Implementation notes:
- Never return "false": a non-empty string is truthy in Go templates.
  Use as `{{ if include "mycrd.service.guard" (dict ...) }}`.
- Mutates ctx.diag only.
*/}}
{{- define "mycrd.service.guard" -}}
{{- $ctx := .ctx -}}
{{- include "mycrd.service.registry" $ctx -}}
{{- if hasKey $ctx.mycrd.added (toString .id) -}}
true
{{- else -}}
  {{- $_ := set $ctx.diag "errors" (append $ctx.diag.errors (printf "service '%s' was not added — helper '%s' ignored" (toString .id) .helper)) -}}
{{- end -}}
{{- end -}}

{{/*
mycrd.service.exportVar (internal)

Writes the model entry of an exported variable and records its owner.

Interface:
- Params (dict): { "ctx": <chain ctx>, "id": <service ID>, "name":
  <token name> }
- Returns: nothing (mutates ctx.model and ctx.mycrd in place).

Implementation notes:
- Writes `spec.services.<id>.environment.<name>: {value: "@<name>@",
  targetContainer: <tc>}` only when the token's CURRENT targetContainer
  is main/side-car/both; any other token is left out of the model.
- `value` holds a `@<name>@` marker, resolved by crdkit.render's single
  substitution pass — this define never resolves tokens itself.
- Reads the RAW declaration's annotation, not a resolved value: it is
  static metadata, never target-escalated.
*/}}
{{- define "mycrd.service.exportVar" -}}
{{- $ctx := .ctx -}}
{{- $decl := index $ctx.tokens .name -}}
{{- $tc := "" -}}
{{- if kindIs "map" $decl -}}
  {{- $tc = get $decl "targetContainer" | default "" -}}
{{- end -}}
{{- if has $tc (list "main" "side-car" "both") -}}
  {{- $segments := (include "mycrd.paths.var" (dict "service" .id "name" .name) | fromYaml).value -}}
  {{- include "crdkit.dictMerge" (concat (list $ctx.model) $segments (list (dict "value" (printf "@%s@" .name) "targetContainer" $tc))) -}}
  {{- $_ := set $ctx.mycrd.owners (include "mycrd.paths.pointer" (dict "segments" $segments)) (toString .id) -}}
{{- end -}}
{{- end -}}

{{/*
mycrd.service.add (internal)

Registers a service: writes its `type` into the model, writes every
exported variable the service declares, and marks it added so the other
service helpers act for it.

Interface:
- Params (dict): { "ctx": <chain ctx>, "id": <service ID> }
- Returns: nothing (mutates ctx.model and ctx.mycrd in place).

Implementation notes:
- Scope is internal, not protected: mycrd.integrations.services calls
  it before each type handler, so a handler always starts with its
  service added and never calls it itself.
- Writes `spec.services.<id>.type` (the `type` under
  `Values.services.<id>`), so every dispatched service appears in the
  output.
- Exported variables: every token annotated `service: <id>` with
  targetContainer main/side-car/both (consumer declarations and library
  tokens exported by this service), via mycrd.service.exportVar, in
  alphabetical name order.
- Idempotent.
*/}}
{{- define "mycrd.service.add" -}}
{{- $ctx := .ctx -}}
{{- $id := toString .id -}}
{{- include "mycrd.service.registry" $ctx -}}
{{- $services := ($ctx.root.Values | toYaml | fromYaml).services | default dict -}}
{{- $type := "" -}}
{{- if kindIs "map" $services -}}
  {{- $svc := get $services $id -}}
  {{- if kindIs "map" $svc -}}
    {{- $type = get $svc "type" | default "" -}}
  {{- end -}}
{{- end -}}
{{- $segments := (include "mycrd.paths.service" (dict "service" $id) | fromYaml).value -}}
{{- include "crdkit.dictMerge" (concat (list $ctx.model) $segments (list (dict "type" $type))) -}}
{{- range $name := sortAlpha (keys $ctx.tokens) -}}
  {{- $decl := index $ctx.tokens $name -}}
  {{- if and (kindIs "map" $decl) (eq (get $decl "service" | default "" | toString) $id) -}}
    {{- include "mycrd.service.exportVar" (dict "ctx" $ctx "id" $id "name" $name) -}}
  {{- end -}}
{{- end -}}
{{- $_ := set $ctx.mycrd.added $id true -}}
{{- end -}}

{{/*
mycrd.service.addVar (protected)

The way a service type handler contributes a variable: registers a
GENERATED value (crdkit.token.underlay) for `name`, annotated with
`service: <id>` (and `targetContainer` when given), and exports it into
the model when the token's final targetContainer is main/side-car/both.

Interface:
- Params (dict): { "ctx": <chain ctx>, "id": <service ID>, "name":
  <token name>, "value": <generated value, may hold "@ref@" markers or
  be a structure>, "targetContainer": <string, optional> }
- Returns: nothing (mutates ctx.tokens, ctx.model, ctx.mycrd and
  ctx.diag in place).

Implementation notes:
- Service must be added (mycrd.service.guard), otherwise an ERROR is
  recorded and nothing happens.
- A token already annotated with a DIFFERENT service is left untouched
  and an ERROR is recorded: a variable has exactly one owning service.
- Generated values have the lowest priority: anything the consumer
  declared for the same token (under the same service's `environment`)
  wins, `default` included. Annotations already on the declaration win
  over the ones passed here, so the exported targetContainer is the
  final one.
- Exporting writes `environment.<name>` and records the service as the
  owner of that variable (mycrd.service.exportVar).
*/}}
{{- define "mycrd.service.addVar" -}}
{{- $ctx := .ctx -}}
{{- if include "mycrd.service.guard" (dict "ctx" $ctx "id" .id "helper" "mycrd.service.addVar") -}}
  {{- $owner := "" -}}
  {{- if hasKey $ctx.tokens .name -}}
    {{- $owner = get (index $ctx.tokens .name) "service" | default "" -}}
  {{- end -}}
  {{- if and $owner (ne (toString $owner) (toString .id)) -}}
    {{- $_ := set $ctx.diag "errors" (append $ctx.diag.errors (printf "service '%s' generates variable '%s', already owned by service '%s' — generated value ignored" .id .name $owner)) -}}
  {{- else -}}
    {{- $annotations := dict "service" .id -}}
    {{- if .targetContainer -}}
      {{- $_ := set $annotations "targetContainer" .targetContainer -}}
    {{- end -}}
    {{- include "crdkit.token.underlay" (list $ctx .name .value $annotations) -}}
    {{- include "mycrd.service.exportVar" (dict "ctx" $ctx "id" .id "name" .name) -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
mycrd.service.addFile (protected)

The way a service type handler contributes a file to a volume mount:
creates the mount when absent and adds the file under its `files`.

Interface:
- Params (dict): { "ctx": <chain ctx>, "id": <service ID>, "mount":
  <mount name>, "source": <mount source, e.g. configMap>, "file": <file
  name>, "content": <file content, may hold "@TOKEN@" markers> }
- Returns: nothing (mutates ctx.model, ctx.mycrd and ctx.diag in place).

Implementation notes:
- Service must be added (mycrd.service.guard), otherwise an ERROR is
  recorded and nothing happens.
- Mounts are shared: several services may add different files to one
  mount, and each becomes a contributor of it.
- A mount that exists with a different `source` records an ERROR and the
  file is not added.
- A file that already exists in the mount records an ERROR naming its
  owner; the first definition is kept.
- `content` is resolved by crdkit.render's single substitution pass.
- Records the file's owner and the mount's contributor in ctx.mycrd.
*/}}
{{- define "mycrd.service.addFile" -}}
{{- $ctx := .ctx -}}
{{- $id := toString .id -}}
{{- if include "mycrd.service.guard" (dict "ctx" $ctx "id" $id "helper" "mycrd.service.addFile") -}}
  {{- $mountSegments := (include "mycrd.paths.mount" (dict "mount" .mount) | fromYaml).value -}}
  {{- $fileSegments := (include "mycrd.paths.file" (dict "mount" .mount "file" .file) | fromYaml).value -}}
  {{- $mountPointer := include "mycrd.paths.pointer" (dict "segments" $mountSegments) -}}
  {{- $filePointer := include "mycrd.paths.pointer" (dict "segments" $fileSegments) -}}
  {{- $add := true -}}
  {{- if include "crdkit.model.hasPath" (concat (list $ctx.model) $mountSegments) -}}
    {{- $node := $ctx.model -}}
    {{- range $segment := $mountSegments -}}
      {{- $node = index $node $segment -}}
    {{- end -}}
    {{- $have := get $node "source" -}}
    {{- if ne (toString $have) (toString .source) -}}
      {{- $add = false -}}
      {{- $_ := set $ctx.diag "errors" (append $ctx.diag.errors (printf "mount '%s' has source '%s', service '%s' asked for '%s' — file '%s' not added" .mount $have $id .source .file)) -}}
    {{- else if include "crdkit.model.hasPath" (concat (list $ctx.model) $fileSegments) -}}
      {{- $add = false -}}
      {{- $_ := set $ctx.diag "errors" (append $ctx.diag.errors (printf "file '%s' in mount '%s' is already defined by service '%s'" .file .mount (get $ctx.mycrd.owners $filePointer))) -}}
    {{- end -}}
  {{- else -}}
    {{- include "crdkit.dictMerge" (concat (list $ctx.model) $mountSegments (list (dict "source" .source))) -}}
  {{- end -}}
  {{- if $add -}}
    {{- include "crdkit.dictMerge" (concat (list $ctx.model) $mountSegments (list "files") (list (dict .file .content))) -}}
    {{- $_ := set $ctx.mycrd.owners $filePointer $id -}}
    {{- if not (hasKey $ctx.mycrd.contributors $mountPointer) -}}
      {{- $_ := set $ctx.mycrd.contributors $mountPointer (dict) -}}
    {{- end -}}
    {{- $_ := set (index $ctx.mycrd.contributors $mountPointer) $id true -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
mycrd.service.reference (internal)

Records one reference of a service; shared by the four
mycrd.service.reference* helpers.

Interface:
- Params (dict): { "ctx": <chain ctx>, "id": <service ID>, "helper":
  <calling helper's template name, for the guard message>, "segments":
  <path segments of the referenced node>, "var": <dict { "service":
  <ID>, "name": <variable name> }, optional — set for a variable> }
- Returns: nothing (mutates ctx.mycrd in place).

Implementation notes:
- Service must be added (mycrd.service.guard), otherwise an ERROR is
  recorded and nothing is recorded.
- Stored as `ctx.mycrd.references.<id>.<pointer>: {segments, var?}`: the
  pointer key makes repeated references collapse, the descriptor lets
  mycrd.integrations.references check the node without decoding the
  pointer.
- Only records: the target may be created by a handler that runs later,
  so validation is mycrd.integrations.references' job.
*/}}
{{- define "mycrd.service.reference" -}}
{{- $ctx := .ctx -}}
{{- $id := toString .id -}}
{{- if include "mycrd.service.guard" (dict "ctx" $ctx "id" $id "helper" .helper) -}}
  {{- if not (hasKey $ctx.mycrd.references $id) -}}
    {{- $_ := set $ctx.mycrd.references $id (dict) -}}
  {{- end -}}
  {{- $descriptor := dict "segments" .segments -}}
  {{- if .var -}}
    {{- $_ := set $descriptor "var" .var -}}
  {{- end -}}
  {{- $_ := set (index $ctx.mycrd.references $id) (include "mycrd.paths.pointer" (dict "segments" .segments)) $descriptor -}}
{{- end -}}
{{- end -}}

{{/*
mycrd.service.referenceService (protected)

A service type handler's way to record that its service references
another service as a whole.

Interface:
- Params (dict): { "ctx": <chain ctx>, "id": <calling service ID>,
  "service": <referenced service ID> }
- Returns: nothing (mutates ctx.mycrd in place).

Implementation notes:
- See mycrd.service.reference; records the pointer of
  mycrd.paths.service.
*/}}
{{- define "mycrd.service.referenceService" -}}
{{- include "mycrd.service.reference" (dict
      "ctx" .ctx
      "id" .id
      "helper" "mycrd.service.referenceService"
      "segments" (include "mycrd.paths.service" (dict "service" .service) | fromYaml).value) -}}
{{- end -}}

{{/*
mycrd.service.referenceVar (protected)

A service type handler's way to record that its service references an
environment variable of a service.

Interface:
- Params (dict): { "ctx": <chain ctx>, "id": <calling service ID>,
  "service": <ID of the service exporting the variable>, "name":
  <variable name> }
- Returns: nothing (mutates ctx.mycrd in place).

Implementation notes:
- See mycrd.service.reference; records the pointer of mycrd.paths.var.
*/}}
{{- define "mycrd.service.referenceVar" -}}
{{- include "mycrd.service.reference" (dict
      "ctx" .ctx
      "id" .id
      "helper" "mycrd.service.referenceVar"
      "segments" (include "mycrd.paths.var" (dict "service" .service "name" .name) | fromYaml).value
      "var" (dict "service" (toString .service) "name" (toString .name))) -}}
{{- end -}}

{{/*
mycrd.service.referenceMount (protected)

A service type handler's way to record that its service references a
volume mount as a whole.

Interface:
- Params (dict): { "ctx": <chain ctx>, "id": <calling service ID>,
  "mount": <mount name> }
- Returns: nothing (mutates ctx.mycrd in place).

Implementation notes:
- See mycrd.service.reference; records the pointer of
  mycrd.paths.mount.
*/}}
{{- define "mycrd.service.referenceMount" -}}
{{- include "mycrd.service.reference" (dict
      "ctx" .ctx
      "id" .id
      "helper" "mycrd.service.referenceMount"
      "segments" (include "mycrd.paths.mount" (dict "mount" .mount) | fromYaml).value) -}}
{{- end -}}

{{/*
mycrd.service.referenceFile (protected)

A service type handler's way to record that its service references a
file inside a volume mount.

Interface:
- Params (dict): { "ctx": <chain ctx>, "id": <calling service ID>,
  "mount": <mount name>, "file": <file name> }
- Returns: nothing (mutates ctx.mycrd in place).

Implementation notes:
- See mycrd.service.reference; records the pointer of mycrd.paths.file.
*/}}
{{- define "mycrd.service.referenceFile" -}}
{{- include "mycrd.service.reference" (dict
      "ctx" .ctx
      "id" .id
      "helper" "mycrd.service.referenceFile"
      "segments" (include "mycrd.paths.file" (dict "mount" .mount "file" .file) | fromYaml).value) -}}
{{- end -}}
