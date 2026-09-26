import type { PublicationStatus } from "./types";

type BadgeVariant = "default" | "secondary" | "destructive" | "outline";

// A finished publication reads strongest, work in flight stays muted.
const PUBLICATION_STATUS_VARIANTS: Record<PublicationStatus, BadgeVariant> = {
  published: "default",
  queued: "secondary",
  running: "secondary",
  retrying: "secondary",
  failed: "destructive",
};

/** The badge variant of a publication status, the same on every template screen. */
export function publicationStatusVariant(status: string): BadgeVariant {
  return PUBLICATION_STATUS_VARIANTS[status as PublicationStatus] ?? "outline";
}
