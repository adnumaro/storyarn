import type { Ref } from "vue";
import { createContext } from "reka-ui";

export interface CommandContext {
  allItems: Ref<Map<string, string>>;
  allGroups: Ref<Map<string, Set<string>>>;
  disableFilter: Ref<boolean>;
  filterItems: () => void;
  filterState: {
    search: string;
    filtered: {
      count: number;
      items: Map<string, number>;
      groups: Set<string>;
    };
  };
}

export interface CommandGroupContext {
  id: string;
}

export const [useCommand, provideCommandContext] = createContext<CommandContext>("Command");

export const [useCommandGroup, provideCommandGroupContext] =
  createContext<CommandGroupContext>("CommandGroup");
