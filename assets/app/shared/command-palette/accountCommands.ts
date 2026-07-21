import { GraduationCap, ShieldCheck, User } from "lucide-vue-next";
import { liveNavigate } from "../navigation/liveNavigate";
import type { PaletteCommand } from "./registry";

/**
 * Account-settings commands shared by every layout that mounts the palette.
 * Labels reuse the settings shell's own nav keys — one concept, one name.
 * The AI Integrations page is flag-gated server-side and deliberately not
 * listed until the palette can check the flag.
 */
export function accountPaletteCommands(): PaletteCommand[] {
  return [
    {
      id: "account.profile",
      labelKey: "settings.nav.items.profile",
      groupKey: "settings.nav.sections.account",
      icon: User,
      run: () => liveNavigate("/users/settings"),
    },
    {
      id: "account.security",
      labelKey: "settings.nav.items.security",
      groupKey: "settings.nav.sections.account",
      icon: ShieldCheck,
      run: () => liveNavigate("/users/settings/security"),
    },
    {
      id: "account.tutorials",
      labelKey: "settings.nav.items.tutorials",
      groupKey: "settings.nav.sections.account",
      icon: GraduationCap,
      run: () => liveNavigate("/users/settings/tutorials"),
    },
  ];
}
