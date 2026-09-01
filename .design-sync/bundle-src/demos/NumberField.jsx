const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [trust, setTrust] = React.useState(65);
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12, maxWidth: 220 }}>
      <DS.NumberField label="hero.trust" value={trust} min={0} max={100} onChange={setTrust} />
      <DS.NumberField label="Retry limit" value={3} min={0} step={1} />
    </div>
  );
}

window.__dsDemo = Demo;
