import type { PlaceholderIssue, SaveState } from "../../../domain/types";

/** Where the open string sits in the list and whether the arrows can move. */
export interface EditorNavigation {
  /** Localized "3 of 52", or null when the string is not in the loaded list. */
  positionLabel: string | null;
  hasPrevious: boolean;
  hasNext: boolean;
}

/** The live state of the editor, owned by `useTranslationEditor`. */
export interface EditorState {
  saveState: SaveState;
  saveError: string;
  translating: boolean;
  placeholderIssue: PlaceholderIssue | null;
  finalUnavailable: boolean;
}

/** Who wrote the translation and when, for the history line. */
export interface EditorHistory {
  translatedBy: string | null;
  lastTranslatedAt: string | null;
  machineTranslated: boolean;
}
