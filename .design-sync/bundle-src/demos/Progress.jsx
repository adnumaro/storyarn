const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const label = { fontSize: 12, color: "hsl(var(--muted-foreground))", marginBottom: 4 };
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 16, maxWidth: 280 }}>
      <div>
        <div style={label}>Translation · 30%</div>
        <DS.Progress value={30} />
      </div>
      <div>
        <div style={label}>Export · 65%</div>
        <DS.Progress value={65} />
      </div>
      <div>
        <div style={label}>Upload · done</div>
        <DS.Progress value={100} />
      </div>
    </div>
  );
}

window.__dsDemo = Demo;
