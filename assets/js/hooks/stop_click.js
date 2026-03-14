export const StopClick = {
  mounted() {
    this.handleClick = (event) => {
      if (this.el.hasAttribute("data-prevent-default")) {
        event.preventDefault();
      }

      if (this.el.hasAttribute("data-stop-propagation")) {
        event.stopPropagation();
      }
    };

    this.el.addEventListener("click", this.handleClick);
  },

  destroyed() {
    this.el.removeEventListener("click", this.handleClick);
  },
};
