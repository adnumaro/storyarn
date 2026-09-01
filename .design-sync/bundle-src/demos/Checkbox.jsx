const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [checked, setChecked] = React.useState(true);
  const row = { display: "flex", alignItems: "center", gap: 10 };
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      <div style={row}>
        <DS.Checkbox checked={checked} onCheckedChange={setChecked} id="c1" />
        <DS.Label htmlFor="c1">Include dialogue nodes</DS.Label>
      </div>
      <div style={row}>
        <DS.Checkbox checked={false} id="c2" />
        <DS.Label htmlFor="c2">Include annotations</DS.Label>
      </div>
      <div style={row}>
        <DS.Checkbox checked="indeterminate" id="c3" />
        <DS.Label htmlFor="c3">Scenes (2 of 5)</DS.Label>
      </div>
    </div>
  );
}

window.__dsDemo = Demo;
