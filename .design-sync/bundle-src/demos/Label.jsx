const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 6, maxWidth: 280 }}>
      <DS.Label htmlFor="sheet-name">Sheet name</DS.Label>
      <DS.Input id="sheet-name" placeholder="e.g. Hero" />
    </div>
  );
}

window.__dsDemo = Demo;
