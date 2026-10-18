# my-crd values

| Key | Kind | Per target | Default | Required | Description |
| --- | --- | --- | --- | --- | --- |
| `application` | map |  |  |  | The application the object describes. |
| `application.services` | map |  |  |  | Services by ID (upper case by convention). |
| `application.services.<key>` | map, by `type`: environment, greeter, leader |  |  |  | One service; its keys depend on `type`. |
| `metadata` | map |  |  |  | Metadata of the rendered object. |
| `metadata.labels` | map |  |  |  | Labels copied onto the rendered object; standard labels win on a collision. |
| `metadata.labels.<key>` | scalar (string) | markers |  |  | Label value; may hold `@NAME@` markers. |
| `renderMode` | scalar | no |  |  | `validate` prints the render with its diagnostics; `deploy` (default) aborts on errors. |
| `target` | scalar (string) | no |  |  | Render target: `<env>` or `<env>-<seq>` (e.g. `prod-01`). Selects every per-target value. |
| `<key>` | any |  |  |  | The consumer chart's own values; not read by my-crd. |

## `application.services.<key>` with `type: environment`

| Key | Kind | Per target | Default | Required | Description |
| --- | --- | --- | --- | --- | --- |
| `application.services.<key>.enabled` | scalar (bool) | no | `true` |  | `false` removes the service from the output. |
| `application.services.<key>.environment` | map |  |  |  | Variables owned by the service, by name (`<SID>_`-prefixed by convention). |
| `application.services.<key>.environment.<key>` | scalar | yes |  |  | A variable: a scalar or a token declaration (target keys, `default`, `match`, annotation `targetContainer`). |
| `application.services.<key>.type` | scalar (string) | no |  |  | Service type; selects the handler and the keys below. |

## `application.services.<key>` with `type: greeter`

| Key | Kind | Per target | Default | Required | Description |
| --- | --- | --- | --- | --- | --- |
| `application.services.<key>.enabled` | scalar (bool) | no | `true` |  | `false` removes the service from the output. |
| `application.services.<key>.environment` | map |  |  |  | Variables owned by the service, by name (`<SID>_`-prefixed by convention). |
| `application.services.<key>.environment.<key>` | scalar | yes |  |  | A variable: a scalar or a token declaration (target keys, `default`, `match`, annotation `targetContainer`). |
| `application.services.<key>.greeting` | scalar (string) | yes |  |  | Content of the file `message`; absent → nothing generated. |
| `application.services.<key>.type` | scalar (string) | no |  |  | Service type; selects the handler and the keys below. |

## `application.services.<key>` with `type: leader`

| Key | Kind | Per target | Default | Required | Description |
| --- | --- | --- | --- | --- | --- |
| `application.services.<key>.enabled` | scalar (bool) | no | `true` |  | `false` removes the service from the output. |
| `application.services.<key>.environment` | map |  |  |  | Variables owned by the service, by name (`<SID>_`-prefixed by convention). |
| `application.services.<key>.environment.<key>` | scalar | yes |  |  | A variable: a scalar or a token declaration (target keys, `default`, `match`, annotation `targetContainer`). |
| `application.services.<key>.greeter` | scalar (string) | no |  |  | ID of the greeter service to reference; absent → nothing generated. |
| `application.services.<key>.type` | scalar (string) | no |  |  | Service type; selects the handler and the keys below. |
