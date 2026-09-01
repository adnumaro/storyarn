const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const sheets = [
    "Hero", "Mira Chen", "The Warden", "Vault Guard", "Merchant",
    "Old Cartographer", "Ferryman", "Archivist", "Smuggler", "Night Clerk",
  ];
  return (
    <DS.ScrollArea className="h-40 w-56 rounded-md border">
      <div style={{ padding: 12 }}>
        <div
          style={{
            fontSize: 11,
            fontWeight: 600,
            color: "hsl(var(--muted-foreground))",
            marginBottom: 8,
            textTransform: "uppercase",
            letterSpacing: "0.05em",
          }}
        >
          Sheets
        </div>
        {sheets.map((name) => (
          <div key={name} style={{ fontSize: 13, padding: "5px 0" }}>
            {name}
          </div>
        ))}
      </div>
    </DS.ScrollArea>
  );
}

window.__dsDemo = Demo;
