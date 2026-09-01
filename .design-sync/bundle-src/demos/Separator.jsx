const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  return (
    <div style={{ maxWidth: 280 }}>
      <div style={{ fontSize: 13, fontWeight: 600 }}>The Vault</div>
      <div style={{ fontSize: 12, color: "hsl(var(--muted-foreground))" }}>
        Flow · 24 nodes
      </div>
      <DS.Separator className="my-3" />
      <div style={{ display: "flex", alignItems: "center", gap: 12, height: 20, fontSize: 12 }}>
        <span>Sheets</span>
        <DS.Separator orientation="vertical" />
        <span>Flows</span>
        <DS.Separator orientation="vertical" />
        <span>Scenes</span>
      </div>
    </div>
  );
}

window.__dsDemo = Demo;
