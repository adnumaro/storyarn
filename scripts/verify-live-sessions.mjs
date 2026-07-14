#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const routerPath = path.join(repoRoot, "lib", "storyarn_web", "router.ex");
const router = await readFile(routerPath, "utf8");

const failures = [];

for (const session of [":require_authenticated_user", ":project_scope", ":workspace_scope"]) {
  if (new RegExp(`live_session\\s+${session}\\b`).test(router)) {
    failures.push(`Deprecated split LiveView session still exists: live_session ${session}`);
  }
}

const sessionStart = router.indexOf("live_session :authenticated_app");
const sessionEnd = router.indexOf('post "/users/update-password"', sessionStart);

if (sessionStart === -1) {
  failures.push("Missing live_session :authenticated_app");
}

if (sessionStart !== -1 && sessionEnd === -1) {
  failures.push("Could not determine the end of live_session :authenticated_app");
}

const authenticatedSession =
  sessionStart !== -1 && sessionEnd !== -1 ? router.slice(sessionStart, sessionEnd) : "";

const requiredSnippets = [
  "{@user_auth_hook, :require_authenticated}",
  "{@user_auth_hook, :load_workspaces}",
  "{StoryarnWeb.Live.Hooks.ProjectScope, :load_project}",
  "{StoryarnWeb.Live.Hooks.WorkspaceScope, :load_workspace}",
  'live "/workspaces/:workspace_slug", WorkspaceLive.Show, :show',
  'live "/workspaces/:workspace_slug/projects/:project_slug/sheets"',
  'live "/workspaces/:workspace_slug/projects/:project_slug/settings"',
  'live "/users/settings/workspaces/:slug/general", SettingsLive.WorkspaceGeneral, :edit',
];

for (const snippet of requiredSnippets) {
  if (!authenticatedSession.includes(snippet)) {
    failures.push(`Authenticated app live_session is missing expected router entry: ${snippet}`);
  }
}

const publicSessionStart = router.indexOf("live_session :current_user");
const publicSessionEnd = router.indexOf('post "/users/log-in"', publicSessionStart);
const publicSession =
  publicSessionStart !== -1 && publicSessionEnd !== -1
    ? router.slice(publicSessionStart, publicSessionEnd)
    : "";

for (const snippet of [
  'live "/", LandingLive.Index, :index',
  'live "/docs", DocsLive.Show, :index',
  'live "/docs/:category/*path", DocsLive.Show, :show',
  'live "/users/register", UserLive.Registration, :new',
  'live "/users/log-in", UserLive.Login, :new',
]) {
  if (!publicSession.includes(snippet)) {
    failures.push(`Public live_session is missing expected router entry: ${snippet}`);
  }
}

if (failures.length > 0) {
  console.error(`Live session verification failed with ${failures.length} issue(s):\n`);
  console.error(failures.join("\n"));
  process.exitCode = 1;
} else {
  console.log("Verified LiveView session boundaries.");
}
