# Flow Relational Refactor — Execution Plan

Este documento describe la ejecución fasificada del refactor descrito en [`REFACTOR.md`](./REFACTOR.md).

## Estrategia

- **Incremental con dual-write/dual-read** donde haga falta. Cada fase deja el código compilando, los tests pasando, y la app funcional.
- **Branch:** `feat/live-vue-sheets` (branch actual). Sin branch separado.
- **Pre-release:** no hay usuarios. Dev DB es disposable, pero cada fase migra datos correctamente para que la siguiente no empiece sobre basura.
- **Cada fase es revertible** antes de la siguiente (no se acumulan estados intermedios inconsistentes en disco).

## Overview de fases

| #   | Fase                                      | Objetivo                                                                                                                                                                                                                                                                                                                                 | Outcome observable                                                                                          |
| --- | ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| 1   | Sequence unification + `sequence_configs` | Unificar sequences en `flow_nodes` con `type='sequence'`, `parent_id` self-FK. Crear `flow_node_sequence_configs` 1:1 (name/width/height). Drop `flow_sequences`. Tracks se deja para F6 (hoy vacío).                                                                                                                                    | Usuario puede anidar sequences con children mixtos end-to-end.                                              |
| 2   | Columnas compartidas en `flow_nodes`      | Promover a columnas inline en `flow_nodes`: `text`, `color`, `font_size`, `description`, `referenced_flow_id`. Migrar jsonb → columnas para annotation, hub (color), exit (color), instruction (description), subflow (referenced_flow_id), dialogue (text). `data` jsonb se queda solo con lo type-específico wide que se mueve en F3+. | Tipos light relational. CHECK per-type en flow_nodes blinda ownership.                                      |
| 3   | Dialogue externalizado                    | Crear `flow_node_dialogue_configs` (speaker/audio/avatar/stage_directions/menu_text/technical_id/localization_id) + `flow_node_dialogue_responses` + columna `flow_connections.source_response_id`. Triggers: owner de configs, fan-out soft-delete de sheets/assets/sheet_avatars, coherencia source_response.                          | Dialogue refs FK-enforced. Responses relational. Conexiones desde response por FK.                          |
| 4   | Condition + Instruction relational        | Crear `flow_node_condition_blocks` + `flow_node_statements` (kind='rule' o 'assignment'). Migrar `condition.blocks/rules`, `instruction.assignments`, condition/instruction de responses. Triggers: owner polimórfico, fan-out soft-delete de sheet_blocks (CASCADE).                                                                    | Variable refs FK-enforced. Cero jsonb con cross-refs.                                                       |
| 5   | Exit + Hub/Jump externalizados            | Crear `flow_node_exit_configs` (exit_mode/outcome_tags/target_scene_id/target_flow_id/label/technical_id) + `flow_node_anchor_configs` (hub_id/target_hub_node_id/label). Triggers: owner, cross-tabla exit_mode ↔ targets, fan-out soft-delete de flows/scenes.                                                                         | Exit target refs FK-enforced (scene/flow). Hub/jump strings en columnas propias con CHECK `num_nonnulls=1`. |
| 6   | Sequence tracks externalizados            | Crear `flow_node_sequence_tracks`. Trigger owner + fan-out soft-delete de assets.                                                                                                                                                                                                                                                        | Tracks relational, FK integrity con assets preparado para cuando FlowPlay los consuma.                      |
| 7   | F0A cleanup                               | Borrar `Storyarn.Shared.Trashable`, `Storyarn.Flows.EntityTrashRefs`, `Storyarn.Flows.EntityTrashRef`, `Storyarn.Workers.TrashRetentionWorker`, `Plan.retention_hours`, cron en config.exs, delegates en facade, tests asociados. Simplificar delete/restore en CRUDs.                                                                   | ~700 líneas menos. Maquinaria sustituida por FK + triggers DB-enforced.                                     |

## Dependencias entre fases

- **F1 desbloquea todas las demás** — sin unificación, la jerarquía sigue partida y ningún nodo-con-data puede moverse de forma consistente.
- **F2 prepara `flow_nodes`** con columnas compartidas antes de que F3-F5 creen tablas 1:1 per-type que esperan encontrar esas columnas ya promovidas.
- **F3 crea `flow_node_dialogue_responses`** que F4 necesita — condition/instruction statements de responses llevan FK a esa tabla.
- **F7 va al final** porque F0A (`Trashable` + `entity_trash_refs`) sigue en uso hasta que TODAS las refs sean relacionales. Si se quita antes, rompe la integridad durante la transición.

## Cobertura del scope completo

Cada item del scope original está cubierto, distribuido entre fases:

| Item del scope                              | F1                  | F2                                                                                    | F3                                              | F4                                                 | F5                          | F6           | F7                                             |
| ------------------------------------------- | ------------------- | ------------------------------------------------------------------------------------- | ----------------------------------------------- | -------------------------------------------------- | --------------------------- | ------------ | ---------------------------------------------- |
| Migración + Ecto schemas + CRUD             | ✓                   | ✓                                                                                     | ✓                                               | ✓                                                  | ✓                           | ✓            | —                                              |
| 9 node modules (`nodes/*/node.ex`)          | sequence            | annotation + text/color/desc/ref_flow_id en dialogue, hub, exit, instruction, subflow | dialogue (resto)                                | condition, instruction                             | exit, hub, jump             | —            | —                                              |
| Handlers LiveView                           | seq                 | subset shared-cols                                                                    | dialogue                                        | condition builder, instruction builder             | exit, hub, jump             | —            | —                                              |
| Serializer `flows.ex.serialize_for_canvas`  | ✓                   | ✓                                                                                     | ✓                                               | ✓                                                  | ✓                           | ✓            | —                                              |
| Evaluator (runtime reading refs)            | —                   | lee cols shared                                                                       | dialogue runtime, responses                     | condition eval, instruction eval                   | exit target resolution      | —            | —                                              |
| Frontend (rete-schemes, useFlowEditor, Vue) | ✓ (seq unification) | Vue components light                                                                  | DialogueNode.vue, responses, node-configs pins  | ConditionNode/Builder, InstructionNode/Builder     | ExitNode, HubNode, JumpNode | —            | —                                              |
| F0A removal                                 | —                   | —                                                                                     | —                                               | —                                                  | —                           | —            | ✓                                              |
| Screenplay sync writer                      | —                   | text                                                                                  | speaker + responses                             | —                                                  | —                           | —            | —                                              |
| Tests pesados                               | seq_crud_test       | light types                                                                           | dialogue, connections                           | condition, instruction, variable_reference_tracker | exit, hub, jump             | tracks nuevo | borrado entity_trash_refs_test, trashable_test |
| Export/Import (fountain + JSON)             | —                   | text                                                                                  | speaker, stage_directions, menu_text, responses | —                                                  | exit mode + targets         | —            | —                                              |

## Formato de detalle por fase

Cada fase, detallada en secciones posteriores de este mismo documento, contendrá:

- **Objetivo** y **outcome observable**.
- **Pre-requisitos** (qué fase(s) tienen que estar done).
- **Schema changes** (migraciones concretas, columnas añadidas/eliminadas, triggers).
- **Ecto schemas nuevos/modificados** (módulos a crear o editar).
- **CRUD / domain modules** tocados.
- **Handlers LiveView** tocados.
- **Serializer + evaluator** — qué cambia en cada uno.
- **Frontend** — archivos TS/Vue a tocar.
- **Screenplay sync** — si aplica.
- **Export/Import** — si aplica.
- **Tests** — adjusted + nuevos.
- **Verificación** — cómo comprobar que la fase está correcta (smoke test manual, tests automáticos clave, comprobaciones en DB).
- **Rollback** — cómo revertir antes de pasar a la siguiente fase.

---

## Fase 1 — Sequence unification + sequence_configs

Detalle completo en [`phase-1-sequence-unification.md`](./phase-1-sequence-unification.md).

## Fase 2 — Columnas compartidas en `flow_nodes`

_Pendiente de detallar._

## Fase 3 — Dialogue externalizado

_Pendiente de detallar._

## Fase 4 — Condition + Instruction relational

_Pendiente de detallar._

## Fase 5 — Exit + Hub/Jump externalizados

_Pendiente de detallar._

## Fase 6 — Sequence tracks externalizados

_Pendiente de detallar._

## Fase 7 — F0A cleanup

_Pendiente de detallar._
