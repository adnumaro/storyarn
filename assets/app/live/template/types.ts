export type TemplateVisibility = "public" | "private";
export type TemplateSectionKey = "private" | "public" | "archived";

/** One template as its card shows it. */
export interface TemplateCardItem {
  id: number;
  name: string;
  description: string | null;
  visibility: TemplateVisibility;
  versionNumber: number | null;
  updatedAt: string | null;
  /** The first names the current version previews, at most three. */
  previewNames: string[];
  canManage: boolean;
  href: string;
}

export interface TemplateSection {
  key: TemplateSectionKey;
  templates: TemplateCardItem[];
  totalCount: number;
  page: number;
  totalPages: number;
  prevHref: string | null;
  nextHref: string | null;
}

export interface TemplateVersion {
  id: number;
  versionNumber: number;
  notes: string | null;
  publishedAt: string | null;
  /** Only for readers who manage the template. */
  publishedByEmail: string | null;
  isCurrent: boolean;
}

export interface TemplateCurrentVersion extends TemplateVersion {
  entityCounts: Array<[string, number]>;
  preview: { sheets: string[]; flows: string[]; scenes: string[] };
}

export type PublicationStatus = "queued" | "running" | "retrying" | "published" | "failed";

export interface TemplatePublication {
  id: number;
  name: string;
  status: PublicationStatus | string;
  mode: "new" | "update" | string | null;
  versionNumber: number | null;
  /** The stored failure message of a failed publication, shown as it is. */
  errorMessage: string | null;
  insertedAt: string | null;
}

export interface TemplateInstall {
  id: number;
  versionNumber: number;
  installedAt: string | null;
}

export interface TemplateActiveInstallation {
  id: number;
  projectName: string;
  stage: string;
}

export interface TemplateInstallationFailure {
  id: number;
  errorCode: string | null;
}

export interface TemplateDetail {
  id: number;
  name: string;
  description: string | null;
  visibility: TemplateVisibility;
  status: "active" | "archived";
  canPublish: boolean;
}

export interface TemplateInstallDefaults {
  workspaceId: string;
  versionId: string;
  name: string;
}

/** What the install form needs: where it can create a project, and what is running. */
export interface TemplateInstallState {
  workspaces: Array<{ id: string; name: string }>;
  defaults: TemplateInstallDefaults;
  activeInstallations: TemplateActiveInstallation[];
}
