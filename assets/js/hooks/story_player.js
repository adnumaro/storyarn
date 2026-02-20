/**
 * StoryPlayer hook — handles keyboard shortcuts for the story player.
 *
 * Space/Enter/→  → continue
 * ←/Backspace    → go back
 * Escape         → exit player
 * P              → toggle player/analysis mode
 * 1–9            → choose response by number
 */
export const StoryPlayer = {
  mounted() {
    this.handleKeydown = (e) => {
      // Ignore when focus is in an input or textarea
      if (
        e.target.tagName === "INPUT" ||
        e.target.tagName === "TEXTAREA" ||
        e.target.isContentEditable
      ) {
        return;
      }

      switch (e.key) {
        case " ":
        case "Enter":
        case "ArrowRight":
          e.preventDefault();
          this.pushEvent("continue", {});
          break;
        case "ArrowLeft":
        case "Backspace":
          e.preventDefault();
          this.pushEvent("go_back", {});
          break;
        case "Escape":
          e.preventDefault();
          this.pushEvent("exit_player", {});
          break;
        case "p":
        case "P":
          this.pushEvent("toggle_mode", {});
          break;
        default:
          if (e.key >= "1" && e.key <= "9") {
            e.preventDefault();
            this.pushEvent("choose_response_by_number", {
              number: parseInt(e.key, 10),
            });
          }
      }
    };

    document.addEventListener("keydown", this.handleKeydown);
  },

  destroyed() {
    document.removeEventListener("keydown", this.handleKeydown);
  },
};
