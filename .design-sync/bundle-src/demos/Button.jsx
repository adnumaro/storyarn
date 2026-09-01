const DS = window.Storyarn_e287ac;

function Demo() {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
      <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
        <DS.Button>Save changes</DS.Button>
        <DS.Button variant="secondary">Duplicate</DS.Button>
        <DS.Button variant="outline">Preview</DS.Button>
        <DS.Button variant="ghost">Cancel</DS.Button>
        <DS.Button variant="link">Learn more</DS.Button>
        <DS.Button variant="destructive">Delete flow</DS.Button>
      </div>
      <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
        <DS.Button size="xs">Extra small</DS.Button>
        <DS.Button size="sm">Small</DS.Button>
        <DS.Button size="default">Default</DS.Button>
        <DS.Button size="lg">Large</DS.Button>
        <DS.Button size="icon" aria-label="Add node">
          +
        </DS.Button>
      </div>
    </div>
  );
}

window.__dsDemo = Demo;
