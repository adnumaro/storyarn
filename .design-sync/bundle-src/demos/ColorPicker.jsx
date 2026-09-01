const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [color, setColor] = React.useState("#14b8a6");
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 12, minHeight: 60 }}>
      <DS.ColorPicker value={color} onChange={setColor} />
      <span style={{ fontSize: 12, color: "hsl(var(--muted-foreground))" }}>{color}</span>
    </div>
  );
}

window.__dsDemo = Demo;
