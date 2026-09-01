const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const cell = {
    display: "flex",
    flexDirection: "column",
    gap: 6,
    alignItems: "flex-start",
  };
  const label = { fontSize: 11, color: "hsl(var(--muted-foreground))" };
  return (
    <div style={{ display: "flex", gap: 32 }}>
      <div style={cell}>
        <span style={label}>saving</span>
        <DS.SaveIndicator status="saving" />
      </div>
      <div style={cell}>
        <span style={label}>saved</span>
        <DS.SaveIndicator status="saved" />
      </div>
      <div style={cell}>
        <span style={label}>idle (renders nothing)</span>
        <DS.SaveIndicator status="idle" />
      </div>
    </div>
  );
}

window.__dsDemo = Demo;
