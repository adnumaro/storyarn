<wizard-report>
# PostHog post-wizard report

The wizard has completed a deep integration of PostHog analytics into Storyarn. The project already had a sophisticated privacy-safe analytics infrastructure (backend `Storyarn.Analytics` + frontend `assets/js/utils/posthog.js` with a strict property allowlist). The integration extended this foundation with 4 new events covering key user journeys: flow player engagement and project data portability.

**Files changed:**

| File                                                                            | Change                                                                                                                                  |
| ------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `assets/js/utils/posthog.js`                                                    | Added 4 new events to the frontend allowlist                                                                                            |
| `lib/storyarn/analytics.ex`                                                     | Added `flow player started` to the backend allowlist                                                                                    |
| `lib/storyarn_web/live/flow_live/player_live.ex`                                | Track `flow player started` on connected mount                                                                                          |
| `assets/app/modules/flows/player/components/PlayerOutcome.vue`                  | Track `flow player completed` on outcome mount                                                                                          |
| `assets/app/modules/projects/settings/export-import/components/ExportPanel.vue` | Track `project exported` on download click                                                                                              |
| `assets/app/modules/projects/settings/export-import/components/ImportPanel.vue` | Track `project imported` when step reaches `done`                                                                                       |
| `.env`                                                                          | Set `POSTHOG_PROJECT_API_KEY`, `POSTHOG_HOST`, `POSTHOG_ENABLED`, `POSTHOG_FRONTEND_ENABLED`, `POSTHOG_FRONTEND_ERROR_TRACKING_ENABLED` |

**Events added:**

| Event                   | Description                                  | File                | Properties                              |
| ----------------------- | -------------------------------------------- | ------------------- | --------------------------------------- |
| `flow player started`   | User begins a flow playback session          | `player_live.ex`    | `project_id`                            |
| `flow player completed` | User reaches an outcome node (end of a flow) | `PlayerOutcome.vue` | `step_count`, `choices_made`            |
| `project exported`      | User downloads a project export file         | `ExportPanel.vue`   | `format`, `asset_mode`, `section_count` |
| `project imported`      | User successfully completes a project import | `ImportPanel.vue`   | `has_conflicts`                         |

**Pre-existing events (unchanged):**

| Event               | Description                 | Properties                                                                              |
| ------------------- | --------------------------- | --------------------------------------------------------------------------------------- |
| `user logged in`    | User authenticated          | `auth_method`                                                                           |
| `user signed up`    | User completed registration | `auth_method`                                                                           |
| `workspace created` | New workspace created       | `workspace_id`                                                                          |
| `project created`   | New project created         | `project_id`, `workspace_id`                                                            |
| `asset uploaded`    | Asset file uploaded         | `asset_type`, `content_type`, `created_variant`, `project_id`, `purpose`, `size_bucket` |
| `page viewed`       | Page navigation             | `route_family`                                                                          |

## Next steps

We've built some insights and a dashboard for you to keep an eye on user behavior, based on the events we just instrumented:

- [Analytics basics dashboard](/dashboard/686438)
- [New signups over time](/insights/uT0tQ9R9) — weekly unique users who sign up
- [Activation funnel: signup → project → player](/insights/Gs0aHEHi) — 3-step conversion funnel showing drop-off between signup, first project, and first flow play
- [Flow player: started vs completed](/insights/uCX2KZ1J) — session start vs outcome reached, revealing flow completion rate
- [Project exports and imports](/insights/vTOakzfm) — power-user data portability activity

### Agent skill

We've left an agent skill folder in your project. You can use this context for further agent development when using Claude Code. This will help ensure the model provides the most up-to-date approaches for integrating PostHog.

</wizard-report>
