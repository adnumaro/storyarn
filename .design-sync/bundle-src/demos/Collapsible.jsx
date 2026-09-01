const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [open, setOpen] = React.useState(true);
  return (
    <div style={{ maxWidth: 280 }}>
      <DS.Collapsible trigger="Act I — The Vault" open={open} onOpenChange={setOpen}>
        <div style={{ padding: "4px 8px", display: "flex", flexDirection: "column", gap: 4 }}>
          {["Opening", "Mira's warning", "The sequence", "Aftermath"].map((s) => (
            <div key={s} style={{ fontSize: 13, padding: "3px 8px" }}>
              {s}
            </div>
          ))}
        </div>
      </DS.Collapsible>
      <DS.Collapsible trigger="Act II — The Crossing" open={false} />
    </div>
  );
}

window.__dsDemo = Demo;
