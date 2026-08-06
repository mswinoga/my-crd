{{/*
Tokens that are reserved by this library and cannot be overridden by
consumers. If a consumer's tokens: map defines one of these keys, their
value is discarded — this dict is passed into crdkit.render as "system",
merged in last, unconditionally, and a WARNING diagnostic is recorded
for the collision by crdkit.mergeTokens.internal. This protection is
NOT re-asserted again after the integration chain runs — crdkit no
longer defends locked tokens against the chain itself, only against a
consumer's own tokens: map (the chain is trusted, first-party library
code, not the untrusted boundary; see crdkit's CLAUDE.md).

"ENV" replaces the "@ENV@" built-in token crdkit itself used to provide
before removing all env/family/tier knowledge from itself (see crdkit's
CLAUDE.md) — this library still wants the convenience, so it computes
its own now, via "mycrd.deriveEnv" (see templates/_target.tpl).
Quoted deliberately, even though it's rarely empty in practice: an
unquoted possibly-empty scalar here would render as YAML `null`, not
`""`, which breaks crdkit.substituteTokens' `replace` call downstream —
see crdkit's CLAUDE.md for the fuller story of this exact gotcha.

Called with the CONSUMER's own root context directly (not a "ctx"
dict — library charts don't get one of their own, see
crdkit.dependencyVersion's doc comment), so plain `.Values.target`
here, not `.root.Values.target` (`.root` doesn't exist at this call
site — an unrelated, broken, uncommitted `PLATFORM_NAME` line using
that wrong path was already sitting in this file when this ENV work
started; removed rather than fixed, since nothing referenced it and
its origin/intent wasn't clear).
*/}}
{{- define "mycrd.systemTokens" -}}
LIBRARY_VERSION: {{ include "crdkit.dependencyVersion" (dict "name" "my-crd" "context" .) }}
ENV: {{ include "mycrd.deriveEnv" .Values.target | quote }}
API_GROUP: "platform.company.io"
{{- end -}}
