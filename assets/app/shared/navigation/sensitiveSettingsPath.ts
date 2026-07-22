export function sensitiveSettingsPath(path: string, sudoGrant: string | null): string {
  if (!sudoGrant) return path;

  const query = new URLSearchParams({ sudo_grant: sudoGrant });
  return `${path}?${query.toString()}`;
}
