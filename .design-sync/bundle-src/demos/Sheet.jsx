const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [open, setOpen] = React.useState(true);
  return (
    <div style={{ minHeight: 380 }}>
      <DS.Button variant="outline" onClick={() => setOpen(true)}>
        Node properties
      </DS.Button>
      <DS.Sheet
        open={open}
        onOpenChange={setOpen}
        title="Dialogue node"
        description="mira_intro · The Vault"
      >
        <div style={{ display: "flex", flexDirection: "column", gap: 12, padding: "0 16px" }}>
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            <DS.Label>Speaker</DS.Label>
            <DS.Input value="Mira Chen" onChange={() => {}} />
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            <DS.Label>Text</DS.Label>
            <DS.Textarea
              rows={3}
              value="The vault was already open when we got here."
              onChange={() => {}}
            />
          </div>
        </div>
      </DS.Sheet>
    </div>
  );
}

window.__dsDemo = Demo;
