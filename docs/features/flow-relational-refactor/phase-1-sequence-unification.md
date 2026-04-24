# Phase 1 — Sequence unification + sequence_configs

Parte del refactor descrito en [`REFACTOR.md`](./REFACTOR.md). Ejecución planificada en [`EXECUTION.md`](./EXECUTION.md).

## Objetivo

Unificar sequences en `flow_nodes` con `type='sequence'`. Crear `flow_node_sequence_configs` 1:1 (name/width/height). Drop `flow_sequences`. Unificar jerarquía vía `parent_id` self-FK en `flow_nodes`.

## Pre-requisitos

Ninguno. Punto de partida del refactor.

## Outcome observable

El usuario puede anidar sequences con children mixtos end-to-end (nodos + sequences dentro de una sequence). `wrap_selection_in_sequence` funciona con IDs mixtos de cualquier tipo de flow_node.

## Schema changes (1 migración atómica)

Archivo: `priv/repo/migrations/YYYYMMDDHHMMSS_unify_sequences_into_flow_nodes.exs`.

1. `ALTER TABLE flow_nodes DROP CONSTRAINT <type_check>; ADD CONSTRAINT type_check CHECK (type IN (..., 'sequence'))`.
2. `ALTER TABLE flow_nodes ADD COLUMN parent_id bigint REFERENCES flow_nodes(id) ON DELETE SET NULL` + índice.
3. Crear tabla `flow_node_sequence_configs`:

   ```
   flow_node_id  bigint PK FK → flow_nodes(id) ON DELETE CASCADE
   name          varchar(200) NOT NULL
   width         float NOT NULL DEFAULT 300.0
   height        float NOT NULL DEFAULT 200.0
   inserted_at, updated_at
   CHECK (length(name) >= 1)
   ```

4. **Data migration** (una transacción):
   - Temp table `_seq_mapping(old_seq_id bigint, new_node_id bigint)`.
   - Para cada row activo+borrado en `flow_sequences`: INSERT en `flow_nodes` con `type='sequence'`, `flow_id`, `position_x`, `position_y`, `deleted_at`, timestamps; RETURNING guarda en `_seq_mapping`.
   - INSERT en `flow_node_sequence_configs` con mapeo: `flow_node_id = new_node_id`, `name`, `width`, `height` copiados del row viejo.
   - UPDATE `flow_nodes` SET `parent_id = mapping.new_node_id` WHERE `parent_sequence_id = mapping.old_seq_id`.
   - UPDATE `flow_nodes` (los recién insertados tipo sequence) SET `parent_id = mapping.new_node_id` FROM `_seq_mapping inner, flow_sequences outer` WHERE `outer.parent_id = inner.old_seq_id`.
   - DROP temp table.

5. `ALTER TABLE flow_nodes DROP COLUMN parent_sequence_id`.
6. `DROP TABLE flow_sequences`.
7. **Triggers** (todos BEFORE INSERT/UPDATE en PL/pgSQL):
   - `fn_validate_parent_is_sequence` — si `NEW.parent_id IS NOT NULL`, el row referenciado debe tener `type='sequence'`.
   - `fn_validate_sequence_config_owner` — en `flow_node_sequence_configs`: owner debe ser `type='sequence'`.
   - `fn_validate_connection_endpoints_not_sequence` — en `flow_connections`: source/target no pueden ser `type='sequence'`.
   - `fn_prevent_type_change_to_sequence_with_connections` — en `flow_nodes` UPDATE OF type: raise si `NEW.type='sequence'` y hay connections entrantes o salientes.
   - `fn_flow_nodes_soft_delete_nilify_parent` — AFTER UPDATE OF deleted_at: SET `parent_id = NULL` en children cuando `OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL`.

**Nota:** `flow_sequences.tracks` jsonb se pierde (vacío en prod; la tabla `flow_node_sequence_tracks` se crea en F6).

## Ecto schemas

**Modificados:**

- `lib/storyarn/flows/flow_node.ex`
  - `@node_types` añade `"sequence"`.
  - Quitar `alias Storyarn.Flows.Sequence`; quitar `belongs_to :parent_sequence, Sequence`; quitar `parent_sequence_id/parent_sequence` del `@type t`.
  - Añadir `belongs_to :parent, __MODULE__, foreign_key: :parent_id`.
  - Añadir `has_many :children, __MODULE__, foreign_key: :parent_id`.
  - Añadir `has_one :sequence_config, Storyarn.Flows.SequenceConfig`.
  - `update_changeset/2`: cambiar `:parent_sequence_id` → `:parent_id`. Ajustar `foreign_key_constraint`.

**Nuevo:**

- `lib/storyarn/flows/sequence_config.ex`
  - Schema `flow_node_sequence_configs`.
  - Fields: `name`, `width`, `height`. `belongs_to :flow_node, FlowNode, primary_key: true`.
  - Changesets: `create_changeset/2`, `update_changeset/2`.

**Borrado:**

- `lib/storyarn/flows/sequence.ex` — el módulo Sequence schema desaparece. `SequenceCrud` queda como API que opera sobre `flow_nodes` + `sequence_config` bajo el capó.

## CRUD / domain modules

- `lib/storyarn/flows/sequence_crud.ex` — **reescrito completo**:
  - Todas las consultas operan sobre `flow_nodes` filtrando `type='sequence'`, con `preload(:sequence_config)`.
  - `list_sequences/1`, `list_deleted/1`, `get_sequence/2`, `get_sequence!/2` — filtran por flow_id + type='sequence'.
  - `create_sequence/2` — INSERT en flow_nodes (type='sequence', position_x/y, flow_id, parent_id) + INSERT en sequence_configs (name/width/height) en una transacción.
  - `update_sequence/2` — permite actualizar name/width/height (en config) y position_x/y/parent_id (en flow_nodes).
  - `delete_sequence/1` — soft-delete directo del flow_node row (NO pasa por Trashable; el trigger de soft-delete nilifica parent_id de children).
  - `restore_sequence/1` — quita `deleted_at` del flow_node. Sin Trashable.
  - `wrap_selection_in_sequence/3` — acepta `node_ids` de cualquier flow_node.id. Carga flow_nodes, valida `common_parent_id` usando el nuevo `parent_id`, crea sequence + config, asigna `parent_id` a todos los seleccionados.

- `lib/storyarn/flows.ex` (facade):
  - Los delegates de sequence siguen (`list_sequences`, `list_deleted_sequences`, `get_sequence`, `get_sequence!`, `create_sequence`, `update_sequence`, `delete_sequence`, `restore_sequence`, `wrap_selection_in_sequence`) apuntando al SequenceCrud reescrito.

- `lib/storyarn/shared/trashable.ex`:
  - Quitar entry `:flow_sequence` del `@targets` y `@inbound_refs`.
  - Quitar `alias Storyarn.Flows.Sequence`.

- `lib/storyarn/workers/trash_retention_worker.ex`:
  - Quitar el handling de `Sequence` (el worker deja de purgar sequences).

- `lib/storyarn/flows/entity_trash_refs.ex`:
  - Quitar `alias Storyarn.Flows.Sequence` y la referencia `:flow_sequence` en `@type target_type`.

- `lib/storyarn/flows/entity_trash_ref.ex`:
  - Quitar `target_flow_sequence_id` de la schema + CHECK (F7 borrará la tabla entera).

- `lib/storyarn/live_vue_encoders.ex`:
  - Quitar `Protocol.derive(LiveVue.Encoder, Storyarn.Flows.Sequence)`.
  - Añadir `Protocol.derive(LiveVue.Encoder, Storyarn.Flows.SequenceConfig)`.

## Handlers LiveView

- `lib/storyarn_web/live/flow_live/show.ex:746` — `handle_event("wrap_selection_in_sequence", ...)`: sin cambios funcionales (el handler pasa IDs al CRUD, que ahora acepta cualquier flow_node.id).

## Serializer

- `lib/storyarn/flows.ex` `serialize_for_canvas/2`:
  - Línea 691: `parent_sequence_id: node.parent_sequence_id` → `parent_id: node.parent_id`.
  - Bloque `sequences:` (líneas 705-715): sigue vía `SequenceCrud.list_sequences(flow.id)`, que devuelve flow_nodes preloaded. Map:

    ```
    %{
      id: seq.id,
      name: seq.sequence_config.name,
      position: %{x: seq.position_x, y: seq.position_y},
      width: seq.sequence_config.width,
      height: seq.sequence_config.height,
      parent_id: seq.parent_id
    }
    ```

  - Opcional: mover sequences del array separado a inline en `nodes[]` con `type='sequence'`. Simpler frontend. Decidir en F1 o diferir a F2.

## Evaluator

N/A. El evaluator runtime no consume sequences hoy.

## Frontend (TS/Vue)

- `assets/app/modules/flows/lib/flow-sequence.ts` — **DELETE** (la clase `FlowSequence` desaparece).
- `assets/app/modules/flows/lib/rete-schemes.ts` — `FlowGraphNode = FlowNode` (quitar union con FlowSequence).
- `assets/app/modules/flows/lib/flow-node.ts` — permitir `parent` cuando type='sequence'.
- `assets/app/modules/flows/setup.ts` — línea 106: `if (context.payload instanceof FlowSequence) return Sequence` → `if (context.payload.data.type === 'sequence') return Sequence`. Quitar import de FlowSequence.
- `assets/app/modules/flows/composables/useFlowEditor.ts` — quitar `addSequenceToEditor`, `reteSequenceId`. `addNodeToEditor` detecta type='sequence' y setea `width/height` del payload.
- `assets/app/modules/flows/services/flowMarquee.ts` — línea 148: quitar el filtro `instanceof FlowSequence`. **Sequences ahora son seleccionables.**
- `assets/app/modules/flows/lib/context_menu_items.ts` — línea 153 y adyacentes: quitar filtro `FlowSequence instanceof`. Sequences pueden formar parte del `getSelectedNodeDbIds`.
- `assets/app/modules/flows/components/Sequence.vue` — prop `data: FlowSequence` → `data: FlowNode` con type='sequence'. Lee `data.sequenceName`, `data.width`, `data.height` del flatten del serializer.
- `assets/app/modules/flows/components/FlowNode.vue` — sin cambios (dispatch vive en setup.ts).
- `assets/app/modules/flows/types.ts` — quitar `sequences` como array separado (si cambiamos el payload) o mantener.

## Screenplay sync

N/A. Screenplay sync no crea sequences.

## Export / Import

N/A en F1.

## Tests

**Reescritos:**

- `test/storyarn/flows/sequence_crud_test.exs` — adapta aserciones: `seq.name` → `seq.sequence_config.name`. `seq.parent_id` queda (ahora es `flow_nodes.parent_id`). Remover aserciones de Trashable.
- `test/storyarn/flows_test.exs` líneas 970-1008 (serialize_for_canvas con sequences): ajustar `parent_sequence_id` → `parent_id` en payload.
- `test/storyarn/shared/trashable_test.exs` — eliminar test "sweeps parent_sequence_id" (responsabilidad pasa al trigger).
- `test/storyarn/flows/entity_trash_refs_test.exs` — eliminar tests que usan `:flow_sequence` / `parent_sequence_id`.

**Nuevos:**

- `test/storyarn/flows/sequence_config_test.exs` — changeset + validaciones del nuevo schema.
- Integration test: trigger `fn_validate_parent_is_sequence` (INSERT con parent_id apuntando a nodo non-sequence debe fallar).
- Integration test: cascade soft-delete (soft-delete de sequence → children quedan con parent_id=NULL).

## Verificación

1. `mix ecto.migrate` limpia.
2. `mix test test/storyarn/flows/sequence_crud_test.exs` pasa.
3. Test manual: `mix phx.server`, crear flow con sequences anidadas, arrastrar un nodo de una sequence a otra, wrap selection con nodes+sequence mixtos → se crea una sequence outer conteniendo ambos.
4. Verificar en DB: `SELECT id, type, parent_id FROM flow_nodes WHERE flow_id = <X>` muestra jerarquía correcta.
5. Verificar trigger: `INSERT INTO flow_connections (source_node_id, ...) VALUES (<sequence_node_id>, ...)` debe fallar.
6. `just quality` (oxlint, credo, tests, e2e, vitest) limpia.

## Rollback

- `mix ecto.rollback` devuelve al estado previo (migración reversible: `down` recrea flow_sequences, restaura parent_sequence_id, elimina sequence_configs).
- Revertir commit de código.
