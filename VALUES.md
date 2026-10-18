# my-crd values

| Key | Type | Per target | Default | Required | Description |
| --- | --- | --- | --- | --- | --- |
| `application` | map |  |  |  | The application the object describes. |
| `application.services` | map, keys match `^[A-Z0-9_]+$` |  |  |  | Services by ID. |
| `application.services.<key>` | map, by `type`: environment, greeter, leader |  |  |  | One service; its keys depend on `type`. |
| `metadata` | map |  |  |  | Metadata of the rendered object. |
| `metadata.labels` | map |  |  |  | Labels copied onto the rendered object; standard labels win on a collision. |
| `metadata.labels.<key>` | string | markers |  |  | Label value; may hold `@NAME@` markers. |
| `renderMode` | scalar | no |  |  | `validate` prints the render with its diagnostics; `deploy` (default) aborts on errors. |
| `target` | string | no |  |  | Render target: `<env>` or `<env>-<seq>` (e.g. `prod-01`). Selects every per-target value. |
| `<key>` | any |  |  |  | The consumer chart's own values; not read by my-crd. |

## `application.services.<key>` with `type: environment`

| Key | Type | Per target | Default | Required | Description |
| --- | --- | --- | --- | --- | --- |
| `application.services.<key>.enabled` | bool | no | `true` |  | `false` removes the service from the output. |
| `application.services.<key>.environment` | map, keys match `^[A-Z][A-Z0-9_]*$` |  |  |  | Variables owned by the service, by name (`<ID>_`-prefixed by convention). |
| `application.services.<key>.environment.<key>` | scalar | yes |  |  | A variable: a scalar or a token declaration (target keys, `default`, `match`, annotation `targetContainer`). |
| `application.services.<key>.type` | string | no |  |  | Service type; selects the handler and the keys below. |

## `application.services.<key>` with `type: greeter`

| Key | Type | Per target | Default | Required | Description |
| --- | --- | --- | --- | --- | --- |
| `application.services.<key>.enabled` | bool | no | `true` |  | `false` removes the service from the output. |
| `application.services.<key>.environment` | map, keys match `^[A-Z][A-Z0-9_]*$` |  |  |  | Variables owned by the service, by name (`<ID>_`-prefixed by convention). |
| `application.services.<key>.environment.<key>` | scalar | yes |  |  | A variable: a scalar or a token declaration (target keys, `default`, `match`, annotation `targetContainer`). |
| `application.services.<key>.greeting` | string | yes |  |  | Content of the file `message`; absent → nothing generated. |
| `application.services.<key>.type` | string | no |  |  | Service type; selects the handler and the keys below. |

## `application.services.<key>` with `type: leader`

| Key | Type | Per target | Default | Required | Description |
| --- | --- | --- | --- | --- | --- |
| `application.services.<key>.enabled` | bool | no | `true` |  | `false` removes the service from the output. |
| `application.services.<key>.environment` | map, keys match `^[A-Z][A-Z0-9_]*$` |  |  |  | Variables owned by the service, by name (`<ID>_`-prefixed by convention). |
| `application.services.<key>.environment.<key>` | scalar | yes |  |  | A variable: a scalar or a token declaration (target keys, `default`, `match`, annotation `targetContainer`). |
| `application.services.<key>.greeter` | string | no |  |  | ID of the greeter service to reference; absent → nothing generated. |
| `application.services.<key>.type` | string | no |  |  | Service type; selects the handler and the keys below. |
