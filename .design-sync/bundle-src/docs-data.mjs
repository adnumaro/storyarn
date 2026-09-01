/**
 * Per-component docs: React-side API (.d.ts) + usage notes (.prompt.md).
 * build.mjs emits components/<group>/<Name>/<Name>.d.ts and .prompt.md from
 * this map. Callbacks receive Vue emit payloads (the value itself, never a
 * DOM event) — that is the wrap() contract and every entry documents it.
 */

const NS = "window.Storyarn_e287ac";

export const docs = {
  Button: {
    dts: `import * as React from "react";
export interface ButtonProps {
  variant?: "default" | "destructive" | "outline" | "secondary" | "ghost" | "link";
  size?: "default" | "xs" | "sm" | "lg" | "icon" | "icon-xs" | "icon-sm" | "icon-lg";
  disabled?: boolean;
  className?: string;
  onClick?: () => void;
  children?: React.ReactNode;
}
export declare const Button: React.FC<ButtonProps>;`,
    prompt: `Storyarn's button (teal primary). Default variant is the brand action; use \`destructive\` for delete flows, \`ghost\` for toolbars, \`outline\` for secondary actions. Icon sizes (\`icon*\`) make it square.

\`\`\`jsx
const { Button } = ${NS};
<Button onClick={save}>Save changes</Button>
<Button variant="ghost" size="sm">Cancel</Button>
\`\`\``,
  },

  Badge: {
    dts: `import * as React from "react";
export interface BadgeProps {
  variant?: "default" | "secondary" | "destructive" | "outline";
  className?: string;
  children?: React.ReactNode;
}
export declare const Badge: React.FC<BadgeProps>;`,
    prompt: `Small status/count label. \`default\` is teal — reserve it for primary tags; \`secondary\` for neutral metadata, \`destructive\` for error counts.

\`\`\`jsx
<Badge variant="destructive">2 errors</Badge>
\`\`\``,
  },

  Input: {
    dts: `import * as React from "react";
export interface InputProps {
  value?: string | number;
  defaultValue?: string | number;
  onChange?: (value: string | number) => void;
  size?: "xs" | "sm" | "base";
  placeholder?: string;
  disabled?: boolean;
  id?: string;
  type?: string;
  className?: string;
}
export declare const Input: React.FC<InputProps>;`,
    prompt: `Text input. NOTE: \`onChange\` receives the new value directly (not an event) — \`onChange={setName}\` works as-is. Pair with \`Label\` via \`id\`/\`htmlFor\`.

\`\`\`jsx
<Input value={name} onChange={setName} placeholder="Sheet name" />
\`\`\``,
  },

  Textarea: {
    dts: `import * as React from "react";
export interface TextareaProps {
  value?: string | number;
  defaultValue?: string | number;
  onChange?: (value: string | number) => void;
  rows?: number;
  placeholder?: string;
  disabled?: boolean;
  id?: string;
  className?: string;
}
export declare const Textarea: React.FC<TextareaProps>;`,
    prompt: `Multiline text input. \`onChange\` receives the value directly (not an event).

\`\`\`jsx
<Textarea value={text} onChange={setText} rows={3} placeholder="Scene description…" />
\`\`\``,
  },

  Label: {
    dts: `import * as React from "react";
export interface LabelProps {
  htmlFor?: string;
  className?: string;
  children?: React.ReactNode;
}
export declare const Label: React.FC<LabelProps>;`,
    prompt: `Form label. Use \`htmlFor\` matching the control's \`id\`.

\`\`\`jsx
<Label htmlFor="name">Sheet name</Label>
<Input id="name" />
\`\`\``,
  },

  Switch: {
    dts: `import * as React from "react";
export interface SwitchProps {
  checked?: boolean;
  defaultChecked?: boolean;
  onCheckedChange?: (checked: boolean) => void;
  disabled?: boolean;
  id?: string;
  className?: string;
}
export declare const Switch: React.FC<SwitchProps>;`,
    prompt: `On/off toggle (teal when on). Controlled via \`checked\` + \`onCheckedChange\`.

\`\`\`jsx
<Switch checked={autosave} onCheckedChange={setAutosave} id="autosave" />
<Label htmlFor="autosave">Autosave</Label>
\`\`\``,
  },

  Checkbox: {
    dts: `import * as React from "react";
export interface CheckboxProps {
  checked?: boolean | "indeterminate";
  defaultChecked?: boolean | "indeterminate";
  onCheckedChange?: (checked: boolean | "indeterminate") => void;
  disabled?: boolean;
  id?: string;
  className?: string;
}
export declare const Checkbox: React.FC<CheckboxProps>;`,
    prompt: `Checkbox with \`"indeterminate"\` support for partial selections.

\`\`\`jsx
<Checkbox checked={all ? true : some ? "indeterminate" : false} onCheckedChange={toggleAll} />
\`\`\``,
  },

  Separator: {
    dts: `import * as React from "react";
export interface SeparatorProps {
  orientation?: "horizontal" | "vertical";
  className?: string;
}
export declare const Separator: React.FC<SeparatorProps>;`,
    prompt: `Hairline divider. A vertical separator needs a parent with an explicit height (e.g. a flex row with \`height\`).

\`\`\`jsx
<Separator className="my-3" />
\`\`\``,
  },

  Progress: {
    dts: `import * as React from "react";
export interface ProgressProps {
  value?: number;
  max?: number;
  className?: string;
}
export declare const Progress: React.FC<ProgressProps>;`,
    prompt: `Teal progress bar; \`value\` out of \`max\` (default 100).

\`\`\`jsx
<Progress value={65} />
\`\`\``,
  },

  Toggle: {
    dts: `import * as React from "react";
export interface ToggleProps {
  pressed?: boolean;
  onPressedChange?: (pressed: boolean) => void;
  variant?: "default" | "outline";
  size?: "default" | "xs" | "sm" | "lg";
  disabled?: boolean;
  className?: string;
  children?: React.ReactNode;
}
export declare const Toggle: React.FC<ToggleProps>;`,
    prompt: `Single pressable toggle (teal when pressed). For exclusive/multi sets use \`ToggleGroup\`.

\`\`\`jsx
<Toggle pressed={bold} onPressedChange={setBold}>Bold</Toggle>
\`\`\``,
  },

  ScrollArea: {
    dts: `import * as React from "react";
export interface ScrollAreaProps {
  className?: string;
  children?: React.ReactNode;
}
export declare const ScrollArea: React.FC<ScrollAreaProps>;`,
    prompt: `Styled scroll container — give it a fixed size via \`className\`.

\`\`\`jsx
<ScrollArea className="h-40 w-56 rounded-md border">{items}</ScrollArea>
\`\`\``,
  },

  Tabs: {
    dts: `import * as React from "react";
export interface TabItem { value: string; label: string; disabled?: boolean }
export interface TabsProps {
  tabs?: TabItem[];
  value?: string;
  onChange?: (value: string) => void;
  className?: string;
  children?: React.ReactNode;
}
export declare const Tabs: React.FC<TabsProps>;`,
    prompt: `Tab strip driven by \`tabs\`; render the active panel yourself as children, switching on \`value\`.

\`\`\`jsx
<Tabs value={tab} onChange={setTab} tabs={[{ value: "vars", label: "Variables" }, { value: "usages", label: "Usages" }]}>
  {tab === "vars" ? <VarsPanel /> : <UsagesPanel />}
</Tabs>
\`\`\``,
  },

  Collapsible: {
    dts: `import * as React from "react";
export interface CollapsibleProps {
  trigger: string;
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
  className?: string;
  children?: React.ReactNode;
}
export declare const Collapsible: React.FC<CollapsibleProps>;`,
    prompt: `Collapsible section with a chevron trigger row — sidebar tree sections, act/chapter lists.

\`\`\`jsx
<Collapsible trigger="Act I — The Vault" open={open} onOpenChange={setOpen}>
  {scenes.map((s) => <div key={s}>{s}</div>)}
</Collapsible>
\`\`\``,
  },

  UserAvatar: {
    dts: `import * as React from "react";
export interface UserAvatarProps {
  email?: string;
  displayName?: string;
  size?: "xs" | "sm" | "md" | "lg";
  color?: string | null;
}
export declare const UserAvatar: React.FC<UserAvatarProps>;`,
    prompt: `Initials avatar used for collaborators/presence. \`color\` (hex) overrides the generated hue.

\`\`\`jsx
<UserAvatar displayName="Mira Chen" size="sm" />
\`\`\``,
  },

  Select: {
    dts: `import * as React from "react";
export interface SelectOption { value: string; label: string; disabled?: boolean }
export interface SelectOptionGroup { label: string; options: SelectOption[] }
export interface SelectProps {
  options?: (SelectOption | SelectOptionGroup)[];
  value?: string;
  onChange?: (value: string) => void;
  placeholder?: string;
  disabled?: boolean;
  size?: "default" | "sm";
  className?: string;
}
export declare const Select: React.FC<SelectProps>;`,
    prompt: `Dropdown select. Options may be flat or grouped (\`{ label, options }\`). Menus float and match the surrounding theme automatically.

\`\`\`jsx
<Select value={type} onChange={setType} placeholder="Node type…"
  options={[{ value: "dialogue", label: "Dialogue" }, { value: "condition", label: "Condition" }]} />
\`\`\``,
  },

  RadioGroup: {
    dts: `import * as React from "react";
export interface RadioOption { value: string; label: string; disabled?: boolean }
export interface RadioGroupProps {
  options?: RadioOption[];
  value?: string;
  onChange?: (value: string) => void;
  disabled?: boolean;
  className?: string;
}
export declare const RadioGroup: React.FC<RadioGroupProps>;`,
    prompt: `Vertical radio list with labels built in.

\`\`\`jsx
<RadioGroup value={role} onChange={setRole}
  options={[{ value: "editor", label: "Editor — can edit content" }, { value: "viewer", label: "Viewer — read only" }]} />
\`\`\``,
  },

  ToggleGroup: {
    dts: `import * as React from "react";
export interface ToggleGroupOption { value: string; label: string; disabled?: boolean }
export interface ToggleGroupProps {
  items?: ToggleGroupOption[];
  type?: "single" | "multiple";
  value?: string | string[];
  onChange?: (value: string | string[] | undefined) => void;
  variant?: "default" | "outline";
  size?: "default" | "sm" | "lg";
  className?: string;
}
export declare const ToggleGroup: React.FC<ToggleGroupProps>;`,
    prompt: `Segmented toggle set — view switchers, formatting marks. CAUTION: with \`type="single"\`, deselecting the active item calls \`onChange(undefined)\`; keep the previous value if you need one always selected.

\`\`\`jsx
<ToggleGroup type="single" value={view} onChange={(v) => v && setView(v)}
  items={[{ value: "canvas", label: "Canvas" }, { value: "list", label: "List" }]} />
\`\`\``,
  },

  TextField: {
    dts: `import * as React from "react";
export interface TextFieldProps {
  label?: string;
  value?: string;
  onChange?: (value: string) => void;
  placeholder?: string;
  disabled?: boolean;
}
export declare const TextField: React.FC<TextFieldProps>;`,
    prompt: `Labeled compact text field — the app's node/panel inspector row. Prefer these \`*Field\` components for editor property panels; they carry the product's exact spacing and label style.

\`\`\`jsx
<TextField label="Node label" value={label} onChange={setLabel} />
\`\`\``,
  },

  NumberField: {
    dts: `import * as React from "react";
export interface NumberFieldProps {
  label?: string;
  value?: number | string;
  onChange?: (value: string) => void;
  min?: number;
  max?: number;
  step?: number;
  disabled?: boolean;
}
export declare const NumberField: React.FC<NumberFieldProps>;`,
    prompt: `Labeled number field for inspector panels. \`onChange\` receives the raw input string — parse it yourself.

\`\`\`jsx
<NumberField label="hero.trust" value={trust} min={0} max={100} onChange={(v) => setTrust(Number(v))} />
\`\`\``,
  },

  SelectField: {
    dts: `import * as React from "react";
export interface SelectFieldOption { value: string | number; label: string }
export interface SelectFieldProps {
  label?: string;
  options: SelectFieldOption[];
  value?: string | number;
  onChange?: (value: string) => void;
  placeholder?: string;
  disabled?: boolean;
}
export declare const SelectField: React.FC<SelectFieldProps>;`,
    prompt: `Labeled select for inspector panels (flat options only — use \`Select\` for grouped menus).

\`\`\`jsx
<SelectField label="Speaker" value={voice} onChange={setVoice}
  options={[{ value: "mira", label: "Mira Chen" }, { value: "hero", label: "Hero" }]} />
\`\`\``,
  },

  ToggleField: {
    dts: `import * as React from "react";
export interface ToggleFieldProps {
  label?: string;
  checked?: boolean;
  onToggle?: () => void;
  disabled?: boolean;
}
export declare const ToggleField: React.FC<ToggleFieldProps>;`,
    prompt: `Labeled switch row (label left, switch right) for inspector panels. \`onToggle\` has no payload — flip your own state.

\`\`\`jsx
<ToggleField label="Snap to grid" checked={snap} onToggle={() => setSnap(!snap)} />
\`\`\``,
  },

  SliderField: {
    dts: `import * as React from "react";
export interface SliderFieldProps {
  label?: string;
  value?: number | string;
  onChange?: (value: string) => void;
  min?: number;
  max?: number;
  step?: number;
  format?: (value: number) => string;
  disabled?: boolean;
}
export declare const SliderField: React.FC<SliderFieldProps>;`,
    prompt: `Labeled slider with a live value readout; \`format\` renders the readout (e.g. percentages). \`onChange\` receives a string.

\`\`\`jsx
<SliderField label="Canvas zoom" value={zoom} min={25} max={200} format={(v) => \`\${v}%\`}
  onChange={(v) => setZoom(Number(v))} />
\`\`\``,
  },

  ButtonGroupField: {
    dts: `import * as React from "react";
export interface ButtonGroupOption { value: string | number; label?: string }
export interface ButtonGroupFieldProps {
  label?: string;
  options: ButtonGroupOption[];
  value?: string | number;
  onChange?: (value: string | number) => void;
  disabled?: boolean;
}
export declare const ButtonGroupField: React.FC<ButtonGroupFieldProps>;`,
    prompt: `Labeled segmented button row for small exclusive choices (image fit, alignment).

\`\`\`jsx
<ButtonGroupField label="Image fit" value={fit} onChange={setFit}
  options={[{ value: "cover", label: "Cover" }, { value: "contain", label: "Contain" }]} />
\`\`\``,
  },

  BooleanToggle: {
    dts: `import * as React from "react";
export interface BooleanToggleProps {
  value: boolean | null;
  onChange?: (value: boolean | null) => void;
  mode?: "two_state" | "tri_state";
  trueLabel: string;
  falseLabel: string;
  neutralLabel?: string;
  disabled?: boolean;
}
export declare const BooleanToggle: React.FC<BooleanToggleProps>;`,
    prompt: `Storyarn's boolean variable control. \`tri_state\` cycles true → false → null (\`neutralLabel\`, default "—") — used for unset variables.

\`\`\`jsx
<BooleanToggle value={visible} trueLabel="Visible" falseLabel="Hidden" onChange={setVisible} />
\`\`\``,
  },

  PasswordInput: {
    dts: `import * as React from "react";
export interface PasswordInputProps {
  value?: string | number;
  defaultValue?: string | number;
  onChange?: (value: string | number) => void;
  id?: string;
  className?: string;
}
export declare const PasswordInput: React.FC<PasswordInputProps>;`,
    prompt: `Password/secret input with a built-in show/hide toggle — used for provider API keys.

\`\`\`jsx
<PasswordInput value={apiKey} onChange={setApiKey} />
\`\`\``,
  },

  EditableText: {
    dts: `import * as React from "react";
export interface EditableTextProps {
  value?: string;
  onChange?: (value: string) => void;
  onSave?: (value: string) => void;
  placeholder?: string;
  tag?: string;
  displayClass?: string;
  inputClass?: string;
  disabled?: boolean;
}
export declare const EditableText: React.FC<EditableTextProps>;`,
    prompt: `Click-to-edit inline text — titles and names that edit in place. \`displayClass\` styles the resting state; \`onSave\` fires on commit (blur/Enter).

\`\`\`jsx
<EditableText value={title} onChange={setTitle} displayClass="text-lg font-semibold" />
\`\`\``,
  },

  ColorPicker: {
    dts: `import * as React from "react";
export interface ColorPickerProps {
  value?: string;
  onChange?: (color: string) => void;
  presets?: string[];
  disabled?: boolean;
}
export declare const ColorPicker: React.FC<ColorPickerProps>;`,
    prompt: `Swatch color picker in a popover (16 presets by default). \`value\` is a hex string.

\`\`\`jsx
<ColorPicker value={color} onChange={setColor} />
\`\`\``,
  },

  Dialog: {
    dts: `import * as React from "react";
export interface DialogProps {
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
  title?: string;
  description?: string;
  footer?: React.ReactNode;
  contentClass?: string;
  children?: React.ReactNode;
}
export declare const Dialog: React.FC<DialogProps>;`,
    prompt: `Modal dialog: children = body, \`footer\` = action row. For confirm/cancel flows use \`ConfirmDialog\` instead — it is the real product confirmation dialog.

\`\`\`jsx
<Dialog open={open} onOpenChange={setOpen} title="Duplicate flow"
  footer={<><Button variant="ghost" onClick={close}>Cancel</Button><Button onClick={dup}>Duplicate</Button></>}>
  <Label htmlFor="n">New name</Label><Input id="n" value={name} onChange={setName} />
</Dialog>
\`\`\``,
  },

  Sheet: {
    dts: `import * as React from "react";
export interface SheetProps {
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
  side?: "top" | "right" | "bottom" | "left";
  title?: string;
  description?: string;
  footer?: React.ReactNode;
  contentClass?: string;
  children?: React.ReactNode;
}
export declare const Sheet: React.FC<SheetProps>;`,
    prompt: `Slide-in side panel (default right) — node properties, settings drawers. Children render below the header; pad them with \`px-4\` or an inline style.

\`\`\`jsx
<Sheet open={open} onOpenChange={setOpen} title="Dialogue node" description="mira_intro · The Vault">
  …fields…
</Sheet>
\`\`\``,
  },

  Popover: {
    dts: `import * as React from "react";
export interface PopoverProps {
  content?: React.ReactNode;
  side?: "top" | "right" | "bottom" | "left";
  align?: "start" | "center" | "end";
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
  contentClass?: string;
  children?: React.ReactNode;
}
export declare const Popover: React.FC<PopoverProps>;`,
    prompt: `Floating panel anchored to its trigger. Children = the trigger; \`content\` = the panel. Leave \`open\` unset for click-to-open; set it to force visibility in a static mockup.

\`\`\`jsx
<Popover content={<ColorGrid />} side="bottom" align="start">
  <Button variant="outline">Color</Button>
</Popover>
\`\`\``,
  },

  Tooltip: {
    dts: `import * as React from "react";
export interface TooltipProps {
  content: string;
  side?: "top" | "right" | "bottom" | "left";
  open?: boolean;
  children?: React.ReactNode;
}
export declare const Tooltip: React.FC<TooltipProps>;`,
    prompt: `Hover tooltip (plain text). Children = the trigger. Set \`open\` to force it visible in a static mockup.

\`\`\`jsx
<Tooltip content="Validate flow health"><Button size="icon">✓</Button></Tooltip>
\`\`\``,
  },

  DropdownMenu: {
    dts: `import * as React from "react";
export interface DropdownItem {
  label?: string;
  value?: string;
  type?: "item" | "label" | "separator";
  shortcut?: string;
  disabled?: boolean;
  destructive?: boolean;
}
export interface DropdownMenuProps {
  items?: DropdownItem[];
  side?: "top" | "right" | "bottom" | "left";
  align?: "start" | "center" | "end";
  onSelect?: (value: string) => void;
  children?: React.ReactNode;
}
export declare const DropdownMenu: React.FC<DropdownMenuProps>;`,
    prompt: `Action menu. Children = the trigger. \`onSelect\` receives the item's \`value\` (falls back to its label). Mark dangerous actions \`destructive: true\`.

\`\`\`jsx
<DropdownMenu onSelect={handle} items={[
  { type: "label", label: "Flow actions" },
  { label: "Rename", shortcut: "⌘R" },
  { type: "separator" },
  { label: "Move to trash", destructive: true },
]}>
  <Button variant="outline">Actions</Button>
</DropdownMenu>
\`\`\``,
  },

  Table: {
    dts: `import * as React from "react";
export interface TableColumn { key: string; label: string; class?: string }
export interface TableProps {
  columns?: TableColumn[];
  rows?: Record<string, unknown>[];
  caption?: string;
  emptyText?: string;
  className?: string;
}
export declare const Table: React.FC<TableProps>;`,
    prompt: `Data table driven by \`columns\` + \`rows\` (cell values render as text; use \`class: "text-right"\` for numeric columns). For fully custom cells, build your own grid with the primitives.

\`\`\`jsx
<Table columns={[{ key: "name", label: "Flow" }, { key: "nodes", label: "Nodes", class: "text-right" }]}
  rows={[{ name: "The Vault", nodes: 24 }]} />
\`\`\``,
  },

  ConfirmDialog: {
    dts: `import * as React from "react";
export interface ConfirmDialogProps {
  open: boolean;
  onOpenChange?: (open: boolean) => void;
  title: string;
  description?: string;
  confirmText?: string;
  cancelText?: string;
  variant?: "default" | "destructive" | "warning";
  pending?: boolean;
  pendingText?: string;
  closeOnConfirm?: boolean;
  error?: string;
  onConfirm?: () => void;
  onCancel?: () => void;
}
export declare const ConfirmDialog: React.FC<ConfirmDialogProps>;`,
    prompt: `THE product confirmation dialog — Storyarn never uses browser confirm(). Use it for every destructive or irreversible action; \`variant="destructive"\` for deletes. \`pending\` shows \`pendingText\` and blocks dismissal.

\`\`\`jsx
<ConfirmDialog open={open} onOpenChange={setOpen} variant="destructive"
  title="Delete this flow?" description="Moved to the project trash."
  confirmText="Delete" onConfirm={del} />
\`\`\``,
  },

  SaveIndicator: {
    dts: `import * as React from "react";
export interface SaveIndicatorProps {
  status?: "idle" | "saving" | "saved";
}
export declare const SaveIndicator: React.FC<SaveIndicatorProps>;`,
    prompt: `Autosave status chip shown in editor toolbars. \`idle\` renders nothing; show \`saving\` then \`saved\`.

\`\`\`jsx
<SaveIndicator status="saved" />
\`\`\``,
  },
};
