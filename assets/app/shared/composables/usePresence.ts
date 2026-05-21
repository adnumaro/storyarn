/**
 * Collaboration presence tracking.
 *
 * Receives online users via LiveView props and provides helper methods.
 *
 * Usage:
 *   const { onlineUsers, isUserOnline } = usePresence(props)
 */

import { type ComputedRef, computed } from "vue";

export interface OnlineUser {
  id: number;
  color: string;
  [key: string]: unknown;
}

interface PresenceProps {
  onlineUsers?: OnlineUser[];
  [key: string]: unknown;
}

interface UsePresenceReturn {
  onlineUsers: ComputedRef<OnlineUser[]>;
  isUserOnline: (userId: number) => boolean;
  userColor: (userId: number) => string;
}

export function usePresence(props: PresenceProps): UsePresenceReturn {
  const onlineUsers = computed<OnlineUser[]>(() => props.onlineUsers || []);

  function isUserOnline(userId: number): boolean {
    return onlineUsers.value.some((u) => u.id === userId);
  }

  function userColor(userId: number): string {
    const user = onlineUsers.value.find((u) => u.id === userId);
    return user?.color || "#888";
  }

  return { onlineUsers, isUserOnline, userColor };
}
