# Flow Relational Refactor

## Propósito

Permitir anidar sequences con children mixtos (nodos y otras sequences) como operación de primera clase. Ejemplo:

`Sequence(Entry - Dialogue1 - Sequence(Dialogue2) - Condition - Sequence(Instruction - Dialogue3 - Exit))`

Hoy no es posible porque la jerarquía está partida: sequences y nodos viven en tablas distintas, con relaciones de parent distintas, y todas las capas (selección, wrap, serialización) los tratan como entidades separadas.

El refactor unifica la jerarquía en una sola tabla `flow_nodes` donde la sequence es un tipo de nodo que se auto-referencia vía `parent_id`.

Como consecuencia derivada, las referencias cross-entity que hoy viven dispersas (algunas en columnas FK, otras dentro de campos JSONB) pasan a ser columnas tipadas con integridad referencial garantizada por la base de datos, no por código Elixir.

---

## Estructura de tablas

### `flow_nodes` (base, unificada)

```
id                          bigserial PK
type                        varchar(32) NOT NULL
flow_id                     bigint NOT NULL FK → flows(id) ON DELETE CASCADE
parent_id                   bigint FK → flow_nodes(id) ON DELETE SET NULL        -- self-FK
position_x                  float NOT NULL DEFAULT 0.0
position_y                  float NOT NULL DEFAULT 0.0
word_count                  integer NOT NULL DEFAULT 0
source                      varchar(32) NOT NULL DEFAULT 'manual'
deleted_at                  timestamptz
referenced_flow_id          bigint FK → flows(id) ON DELETE SET NULL             -- shared: subflow + exit
text                        text                                                  -- annotation, dialogue
color                       varchar(7)                                            -- annotation, hub, exit
font_size                   varchar(8)                                            -- annotation
description                 varchar(5000)                                         -- instruction
inserted_at                 timestamptz NOT NULL DEFAULT now()
updated_at                  timestamptz NOT NULL DEFAULT now()

CHECK (type IN ('entry','exit','dialogue','condition','instruction','hub','jump','subflow','annotation','sequence'))
CHECK (source IN ('manual','screenplay_sync'))
CHECK (referenced_flow_id IS NULL OR type IN ('subflow','exit'))
CHECK (text IS NULL OR type IN ('annotation','dialogue'))
CHECK (color IS NULL OR (color ~ '^#[0-9a-fA-F]{6}$' AND type IN ('annotation','hub','exit')))
CHECK (font_size IS NULL OR (font_size IN ('sm','md','lg','xl') AND type = 'annotation'))
CHECK (description IS NULL OR type = 'instruction')

INDEX (flow_id) WHERE deleted_at IS NULL
INDEX (parent_id)
INDEX (flow_id, type) WHERE deleted_at IS NULL
INDEX (deleted_at) WHERE deleted_at IS NOT NULL
```

### `flow_node_dialogue_configs` (1:1 con dialogue)

```
flow_node_id                bigint PK FK → flow_nodes(id) ON DELETE CASCADE
speaker_sheet_id            bigint FK → sheets(id) ON DELETE SET NULL
audio_asset_id              bigint FK → assets(id) ON DELETE SET NULL
avatar_id                   bigint FK → sheet_avatars(id) ON DELETE SET NULL
stage_directions            varchar(5000)
menu_text                   varchar(500)
technical_id                varchar(100)
localization_id             varchar(200)
inserted_at, updated_at     timestamptz

INDEX (speaker_sheet_id)
INDEX (audio_asset_id)
INDEX (avatar_id)
```

### `flow_node_sequence_configs` (1:1 con sequence)

```
flow_node_id                bigint PK FK → flow_nodes(id) ON DELETE CASCADE
name                        varchar(200) NOT NULL
width                       float NOT NULL DEFAULT 300.0
height                      float NOT NULL DEFAULT 200.0
inserted_at, updated_at     timestamptz

CHECK (length(name) >= 1)
```

### `flow_node_anchor_configs` (1:1 con hub ó jump)

```
flow_node_id                bigint PK FK → flow_nodes(id) ON DELETE CASCADE
hub_id                      varchar(100)                                          -- solo hub
target_hub_node_id          varchar(100)                                          -- solo jump
label                       varchar(200)
inserted_at, updated_at     timestamptz

CHECK (num_nonnulls(hub_id, target_hub_node_id) = 1)

INDEX (hub_id)
INDEX (target_hub_node_id)
```

### `flow_node_exit_configs` (1:1 con exit)

```
flow_node_id                bigint PK FK → flow_nodes(id) ON DELETE CASCADE
label                       varchar(200)
technical_id                varchar(100)
outcome_tags                text[] NOT NULL DEFAULT ARRAY[]::text[]
exit_mode                   varchar(32) NOT NULL DEFAULT 'terminal'
target_scene_id             bigint FK → scenes(id) ON DELETE SET NULL
target_flow_id              bigint FK → flows(id) ON DELETE SET NULL
inserted_at, updated_at     timestamptz

CHECK (exit_mode IN ('terminal','flow_reference','caller_return'))
CHECK (num_nonnulls(target_scene_id, target_flow_id) <= 1)

INDEX (target_scene_id)
INDEX (target_flow_id)
```

### `flow_node_dialogue_responses` (N por dialogue)

```
id                          bigserial PK
flow_node_id                bigint NOT NULL FK → flow_nodes(id) ON DELETE CASCADE
position                    integer NOT NULL DEFAULT 0
text                        text
inserted_at, updated_at     timestamptz

INDEX (flow_node_id, position)
```

### `flow_node_sequence_tracks` (N por sequence)

```
id                          bigserial PK
flow_node_id                bigint NOT NULL FK → flow_nodes(id) ON DELETE CASCADE
kind                        varchar(16) NOT NULL
position                    integer NOT NULL DEFAULT 0
asset_id                    bigint FK → assets(id) ON DELETE SET NULL
start_time                  numeric(10,3)
end_time                    numeric(10,3)
volume                      numeric(4,3) DEFAULT 1.0
inserted_at, updated_at     timestamptz

CHECK (kind IN ('background','music','ambient'))

INDEX (flow_node_id, kind, position)
INDEX (asset_id)
```

### `flow_node_condition_blocks` (árbol AND/OR de condition)

```
id                          bigserial PK
flow_node_id                bigint FK → flow_nodes(id) ON DELETE CASCADE         -- root block de condition node
dialogue_response_id        bigint FK → flow_node_dialogue_responses(id) ON DELETE CASCADE   -- root block de una response
parent_block_id             bigint FK → flow_node_condition_blocks(id) ON DELETE CASCADE    -- nested block
logic                       varchar(8) NOT NULL
kind                        varchar(16) NOT NULL DEFAULT 'block'
label                       varchar(200)
position                    integer NOT NULL DEFAULT 0
inserted_at, updated_at     timestamptz

CHECK (logic IN ('all','any'))
CHECK (kind IN ('block','group'))
CHECK (num_nonnulls(flow_node_id, dialogue_response_id, parent_block_id) = 1)

INDEX (flow_node_id)
INDEX (dialogue_response_id)
INDEX (parent_block_id)
```

### `flow_node_statements` (rules + assignments compartidos)

```
id                          bigserial PK
kind                        varchar(16) NOT NULL                                  -- 'rule' | 'assignment'
condition_block_id          bigint FK → flow_node_condition_blocks(id) ON DELETE CASCADE    -- owner si kind='rule'
flow_node_id                bigint FK → flow_nodes(id) ON DELETE CASCADE                    -- owner si kind='assignment' (instruction node)
dialogue_response_id        bigint FK → flow_node_dialogue_responses(id) ON DELETE CASCADE  -- owner si kind='assignment' (response)
position                    integer NOT NULL DEFAULT 0
label                       varchar(200)                                          -- switch mode (rule only)
sheet_id                    bigint FK → sheets(id) ON DELETE CASCADE
block_id                    bigint FK → sheet_blocks(id) ON DELETE CASCADE        -- la variable leída/escrita
operator                    varchar(32) NOT NULL
value_type                  varchar(16) NOT NULL
value_number                numeric
value_text                  text
value_boolean               boolean
value_sheet_id              bigint FK → sheets(id) ON DELETE SET NULL
value_block_id              bigint FK → sheet_blocks(id) ON DELETE SET NULL
inserted_at, updated_at     timestamptz

CHECK (kind IN ('rule','assignment'))
CHECK (num_nonnulls(condition_block_id, flow_node_id, dialogue_response_id) = 1)
CHECK (value_type IN ('number','text','boolean','variable','nil'))
CHECK (
  (value_type = 'number'   AND value_number IS NOT NULL) OR
  (value_type = 'text'     AND value_text IS NOT NULL)   OR
  (value_type = 'boolean'  AND value_boolean IS NOT NULL) OR
  (value_type = 'variable' AND value_block_id IS NOT NULL) OR
  (value_type = 'nil')
)
CHECK (
  (kind = 'rule' AND operator IN (
    'equals','not_equals','contains','not_contains','starts_with','ends_with','is_empty',
    'greater_than','greater_than_or_equal','less_than','less_than_or_equal',
    'is_true','is_false','is_nil','before','after'
  )) OR
  (kind = 'assignment' AND operator IN (
    'set','add','subtract','set_if_unset','set_true','set_false','toggle','clear'
  ))
)

INDEX (condition_block_id, position) WHERE condition_block_id IS NOT NULL
INDEX (flow_node_id, position) WHERE flow_node_id IS NOT NULL
INDEX (dialogue_response_id, position) WHERE dialogue_response_id IS NOT NULL
INDEX (block_id)
INDEX (value_block_id)
```

### `flow_connections` (modificada)

```
id                          bigserial PK
flow_id                     bigint NOT NULL FK → flows(id) ON DELETE CASCADE
source_node_id              bigint NOT NULL FK → flow_nodes(id) ON DELETE CASCADE
target_node_id              bigint NOT NULL FK → flow_nodes(id) ON DELETE CASCADE
source_pin                  varchar(100)                                          -- "output", "true", "false", labels de condition switch
source_response_id          bigint FK → flow_node_dialogue_responses(id) ON DELETE CASCADE
target_pin                  varchar(100)
label                       varchar(200)
inserted_at, updated_at     timestamptz

CHECK (num_nonnulls(source_pin, source_response_id) = 1)

UNIQUE NULLS NOT DISTINCT (source_node_id, source_pin, source_response_id, target_node_id, target_pin)

INDEX (flow_id)
INDEX (source_node_id)
INDEX (target_node_id)
INDEX (source_response_id)
```

`source_response_id` se usa SOLO cuando el source es un dialogue y la conexión sale de una response concreta. Para el resto de tipos (entry/condition/instruction/hub/jump/subflow/exit), `source_pin` guarda el string del pin (`"output"`, `"true"`, `"false"`, labels de condition switch). La CHECK garantiza que cada conexión usa exactamente un mecanismo.

---

## Triggers

### Validación de `flow_node_id` en tablas 1:1 de config

Cada config table valida que su `flow_node_id` apunte a un `flow_nodes.type` correcto:

- `flow_node_dialogue_configs` → `type='dialogue'`
- `flow_node_sequence_configs` → `type='sequence'`
- `flow_node_anchor_configs` → `type IN ('hub','jump')` (+ sub-check: si `hub_id` NOT NULL entonces type='hub'; si `target_hub_node_id` NOT NULL entonces type='jump')
- `flow_node_exit_configs` → `type='exit'`
- `flow_node_dialogue_responses` → `type='dialogue'`
- `flow_node_sequence_tracks` → `type='sequence'`

### Validación de jerarquía

- `flow_nodes.parent_id` debe apuntar a un row con `type='sequence'` (enforced on INSERT + UPDATE).

### Validación polimórfica en condition_blocks y statements

- `flow_node_condition_blocks.flow_node_id` (si set) → `type='condition'`.
- `flow_node_condition_blocks.dialogue_response_id` (si set) → su flow_node es `type='dialogue'`.
- `flow_node_statements`: si `kind='rule'` → owner debe ser `condition_block_id`. Si `kind='assignment'` y `flow_node_id` set → `type='instruction'`.

### Cross-tabla: `exit_mode` ↔ targets

Invariantes que combinan `flow_node_exit_configs` con `flow_nodes.referenced_flow_id`:

- `exit_mode = 'terminal'` → `referenced_flow_id` (del flow_node) debe ser NULL. `target_scene_id` o `target_flow_id` pueden estar set (opcional, polymorphic).
- `exit_mode = 'flow_reference'` → `referenced_flow_id` set. `target_scene_id` y `target_flow_id` deben ser NULL.
- `exit_mode = 'caller_return'` → `referenced_flow_id`, `target_scene_id`, `target_flow_id` todos NULL.

Implementado con trigger en `flow_node_exit_configs` (INSERT/UPDATE) y trigger inverso en `flow_nodes` (UPDATE de `referenced_flow_id`) que consulta `flow_node_exit_configs.exit_mode`.

### Integridad de `flow_connections`

- **Endpoint no-sequence:** trigger BEFORE INSERT OR UPDATE en `flow_connections` que valida que `source_node_id` y `target_node_id` apuntan a rows con `type != 'sequence'`. Las sequences son contenedores, no tienen sockets.
- **Prevención de re-typing:** trigger BEFORE UPDATE OF type en `flow_nodes` que raise si el nuevo type='sequence' y el nodo tiene conexiones entrantes o salientes.
- **Coherencia source_response_id ↔ source_node_id:** trigger BEFORE INSERT OR UPDATE que valida que si `source_response_id` NOT NULL, la response pertenece al dialogue que es la fuente (`flow_node_dialogue_responses.flow_node_id = source_node_id`). Evita conectar desde un dialogue a una response de otro dialogue.

Cross-sequence connections están permitidas (un nodo dentro de Sequence A puede conectar con otro fuera o en Sequence B). Las sequences son agrupación visual + contexto de backdrop, no contenedores estrictos con ingress/egress.

### Soft-delete fan-out

`AFTER UPDATE OF deleted_at` cuando `OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL`. Cada trigger replica el comportamiento del FK equivalente, adelantándolo al soft-delete:

| Target soft-deleted | Acción                                                                                                                         |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `sheets`            | SET NULL → `flow_node_dialogue_configs.speaker_sheet_id`                                                                       |
| `assets`            | SET NULL → `flow_node_dialogue_configs.audio_asset_id`, `flow_node_sequence_tracks.asset_id`                                   |
| `sheet_avatars`     | SET NULL → `flow_node_dialogue_configs.avatar_id`                                                                              |
| `flows`             | SET NULL → `flow_nodes.referenced_flow_id`, `flow_node_exit_configs.target_flow_id`                                            |
| `scenes`            | SET NULL → `flow_node_exit_configs.target_scene_id`                                                                            |
| `sheet_blocks`      | CASCADE DELETE → `flow_node_statements` WHERE `block_id = OLD.id` (matches `ON DELETE CASCADE`). SET NULL → `.value_block_id`. |
| `flow_nodes` (self) | SET NULL → `flow_nodes.parent_id` donde `= OLD.id`                                                                             |

---

## Post-refactor follow-ups

1. **Modal de confirmación al borrar variable referenciada.** Cuando el usuario borra un `sheet_block` (variable) que está siendo usado en algún `flow_node_statement` (rule o assignment), la UI debe mostrar un modal previo listando dónde se usa (qué flow, qué node, qué rule/assignment). Sin el modal, CASCADE del schema borra silenciosamente statements que el usuario no esperaba perder. Performance: despreciable (index scan sobre `block_id` y `value_block_id` en `flow_node_statements`). Implementación: `Flows.find_variable_usages/1` + modal en sheet UI al delete. Feature separada del refactor.
