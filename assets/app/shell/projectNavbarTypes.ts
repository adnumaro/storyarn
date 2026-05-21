export interface ProjectNavbarContextUrls {
  workspace?: string;
  projectSettings: string;
  trash: string;
  tools: Record<string, string>;
}

export interface ProjectNavbarAccountUrls {
  accountSettings: string;
  workspaces: string;
  logout: string;
}

export type ProjectLayoutUrls = ProjectNavbarContextUrls & ProjectNavbarAccountUrls;

export interface CurrentUser {
  id: number | null;
  email: string;
  displayName?: string;
  isSuperAdmin?: boolean;
}

export interface OnlineUser {
  userId: number;
  email: string;
  displayName?: string;
  color?: string;
}
