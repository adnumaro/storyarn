const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [open, setOpen] = React.useState(true);
  const [name, setName] = React.useState("The Vault II");
  return (
    <div style={{ minHeight: 320 }}>
      <DS.Button onClick={() => setOpen(true)}>Duplicate flow</DS.Button>
      <DS.Dialog
        open={open}
        onOpenChange={setOpen}
        title="Duplicate flow"
        description="Creates a copy with all nodes and connections."
        footer={
          <>
            <DS.Button variant="ghost" onClick={() => setOpen(false)}>
              Cancel
            </DS.Button>
            <DS.Button onClick={() => setOpen(false)}>Duplicate</DS.Button>
          </>
        }
      >
        <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
          <DS.Label htmlFor="copy-name">New name</DS.Label>
          <DS.Input id="copy-name" value={name} onChange={setName} />
        </div>
      </DS.Dialog>
    </div>
  );
}

window.__dsDemo = Demo;
