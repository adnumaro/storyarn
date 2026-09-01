/**
 * Bundle entry — every component here must also appear in registry.json
 * (build.mjs cross-checks the register() calls against it).
 *
 * React-side prop idiom mapped per component via wrap() aliases:
 * value/onChange for text inputs, checked/onCheckedChange for toggles,
 * open/onOpenChange for dialogs. Callbacks receive the Vue emit payload
 * (the value itself, not a DOM event).
 */
import { wrap, type WrapOptions } from "./harness/wrap";

import { Button } from "@components/ui/button";
import { Badge } from "@components/ui/badge";
import { Input } from "@components/ui/input";
import { Textarea } from "@components/ui/textarea";
import { Label } from "@components/ui/label";
import { Switch } from "@components/ui/switch";
import { Checkbox } from "@components/ui/checkbox";
import { Separator } from "@components/ui/separator";
import { Progress } from "@components/ui/progress";
import { Toggle } from "@components/ui/toggle";
import { ScrollArea } from "@components/ui/scroll-area";
import SaveIndicator from "@components/SaveIndicator.vue";
import UserAvatar from "@components/UserAvatar.vue";
import ConfirmDialog from "@components/ConfirmDialog.vue";
import SelectAdapter from "./adapters/SelectAdapter.vue";
import DropdownMenuAdapter from "./adapters/DropdownMenuAdapter.vue";
import TabsAdapter from "./adapters/TabsAdapter.vue";
import DialogAdapter from "./adapters/DialogAdapter.vue";
import PopoverAdapter from "./adapters/PopoverAdapter.vue";
import TooltipAdapter from "./adapters/TooltipAdapter.vue";
import RadioGroupAdapter from "./adapters/RadioGroupAdapter.vue";
import ToggleGroupAdapter from "./adapters/ToggleGroupAdapter.vue";
import SheetAdapter from "./adapters/SheetAdapter.vue";
import CollapsibleAdapter from "./adapters/CollapsibleAdapter.vue";
import TableAdapter from "./adapters/TableAdapter.vue";
import TextField from "@components/forms/fields/TextField.vue";
import NumberField from "@components/forms/fields/NumberField.vue";
import SelectField from "@components/forms/fields/SelectField.vue";
import ToggleField from "@components/forms/fields/ToggleField.vue";
import SliderField from "@components/forms/fields/SliderField.vue";
import ButtonGroupField from "@components/forms/fields/ButtonGroupField.vue";
import BooleanToggle from "@components/forms/BooleanToggle.vue";
import PasswordInput from "@components/forms/PasswordInput.vue";
import EditableText from "@components/forms/EditableText.vue";
import ColorPicker from "@components/forms/ColorPicker.vue";

const NAMESPACE = "Storyarn_e287ac";

const registry: Record<string, unknown> = {};

function register(name: string, comp: unknown, opts: WrapOptions = {}): void {
  registry[name] = wrap(name, comp as never, opts);
}

const textModel: WrapOptions = {
  propAliases: { value: "modelValue", onChange: "onUpdate:modelValue" },
};
const checkedModel: WrapOptions = {
  propAliases: {
    checked: "modelValue",
    defaultChecked: "defaultValue",
    onCheckedChange: "onUpdate:modelValue",
  },
};

register("Button", Button);
register("Badge", Badge);
register("Input", Input, textModel);
register("Textarea", Textarea, textModel);
register("Label", Label, { propAliases: { htmlFor: "for" } });
register("Switch", Switch, checkedModel);
register("Checkbox", Checkbox, checkedModel);
register("Separator", Separator);
register("Progress", Progress, { propAliases: { value: "modelValue" } });
register("SaveIndicator", SaveIndicator);
register("UserAvatar", UserAvatar);
register("ConfirmDialog", ConfirmDialog, {
  propAliases: { onOpenChange: "onUpdate:open" },
});

const openModel: WrapOptions["propAliases"] = { onOpenChange: "onUpdate:open" };

register("Toggle", Toggle, {
  propAliases: { pressed: "modelValue", onPressedChange: "onUpdate:modelValue" },
});
register("ScrollArea", ScrollArea);
register("Tabs", TabsAdapter, textModel);
register("Select", SelectAdapter, textModel);
register("RadioGroup", RadioGroupAdapter, textModel);
register("ToggleGroup", ToggleGroupAdapter, textModel);
register("Dialog", DialogAdapter, { propAliases: openModel, contentSlots: ["footer"] });
register("Sheet", SheetAdapter, { propAliases: openModel, contentSlots: ["footer"] });
register("Popover", PopoverAdapter, { propAliases: openModel, contentSlots: ["content"] });
register("Tooltip", TooltipAdapter);
register("DropdownMenu", DropdownMenuAdapter);
register("Collapsible", CollapsibleAdapter, { propAliases: openModel });
register("Table", TableAdapter);

const updateEmit: WrapOptions = { propAliases: { onChange: "onUpdate" } };

register("TextField", TextField, updateEmit);
register("NumberField", NumberField, updateEmit);
register("SelectField", SelectField, updateEmit);
register("ToggleField", ToggleField);
register("SliderField", SliderField, updateEmit);
register("ButtonGroupField", ButtonGroupField, updateEmit);
register("BooleanToggle", BooleanToggle, { propAliases: { onChange: "onUpdate:value" } });
register("PasswordInput", PasswordInput, textModel);
register("EditableText", EditableText, textModel);
register("ColorPicker", ColorPicker, textModel);

type Namespace = Record<string, unknown> & { __errors?: unknown[] };
const g = window as unknown as Record<string, Namespace | undefined>;
const ns: Namespace = g[NAMESPACE] ?? {};
Object.assign(ns, registry);
ns.__errors = ns.__errors ?? [];
g[NAMESPACE] = ns;
