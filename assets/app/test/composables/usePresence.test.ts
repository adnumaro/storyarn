import { reactive } from "vue";
import { usePresence, type OnlineUser } from "@composables/usePresence";

function makeProps(users: OnlineUser[] = []) {
  return reactive({ onlineUsers: users });
}

describe("usePresence", () => {
  describe("onlineUsers", () => {
    it("returns the list from props", () => {
      const users: OnlineUser[] = [
        { id: 1, color: "#ff0000" },
        { id: 2, color: "#00ff00" },
      ];
      const props = makeProps(users);
      const { onlineUsers } = usePresence(props);

      expect(onlineUsers.value).toEqual(users);
    });

    it("defaults to empty array when onlineUsers is undefined", () => {
      const props = reactive({});
      const { onlineUsers } = usePresence(props);

      expect(onlineUsers.value).toEqual([]);
    });

    it("reacts to prop changes", () => {
      const props = makeProps([]);
      const { onlineUsers } = usePresence(props);

      expect(onlineUsers.value).toHaveLength(0);

      props.onlineUsers = [{ id: 1, color: "#abc" }];
      expect(onlineUsers.value).toHaveLength(1);
    });
  });

  describe("isUserOnline", () => {
    it("returns true for a user in the list", () => {
      const props = makeProps([
        { id: 1, color: "#ff0000" },
        { id: 2, color: "#00ff00" },
      ]);
      const { isUserOnline } = usePresence(props);

      expect(isUserOnline(1)).toBe(true);
      expect(isUserOnline(2)).toBe(true);
    });

    it("returns false for a user not in the list", () => {
      const props = makeProps([{ id: 1, color: "#ff0000" }]);
      const { isUserOnline } = usePresence(props);

      expect(isUserOnline(99)).toBe(false);
    });

    it("returns false when list is empty", () => {
      const props = makeProps([]);
      const { isUserOnline } = usePresence(props);

      expect(isUserOnline(1)).toBe(false);
    });

    it("reacts to users joining", () => {
      const props = makeProps([]);
      const { isUserOnline } = usePresence(props);

      expect(isUserOnline(5)).toBe(false);

      props.onlineUsers = [{ id: 5, color: "#abc" }];
      expect(isUserOnline(5)).toBe(true);
    });
  });

  describe("userColor", () => {
    it("returns the color for an online user", () => {
      const props = makeProps([
        { id: 1, color: "#ff0000" },
        { id: 2, color: "#00ff00" },
      ]);
      const { userColor } = usePresence(props);

      expect(userColor(1)).toBe("#ff0000");
      expect(userColor(2)).toBe("#00ff00");
    });

    it("returns fallback #888 for unknown user", () => {
      const props = makeProps([{ id: 1, color: "#ff0000" }]);
      const { userColor } = usePresence(props);

      expect(userColor(99)).toBe("#888");
    });

    it("returns fallback #888 when list is empty", () => {
      const props = makeProps([]);
      const { userColor } = usePresence(props);

      expect(userColor(1)).toBe("#888");
    });

    it("reacts to color changes", () => {
      const props = makeProps([{ id: 1, color: "#aaa" }]);
      const { userColor } = usePresence(props);

      expect(userColor(1)).toBe("#aaa");

      props.onlineUsers = [{ id: 1, color: "#bbb" }];
      expect(userColor(1)).toBe("#bbb");
    });
  });
});
