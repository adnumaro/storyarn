const DS = window.Storyarn_e287ac;

function Demo() {
  return (
    <div style={{ minHeight: 90, display: "flex", alignItems: "flex-end", paddingBottom: 12 }}>
      <DS.Tooltip content="Validate flow health" open side="top">
        <DS.Button variant="outline" size="sm">
          Health check
        </DS.Button>
      </DS.Tooltip>
    </div>
  );
}

window.__dsDemo = Demo;
