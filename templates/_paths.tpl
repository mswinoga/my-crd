{{/*
mycrd.paths.service (internal)

Location of a service's node in the rendered model.

Interface:
- Params (dict): { "service": <service ID> }
- Returns YAML: { "value": [spec, application, services, <service>] }

Implementation notes:
- Every mycrd.paths.* define is the only place that knows where a node
  lives in the model. Scope is internal: handlers never call them — they
  use the protected mycrd.service.* helpers, which build locations here,
  so a node can move (e.g. mounts under services) without touching any
  handler.
- Wrapped in `value:` — Helm's `fromYaml` cannot decode a bare list.
*/}}
{{- define "mycrd.paths.service" -}}
value:
- spec
- application
- services
- {{ .service | quote }}
{{- end -}}

{{/*
mycrd.paths.var (internal)

Location of a service's environment variable in the rendered model.

Interface:
- Params (dict): { "service": <service ID>, "name": <variable name> }
- Returns YAML: { "value": [spec, application, services, <service>, environment, <name>] }
*/}}
{{- define "mycrd.paths.var" -}}
value:
- spec
- application
- services
- {{ .service | quote }}
- environment
- {{ .name | quote }}
{{- end -}}

{{/*
mycrd.paths.mount (internal)

Location of a volume mount in the rendered model.

Interface:
- Params (dict): { "mount": <mount name> }
- Returns YAML: { "value": [spec, application, volumeMounts, <mount>] }
*/}}
{{- define "mycrd.paths.mount" -}}
value:
- spec
- application
- volumeMounts
- {{ .mount | quote }}
{{- end -}}

{{/*
mycrd.paths.file (internal)

Location of a file inside a volume mount in the rendered model.

Interface:
- Params (dict): { "mount": <mount name>, "file": <file name> }
- Returns YAML: { "value": [spec, application, volumeMounts, <mount>, files, <file>] }

Implementation notes:
- A file name may contain dots (`app.conf`); each segment stays one
  key.
*/}}
{{- define "mycrd.paths.file" -}}
value:
- spec
- application
- volumeMounts
- {{ .mount | quote }}
- files
- {{ .file | quote }}
{{- end -}}

{{/*
mycrd.paths.pointer (internal)

Encodes path segments as an RFC 6901 JSON Pointer from the CR root.

Interface:
- Params (dict): { "segments": <list of segments, as returned in
  `value` by the other mycrd.paths.* defines> }
- Returns: plain string — "/" followed by the segments joined by "/".

Implementation notes:
- Each segment is escaped `~` -> `~0` first, then `/` -> `~1`; the
  order matters, the other way round would re-escape the `~` of `~1`.
- Dots and dashes are left untouched.
*/}}
{{- define "mycrd.paths.pointer" -}}
{{- $parts := list -}}
{{- range $segment := .segments -}}
  {{- $parts = append $parts (replace "/" "~1" (replace "~" "~0" (toString $segment))) -}}
{{- end -}}
{{- printf "/%s" (join "/" $parts) -}}
{{- end -}}
