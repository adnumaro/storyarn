const DS = window.Storyarn_e287ac;

function Demo() {
  return (
    <div style={{ minHeight: 300 }}>
      <DS.DropdownMenu
        defaultOpen
        align="start"
        items={[
          { type: "label", label: "Flow actions" },
          { label: "Rename", shortcut: "⌘R" },
          { label: "Duplicate", shortcut: "⌘D" },
          { label: "Export…" },
          { type: "separator" },
          { label: "Move to trash", destructive: true },
        ]}
        onSelect={(v) => console.log("selected", v)}
      >
        <DS.Button variant="outline">Actions</DS.Button>
      </DS.DropdownMenu>
    </div>
  );
}

window.__dsDemo = Demo;
