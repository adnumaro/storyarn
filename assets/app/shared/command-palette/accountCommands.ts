import { GraduationCap, Plug, ShieldCheck, User } from "lucide-vue-next";
import type { PaletteCommand } from "./registry";

interface AccountCommandFlags {
  aiIntegrations?: boolean;
}

/**
 * Account-settings commands shared by every layout that mounts the palette.
 * Labels reuse the settings shell's own nav keys — one concept, one name.
 * Flagged destinations use the same actor-resolved feature state as the
 * settings shell, so unavailable commands are absent rather than failing.
 */
export function accountPaletteCommands(flags: AccountCommandFlags = {}): PaletteCommand[] {
  const commands: PaletteCommand[] = [
    {
      id: "account.profile",
      labelKey: "settings.nav.items.profile",
      groupKey: "settings.nav.sections.account",
      icon: User,
      href: "/users/settings",
    },
    {
      id: "account.security",
      labelKey: "settings.nav.items.security",
      groupKey: "settings.nav.sections.account",
      icon: ShieldCheck,
      href: "/users/settings/security",
    },
    {
      id: "account.tutorials",
      labelKey: "settings.nav.items.tutorials",
      groupKey: "settings.nav.sections.account",
      icon: GraduationCap,
      href: "/users/settings/tutorials",
    },
  ];

  if (flags.aiIntegrations) {
    commands.push({
      id: "account.integrations",
      labelKey: "settings.nav.items.integrations",
      groupKey: "settings.nav.sections.account",
      icon: Plug,
      href: "/users/settings/integrations",
    });
  }

  return commands;
}
