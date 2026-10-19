{{/*
mycrd.integrations.preamble (callback)

Invoked by crdkit's integration chain.
Always FIRST in mycrd.render's chain — gives the rendered CR its shape:
apiVersion/kind, metadata.name, metadata.labels, spec.

Interface:
- Params: ctx (root/diag/model/tokens/target — see crdkit.render).
- Returns: nothing (mutates ctx.model in place).

Implementation notes:
- apiVersion/kind set via crdkit.dictMerge with an empty path (the
  zero-path-key case — see crdkit's _model.tpl). apiVersion embeds the
  locked API_GROUP token as a literal "@API_GROUP@" marker, resolved
  later in crdkit.render's single substitution pass — same mechanism a
  consumer's own values use.
- metadata.labels precedence (dictMerge is mergeOverwrite, later call
  wins): consumer's own metadata.labels, then
  crdkit.standardLabels, then this library's own library-version label
  — later chain integrations can still override any key afterward.
- Consumer labels come from the normalized input (`ctx.mycrd.input`,
  seeded by mycrd.render): a label the structural schema pass rejected
  is not copied. Each label value resolves per target (a marker or a
  token declaration) through crdkit.schema.node + crdkit.schema.value,
  exactly like mycrd.service.value; a marker to a token that does not
  exist yet stays and is resolved by the final substitution pass.
- spec starts empty: input is never copied verbatim — every node under
  it is built by an integration from the input DSL (never read
  `Values.spec` here).
- Mutation-only: every include here is empty-returning
  (crdkit.dictMerge) — never mix literal text output into a
  mutation-phase define.
*/}}
{{- define "mycrd.integrations.preamble" -}}
{{- $ctx := . -}}
{{- $labels := dict -}}
{{- range $key, $def := (dig "metadata" "labels" (dict) (dig "mycrd" "input" (dict) $ctx | default dict)) -}}
  {{- $keys := list "metadata" "labels" $key -}}
  {{- $node := (include "crdkit.schema.node" (dict "schema" $ctx.mycrd.schema "values" $ctx.mycrd.input "keys" $keys) | fromYaml).value -}}
  {{- $value := (include "crdkit.schema.value" (dict
        "ctx" $ctx
        "node" $node
        "def" $def
        "path" (include "crdkit.schema.path" (dict "keys" $keys))
        "target" $ctx.target
        "seen" $ctx.mycrd.validated) | fromYaml).value -}}
  {{- $_ := set $labels $key $value -}}
{{- end -}}
{{- include "crdkit.dictMerge" (list .model (dict "apiVersion" "@API_GROUP@/v1" "kind" "SomeCR")) -}}
{{- include "crdkit.dictMerge" (list .model "metadata" (dict "name" .root.Release.Name)) -}}
{{- include "crdkit.dictMerge" (list .model "metadata" "labels" $labels) -}}
{{- include "crdkit.dictMerge" (list .model "metadata" "labels" (include "crdkit.standardLabels" (dict "context" .root) | fromYaml)) -}}
{{- include "crdkit.dictMerge" (list .model "metadata" "labels" (dict "platform.company.io/library-version" "@LIBRARY_VERSION@")) -}}
{{- include "crdkit.dictMerge" (list .model "spec" (dict)) -}}
{{- end -}}
