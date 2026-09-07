import { useI18n } from "vue-i18n";
import type { Member } from "../types";

export function useBoardText() {
  const { t, te } = useI18n();
  function error(code: string | null) {
    const key = `ideation.errors.${code}`;
    return t(te(key) ? key : "ideation.errors.unavailable");
  }
  function member(id: number | null, members: Member[]) {
    return members.find((person) => person.id === id)?.display_name || t("ideation.formerMember");
  }
  function options(values: readonly string[]) {
    return values.map((value) => ({ value, label: t(`ideation.${value}`) }));
  }
  return { t, error, member, options };
}
