export const onboardingGuideKeys = [
  "workspace",
  "sheets",
  "flows",
  "scenes",
  "localization",
  "export",
] as const;

export type OnboardingGuideKey = (typeof onboardingGuideKeys)[number];

export interface OnboardingGuideDefinition {
  docsUrl: string;
  imageUrl?: string;
  slides: string[];
}

export const onboardingGuides: Record<OnboardingGuideKey, OnboardingGuideDefinition> = {
  workspace: {
    docsUrl: "/docs/quick-start/create-workspace",
    imageUrl: "/images/docs/workspace-dashboard.webp",
    slides: ["organize", "projects", "collaborate"],
  },
  sheets: {
    docsUrl: "/docs/world-building/sheets-overview",
    imageUrl: "/images/docs/sheets/sheets-character.webp",
    slides: ["structure", "variables", "inheritance"],
  },
  flows: {
    docsUrl: "/docs/narrative-design/flows-overview",
    imageUrl: "/images/docs/flows/flows.webp",
    slides: ["canvas", "logic", "test"],
  },
  scenes: {
    docsUrl: "/docs/scene-design/scenes-overview",
    imageUrl: "/images/docs/scenes.webp",
    slides: ["canvas", "elements", "exploration"],
  },
  localization: {
    docsUrl: "/docs/localization/localization-overview",
    imageUrl: "/images/docs/localization-dashboard.webp",
    slides: ["languages", "sync", "review"],
  },
  export: {
    docsUrl: "/docs/import-export/import-export-overview",
    slides: ["format", "validate", "deliver"],
  },
};

export function isOnboardingGuideKey(value: string): value is OnboardingGuideKey {
  return onboardingGuideKeys.some((key) => key === value);
}

export function sessionKey(guide: OnboardingGuideKey): string {
  return `storyarn:onboarding:snoozed:${guide}`;
}
