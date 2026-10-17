{{/*
Name: mycrd.integrations.preamble

Scope: internal (chain entry, not called directly by consumers)

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
  wins): consumer's own Values.metadata.labels, then
  crdkit.standardLabels, then this library's own library-version label
  — later chain integrations can still override any key afterward.
- Reading consumer labels needs `.root.Values | toYaml | fromYaml`
  first: Sprig's `dig` requires plain maps, and Helm's `.Values` is a
  distinct `chartutil.Values` type that fails `dig`'s type assertion.
- spec is copied from Values.spec verbatim, markers unresolved — same
  later substitution pass handles it.
- Mutation-only: every include here is empty-returning
  (crdkit.dictMerge) — never mix literal text output into a
  mutation-phase define.
*/}}
{{- define "mycrd.integrations.preamble" -}}
{{- include "crdkit.dictMerge" (list .model (dict "apiVersion" "@API_GROUP@/v1" "kind" "SomeCR")) -}}
{{- include "crdkit.dictMerge" (list .model "metadata" (dict "name" .root.Release.Name)) -}}
{{- include "crdkit.dictMerge" (list .model "metadata" "labels" (dig "metadata" "labels" (dict) (.root.Values | toYaml | fromYaml))) -}}
{{- include "crdkit.dictMerge" (list .model "metadata" "labels" (include "crdkit.standardLabels" (dict "context" .root) | fromYaml)) -}}
{{- include "crdkit.dictMerge" (list .model "metadata" "labels" (dict "platform.company.io/library-version" "@LIBRARY_VERSION@")) -}}
{{- include "crdkit.dictMerge" (list .model "spec" (.root.Values.spec | default dict)) -}}
{{- end -}}
