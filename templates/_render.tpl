{{/*
mycrd.render (public)

The only entry point consumers call: `{{ include "mycrd.render" . }}`,
always with THEIR root context (never nested under .Values.myCrd.*).

Interface:
- Params: none (uses `.` directly).
- Returns: the rendered CR as YAML text (see crdkit.render), followed
  by its diagnostics as `# ERROR:`/`# WARNING:` comments. Deploy
  mode with at least one error fails instead, with the control data
  (mycrd.controlData).

Implementation notes:
- Thin wrapper supplying crdkit.render everything it can't know itself:
  system/default tokens, the integration chain (mycrd.integrations.*,
  preamble always first), this library's own target-escalation
  taxonomy (mycrd.parentTarget, templates/_target.tpl), the annotation
  names it owns (service, targetContainer) and a fresh diagnostics seed.
- The mode comes from the values key `renderMode` (mycrd.renderMode):
  `validate` always prints the output (CI greps it for `# ERROR:`);
  `deploy` (default) aborts on errors, warnings never abort. This is
  the one deliberate `fail` in a render: crdkit and every helper only
  collect diagnostics, and this final decision turns them into an abort.
- The `diag` dict is created here, first recorded into by the
  structural schema pass, mycrd.serviceFields and mycrd.serviceTokens
  (pre-render), then
  seeded into crdkit.render, which appends to it and emits everything.
- Schema: the values are validated against mycrd.schema before the
  chain (crdkit.schema.validate); the schema and the normalized input
  are seeded into `ctx.mycrd` (`schema`, `input`) through crdkit.render's
  `state`. mycrd.integrations.schema, last in the chain, runs the value
  pass.
- Field references: mycrd.serviceFields (templates/_fields.tpl) runs
  between the structural pass and mycrd.serviceTokens — the input it
  returns (relative markers rewritten) is what serviceTokens reads and
  `ctx.mycrd.input` holds; its field tokens (`<ID>.<path>`) and the
  services' copies of the library templates (`<ID>..<T>`) join the
  consumer tokens.
- tokens/system/defaults come from mycrd.serviceTokens
  (templates/_services.tpl).
- apiVersion/kind aren't passed here — mycrd.integrations.preamble sets
  them on ctx.model, same mechanism as labels.
*/}}
{{- define "mycrd.render" -}}
{{- $diag := dict "errors" (list) "warnings" (list) -}}
{{- $mode := include "mycrd.renderMode" (dict "context" . "diag" $diag) -}}
{{- $schema := include "mycrd.schema" . | fromYaml -}}
{{- $input := (include "crdkit.schema.validate" (dict "schema" $schema "values" (.Values | toYaml | fromYaml) "diag" $diag) | fromYaml).value -}}
{{- $system := include "mycrd.systemTokens" . | fromYaml -}}
{{- $defaults := include "mycrd.defaultTokens" . | fromYaml -}}
{{- $fields := include "mycrd.serviceFields" (dict "input" $input "schema" $schema "system" $system "defaults" $defaults "diag" $diag) | fromYaml -}}
{{- $input = $fields.input -}}
{{- $prepared := include "mycrd.serviceTokens" (dict
      "input" $input
      "diag" $diag
      "system" $system
      "defaults" $defaults
    ) | fromYaml -}}
{{- $output := include "crdkit.render" (dict
      "context" .
      "tokens" (merge (dict) ($prepared.tokens | default dict) ($fields.tokens | default dict))
      "target" .Values.target
      "system" $prepared.system
      "defaults" $prepared.defaults
      "parentTargetTemplate" "mycrd.parentTarget"
      "annotations" (include "mycrd.annotationNames" . | fromYaml).value
      "diag" $diag
      "state" (dict "mycrd" (dict "schema" $schema "input" $input))
      "chain" (list "mycrd.integrations.preamble" "mycrd.integrations.services" "mycrd.integrations.references" "mycrd.integrations.schema")
    ) -}}
{{- if and (eq $mode "deploy") $diag.errors -}}
  {{- fail (include "mycrd.controlData" (dict "context" . "diag" $diag)) -}}
{{- end -}}
{{- $output -}}
{{- end -}}

{{/*
mycrd.controlData (internal)

Builds the text of the abort message mycrd.render fails with in deploy
mode when errors exist: a summary, the render's context, every
diagnostic and a hint.

Interface:
- Params (dict): { "context": <root $>, "diag": <diag dict with
  "errors"/"warnings" lists> }
- Returns: text of the form
  ```
  my-crd: render aborted — <E> error(s), <W> warning(s)
  release: <name>   namespace: <ns>   target: <target>   library: my-crd <version>
  # ERROR: <message>      (one line per error)
  # WARNING: <message>    (one line per warning)
  re-run with renderMode: validate to see the rendered object
  ```

Implementation notes:
- Diagnostics are de-duplicated (`uniq`, order-preserving) and use the
  `# ERROR:`/`# WARNING:` prefixes crdkit emits; the counts are of the
  de-duplicated lists, matching the lines shown.
- Library version comes from crdkit.dependencyVersion (`unknown` when
  the consumer does not declare my-crd as a dependency).
*/}}
{{- define "mycrd.controlData" -}}
{{- $root := .context -}}
{{- $errors := uniq .diag.errors -}}
{{- $warnings := uniq .diag.warnings -}}
{{- $version := include "crdkit.dependencyVersion" (dict "name" "my-crd" "context" $root) -}}
my-crd: render aborted — {{ len $errors }} error(s), {{ len $warnings }} warning(s)
release: {{ $root.Release.Name }}   namespace: {{ $root.Release.Namespace }}   target: {{ $root.Values.target }}   library: my-crd {{ $version }}
{{- range $errors }}
# ERROR: {{ . }}
{{- end }}
{{- range $warnings }}
# WARNING: {{ . }}
{{- end }}
re-run with renderMode: validate to see the rendered object
{{- end -}}

{{/*
mycrd.renderMode (internal)

Resolves the consumer's `renderMode` values key to the mode
mycrd.render runs in: `validate` or `deploy`. An absent key means
`deploy`; any other value records an ERROR and also means `deploy`, so
the typo aborts a deployment instead of passing silently.

Interface:
- Params (dict): { "context": <root $>, "diag": <diag dict, mutated> }
- Returns: `validate` or `deploy` (bare string).

Implementation notes:
- Reads `.Values` through `toYaml | fromYaml` (plain maps).
- Called before any other diagnostic is recorded, so the ERROR is the
  first one listed.
*/}}
{{- define "mycrd.renderMode" -}}
{{- $values := .context.Values | toYaml | fromYaml -}}
{{- $mode := "deploy" -}}
{{- if hasKey $values "renderMode" -}}
  {{- if and (kindIs "string" $values.renderMode) (has $values.renderMode (list "validate" "deploy")) -}}
    {{- $mode = $values.renderMode -}}
  {{- else -}}
    {{- $_ := set .diag "errors" (append .diag.errors "values key 'renderMode' must be 'validate' or 'deploy' — rendering in deploy mode") -}}
  {{- end -}}
{{- end -}}
{{- $mode -}}
{{- end -}}
