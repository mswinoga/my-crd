{{/*
This library's own target-escalation taxonomy — crdkit itself has NO
concept of "env"/"family"/"tier" anymore (see crdkit's CLAUDE.md), so
this is where that org-specific knowledge now lives: dev/test/qa
(qam1/qap1 sequenced variants included)/prod, each escalating to an
uppercase family, the nonprod families further escalating to a shared
"NONPROD" tier; "PROD" and "NONPROD" have no further escalation (the
chain simply has no entry for them, so crdkit's walk stops there).

"mycrd.matchSequence" recognizes this library's "<env>-<seq>" target
convention (seq = exactly two digits, e.g. "prod-01") — the one piece
of pattern-matching shared by both "mycrd.deriveEnv" (below) and
"mycrd.parentTarget"'s own first hop, so the regex itself only lives in
one place. Reuses crdkit.matchRules rather than hand-rolling regex
handling — crdkit dropped its own hardcoded version of this exact
pattern (it used to own "env" derivation directly), but kept
crdkit.matchRules as a reusable primitive specifically so a library
like this one doesn't have to reinvent it.

Expects: a bare string (the target to test). Returns YAML: { "matched": <bool>, "value": <string> }.
*/}}
{{- define "mycrd.matchSequence" -}}
{{- include "crdkit.matchRules" (dict "subject" . "rules" (list (dict "(.+)-[0-9]{2}" "$1"))) -}}
{{- end -}}

{{/*
Derives this library's own "@ENV@"-equivalent value from "target" — NOT
part of crdkit anymore (see crdkit's CLAUDE.md: `crdkit.deriveTargetEnv`
and the built-in "@ENV@" token were both removed; any library that
wants this convenience now implements it itself, this is that
implementation). Used once, in "mycrd.systemTokens", to compute the
locked "ENV" token's value — deliberately NOT the same thing as calling
"mycrd.parentTarget" once: for the common case (a plain, unsequenced
target, e.g. "prod"), the escalation chain's first hop would jump
straight past env to "PROD" (the family), which is the wrong answer for
"what env is this" — this returns the target itself, verbatim, when it
doesn't match the sequenced form, rather than escalating further.

Expects: a bare string (the target). Returns: the derived env string.
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
This library's "parentTarget" hook, passed to crdkit.render (see
mycrd.render) — given any rung, returns the next one up, or nothing if
there is none. crdkit calls this repeatedly to walk from an exact
target (e.g. "qam1-01") up to wherever a token's value is actually
declared (e.g. under a "NONPROD" key), caching every rung visited along
the way. See crdkit's CLAUDE.md/README "Target escalation" section for
the full mechanics this plugs into.

Two rules, applied in order: (1) if "target" matches this library's
"<env>-<seq>" convention (mycrd.matchSequence), the next rung is the
stripped env — e.g. "qam1-01" -> "qam1". (2) otherwise, a plain literal
lookup table: env -> family (qa/qam1/qap1 all collapse to "QA"), family
-> "NONPROD"/"PROD" tier, tier -> "default" as the final, universal
catch-all — a deliberate choice by THIS library to preserve the "a
token declaring only 'default' resolves for any recognized env"
convenience the old crdkit-hardcoded ladder always had, now that
crdkit itself has no opinion on whether "default" means anything.
"default" itself is NOT a key in this table — there's nowhere further
for it to escalate to, so the chain simply stops there (an entry
mapping any rung to itself would make crdkit's walk falsely detect a
cycle — a rung "escalating" to itself looks identical to a real loop).

GOTCHA (see crdkit's CLAUDE.md for the full story): never let a bare,
possibly-missing `index` be the last thing this template emits — always
guard with `hasKey` first, exactly as done below. crdkit's own test
harness got bitten by this exact Go text/template behavior once (a
missing map key renders as the literal text "<no value>", not an empty
string, once it crosses an `include` boundary).

Expects a dict: { "target": <string, the current rung>, "context": <root $> } — "context" unused here, this taxonomy needs no external data.
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
