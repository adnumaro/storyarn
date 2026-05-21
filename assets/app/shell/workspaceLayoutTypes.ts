export interface WorkspaceUser {
  id: number | null;
  email: string;
  displayName?: string;
}

export interface WorkspaceItem {
  id: number;
  slug: string;
  name: string;
}
