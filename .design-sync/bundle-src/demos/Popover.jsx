const DS = window.Storyarn_e287ac;

function Demo() {
  return (
    <div style={{ minHeight: 260, paddingTop: 8 }}>
      <DS.Popover
        open
        side="bottom"
        align="start"
        content={
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            <div style={{ fontSize: 13, fontWeight: 600 }}>Node color</div>
            <div style={{ display: "flex", gap: 6 }}>
              {["#2dd4bf", "#f59e0b", "#ef4444", "#8b5cf6", "#64748b"].map((c) => (
                <span key={c} style={{ width: 20, height: 20, borderRadius: 6, background: c }} />
              ))}
            </div>
            <div style={{ fontSize: 12, color: "hsl(var(--muted-foreground))" }}>
              Applies to selected nodes.
            </div>
          </div>
        }
      >
        <DS.Button variant="outline">Color</DS.Button>
      </DS.Popover>
    </div>
  );
}

window.__dsDemo = Demo;
