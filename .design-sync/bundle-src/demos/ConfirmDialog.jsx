const React = window.React;
const DS = window.Storyarn_e287ac;

function Demo() {
  const [open, setOpen] = React.useState(true);
  return (
    <div style={{ minHeight: 300 }}>
      <DS.Button variant="destructive" onClick={() => setOpen(true)}>
        Delete flow
      </DS.Button>
      <DS.ConfirmDialog
        open={open}
        onOpenChange={setOpen}
        title="Delete this flow?"
        description="“The Vault” and its 24 nodes will be moved to the project trash."
        confirmText="Delete"
        cancelText="Keep it"
        variant="destructive"
      />
    </div>
  );
}

window.__dsDemo = Demo;
