<script setup>
import GeneralSection from "./sections/GeneralSection.vue";
import LocalizationSection from "./sections/LocalizationSection.vue";
import MembersSection from "./sections/MembersSection.vue";
import SnapshotsSection from "./sections/SnapshotsSection.vue";
import VersionControlSection from "./sections/VersionControlSection.vue";

const {
  section,
  projectName, projectDescription, sourceLanguage, sourceLanguageName,
  themePrimary, themeAccent, hasCustomTheme,
  providerApiEndpoint, hasApiKey, providerUsage,
  members, currentUserId,
  snapshots, canCreateSnapshot, restorationInProgress, workspaceSlug, projectSlug,
  autoSnapshotsEnabled, autoVersionFlows, autoVersionScenes, autoVersionSheets, versionUsage,
} = defineProps({
  section: { type: String, required: true },
  // General
  projectName: { type: String, default: "" },
  projectDescription: { type: String, default: "" },
  sourceLanguage: { type: Object, default: null },
  sourceLanguageName: { type: String, default: "" },
  themePrimary: { type: String, default: "#00D4CC" },
  themeAccent: { type: String, default: "#E8922F" },
  hasCustomTheme: { type: Boolean, default: false },
  // Localization
  providerApiEndpoint: { type: String, default: "https://api-free.deepl.com" },
  hasApiKey: { type: Boolean, default: false },
  providerUsage: { type: Object, default: null },
  // Members
  members: { type: Array, default: () => [] },
  currentUserId: { type: Number, default: null },
  // Snapshots
  snapshots: { type: Array, default: () => [] },
  canCreateSnapshot: { type: Boolean, default: true },
  restorationInProgress: { type: Boolean, default: false },
  workspaceSlug: { type: String, default: "" },
  projectSlug: { type: String, default: "" },
  // Version Control
  autoSnapshotsEnabled: { type: Boolean, default: false },
  autoVersionFlows: { type: Boolean, default: false },
  autoVersionScenes: { type: Boolean, default: false },
  autoVersionSheets: { type: Boolean, default: false },
  versionUsage: { type: Object, default: null },
});
</script>

<template>
  <GeneralSection
    v-if="section === 'general'"
    :project-name="projectName"
    :project-description="projectDescription"
    :source-language="sourceLanguage"
    :source-language-name="sourceLanguageName"
    :theme-primary="themePrimary"
    :theme-accent="themeAccent"
    :has-custom-theme="hasCustomTheme"
  />

  <LocalizationSection
    v-else-if="section === 'localization'"
    :provider-api-endpoint="providerApiEndpoint"
    :has-api-key="hasApiKey"
    :provider-usage="providerUsage"
  />

  <MembersSection
    v-else-if="section === 'members'"
    :members="members"
    :current-user-id="currentUserId"
  />

  <SnapshotsSection
    v-else-if="section === 'snapshots'"
    :snapshots="snapshots"
    :can-create-snapshot="canCreateSnapshot"
    :restoration-in-progress="restorationInProgress"
    :workspace-slug="workspaceSlug"
    :project-slug="projectSlug"
  />

  <VersionControlSection
    v-else-if="section === 'version_control'"
    :auto-snapshots-enabled="autoSnapshotsEnabled"
    :auto-version-flows="autoVersionFlows"
    :auto-version-scenes="autoVersionScenes"
    :auto-version-sheets="autoVersionSheets"
    :version-usage="versionUsage"
  />
</template>
