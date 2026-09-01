const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [snap, setSnap] = React.useState(true);
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12, maxWidth: 240 }}>
      <DS.ToggleField label="Snap to grid" checked={snap} onToggle={() => setSnap(!snap)} />
      <DS.ToggleField label="Show minimap" checked={false} />
      <DS.ToggleField label="Beta features" checked disabled />
    </div>
  );
}

window.__dsDemo = Demo;
