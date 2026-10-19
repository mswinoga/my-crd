# my-crd values

[HTML reference](VALUES.html)

**Editor support** — first line of a values file:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/mswinoga/my-crd/v0.1.0/input.schema.json
```

```yaml
target:  # string
renderMode:  # scalar
metadata:  # map
  labels:  # map
    <key>:  # string
application:  # map
  services:  # map
    <ID>:  # map, by type
      # type: environment
      # type:  # string
      # enabled:  # bool
      # environment:  # map
      #   <NAME>:  # scalar, per target
      # type: greeter
      # type:  # string
      # enabled:  # bool
      # environment:  # map
      #   <NAME>:  # scalar, per target
      # greeting:  # string, per target
      # type: leader
      # type:  # string
      # enabled:  # bool
      # environment:  # map
      #   <NAME>:  # scalar, per target
      # greeter:  # string
<key>:  # any
```

## (root)

Consumer values of my-crd.

| Key | Type | Per target | Description |
| --- | --- | --- | --- |
| `target` | string | no | Render target: `<env>` or `<env>-<seq>` (e.g. `prod-01`). Selects every per-target value. |
| `renderMode` | scalar | no | `validate` prints the render with its diagnostics; `deploy` (default) aborts on errors. |
| `metadata` | map |  | Metadata of the rendered object. |
| `application` | map |  | The application the object describes. |
| `<key>` | any |  | The consumer chart's own values; not read by my-crd. |

## `metadata`

Metadata of the rendered object.

| Key | Type | Description |
| --- | --- | --- |
| `labels` | map | Labels copied onto the rendered object; standard labels win on a collision. |

## `metadata.labels`

Labels copied onto the rendered object; standard labels win on a collision.

| Key | Type | Per target | Description |
| --- | --- | --- | --- |
| `<key>` | string | markers | Label value; may hold `@NAME@` markers. |

## `application`

The application the object describes.

| Key | Type | Description |
| --- | --- | --- |
| `services` | map, keys match `^[A-Z0-9_]+$` | Services by ID. |

## `application.services`

Services by ID.

| Key | Type | Description |
| --- | --- | --- |
| `<ID>` | map, by `type`: environment, greeter, leader | One service; its keys depend on `type`. |

## `application.services.*[type=environment]`

A service that only declares variables.

| Key | Type | Per target | Default | Description |
| --- | --- | --- | --- | --- |
| `type` (shared) | string | no |  | Service type; selects the handler and the keys below. |
| `enabled` (shared) | bool | no | `true` | `false` removes the service from the output. |
| `environment` (shared) | map, keys match `^[A-Z][A-Z0-9_]*$` |  |  | Variables owned by the service, by name (`<ID>_`-prefixed by convention). |

**Example**

```yaml
application:
  services:
    SHARED:
      environment:
        SHARED_DB_HOST:
          default: db.internal
          prod: db.prod.internal
          targetContainer: main
      type: environment
```

**Example output**

`spec.application.services.SHARED` as rendered.

```yaml
environment:
  SHARED_DB_HOST:
    targetContainer: main
    value: db.prod.internal
type: environment
```

## `application.services.*[type=environment].environment`

Variables owned by the service, by name (`<ID>_`-prefixed by convention).

| Key | Type | Per target | Description |
| --- | --- | --- | --- |
| `<NAME>` | scalar | yes | A variable: a scalar or a token declaration (target keys, `default`, `match`, annotation `targetContainer`). |

## `application.services.*[type=greeter]`

Example type: exports `<ID>_GREETER` and a configMap mount `<ID>-config`.

| Key | Type | Per target | Default | Description |
| --- | --- | --- | --- | --- |
| `type` (shared) | string | no |  | Service type; selects the handler and the keys below. |
| `enabled` (shared) | bool | no | `true` | `false` removes the service from the output. |
| `environment` (shared) | map, keys match `^[A-Z][A-Z0-9_]*$` |  |  | Variables owned by the service, by name (`<ID>_`-prefixed by convention). |
| `greeting` | string | yes |  | Content of the file `message`; absent → nothing generated. |

**Example**

```yaml
application:
  services:
    APP:
      greeting:
        default: hello from @ENV@
        prod: hello from production
      type: greeter
```

**Generated variables**

Added to the service's `environment` by its handler.

| Pattern | Example | Value | Container |
| --- | --- | --- | --- |
| <ID>_GREETER | APP_GREETER | APP | main |

**Example output**

`spec.application.services.APP` as rendered.

```yaml
environment:
  APP_GREETER:
    targetContainer: main
    value: APP
type: greeter
```

## `application.services.*[type=greeter].environment`

Variables owned by the service, by name (`<ID>_`-prefixed by convention).

| Key | Type | Per target | Description |
| --- | --- | --- | --- |
| `<NAME>` | scalar | yes | A variable: a scalar or a token declaration (target keys, `default`, `match`, annotation `targetContainer`). |

## `application.services.*[type=leader]`

Example type: exports `<ID>_SEED` and references a greeter's variable and file.

| Key | Type | Per target | Default | Description |
| --- | --- | --- | --- | --- |
| `type` (shared) | string | no |  | Service type; selects the handler and the keys below. |
| `enabled` (shared) | bool | no | `true` | `false` removes the service from the output. |
| `environment` (shared) | map, keys match `^[A-Z][A-Z0-9_]*$` |  |  | Variables owned by the service, by name (`<ID>_`-prefixed by convention). |
| `greeter` | string | no |  | ID of the greeter service to reference; absent → nothing generated. |

**Example**

```yaml
application:
  services:
    LEAD:
      greeter: APP
      type: leader
```

**Generated variables**

Added to the service's `environment` by its handler.

| Pattern | Example | Value | Container |
| --- | --- | --- | --- |
| <ID>_SEED | LEAD_SEED | 5 | main |

**References**

Nodes the service points the controller at.

| Pattern | Example |
| --- | --- |
| /spec/application/services/<greeter>/environment/<greeter>_GREETER | /spec/application/services/APP/environment/APP_GREETER |
| /spec/application/volumeMounts/<greeter>-config/files/message | /spec/application/volumeMounts/APP-config/files/message |

**Example output**

`spec.application.services.LEAD` as rendered.

```yaml
environment:
  LEAD_SEED:
    targetContainer: main
    value: "5"
references:
- /spec/application/services/APP/environment/APP_GREETER
- /spec/application/volumeMounts/APP-config/files/message
type: leader
```

## `application.services.*[type=leader].environment`

Variables owned by the service, by name (`<ID>_`-prefixed by convention).

| Key | Type | Per target | Description |
| --- | --- | --- | --- |
| `<NAME>` | scalar | yes | A variable: a scalar or a token declaration (target keys, `default`, `match`, annotation `targetContainer`). |
