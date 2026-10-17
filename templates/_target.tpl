{{/*
Scope: internal

Recognizes this library's "<env>-<seq>" target convention (seq = exactly
two digits, e.g. "prod-01").

Interface:
- Params: bare string (the target to test).
- Returns: YAML `{ "matched": <bool>, "value": <string> }`.

Implementation notes:
- The one place this regex lives — shared by mycrd.deriveEnv and
  mycrd.parentTarget's first hop, via crdkit.matchRules.
*/}}
{{- define "mycrd.matchSequence" -}}
{{- include "crdkit.matchRules" (dict "subject" . "rules" (list (dict "(.+)-[0-9]{2}" "$1"))) -}}
{{- end -}}

{{/*
Scope: internal

Derives this library's "@ENV@"-equivalent value from "target". Used
once, in mycrd.systemTokens, for the locked ENV token.

Interface:
- Params: bare string (the target).
- Returns: the derived env string.

Implementation notes:
- NOT equivalent to calling mycrd.parentTarget once: for a plain,
  unsequenced target (e.g. "prod"), escalation would jump straight to
  the "PROD" family, the wrong answer for "what env is this" — instead
  this returns the target verbatim when it isn't the sequenced form.
*/}}
{{- define "mycrd.deriveEnv" -}}
{{- $target := . -}}
{{- $m := include "mycrd.matchSequence" $target | fromYaml -}}
{{- if $m.matched -}}
  {{- $m.value -}}
{{- else -}}
  {{- $target -}}
{{- end -}}
{{- end -}}

{{/*
Scope: public (passed to crdkit.render as parentTargetTemplate)

This library's target-escalation taxonomy: crdkit walks it repeatedly
from an exact target (e.g. "qam1-01") up to wherever a token's value is
declared, caching every rung visited.

Interface:
- Params (dict): { "target": <string, current rung>, "context": <root
  $, unused — this taxonomy needs no external data> }
- Returns: the next rung up, or nothing if there is none.

Implementation notes:
- Two rules, in order: (1) a "<env>-<seq>" target (mycrd.matchSequence)
  escalates to the stripped env (e.g. "qam1-01" -> "qam1"); (2)
  otherwise a literal lookup table: env -> family (qa/qam1/qap1 collapse
  to "QA") -> "NONPROD"/"PROD" tier -> "default" as the final catch-all.
- "default" has no entry of its own — mapping it to itself would make
  crdkit's walk falsely detect a cycle.
- Never let a bare, possibly-missing `index` be the last thing emitted
  — guard with `hasKey` first (a missing key otherwise renders as the
  literal text "<no value>" once it crosses an `include` boundary).
*/}}
{{- define "mycrd.parentTarget" -}}
{{- $target := .target -}}
{{- $seq := include "mycrd.matchSequence" $target | fromYaml -}}
{{- if $seq.matched -}}
  {{- $seq.value -}}
{{- else -}}
  {{- $chain := dict
        "dev" "DEV"
        "test" "TEST"
        "qa" "QA"
        "qam1" "QA"
        "qap1" "QA"
        "prod" "PROD"
        "DEV" "NONPROD"
        "TEST" "NONPROD"
        "QA" "NONPROD"
        "NONPROD" "default"
        "PROD" "default"
  -}}
  {{- if hasKey $chain $target -}}
    {{- index $chain $target -}}
  {{- end -}}
{{- end -}}
{{- end -}}
