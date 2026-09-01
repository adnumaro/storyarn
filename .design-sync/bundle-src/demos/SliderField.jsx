const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [zoom, setZoom] = React.useState(80);
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 16, maxWidth: 240 }}>
      <DS.SliderField
        label="Canvas zoom"
        value={zoom}
        min={25}
        max={200}
        step={5}
        format={(v) => `${v}%`}
        onChange={(v) => setZoom(Number(v))}
      />
      <DS.SliderField label="Ambient volume" value={35} min={0} max={100} />
    </div>
  );
}

window.__dsDemo = Demo;
