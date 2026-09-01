const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  return (
    <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
      <DS.Badge>dialogue</DS.Badge>
      <DS.Badge variant="secondary">draft</DS.Badge>
      <DS.Badge variant="outline">3 variables</DS.Badge>
      <DS.Badge variant="destructive">2 errors</DS.Badge>
    </div>
  );
}

window.__dsDemo = Demo;
