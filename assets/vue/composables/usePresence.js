/**
 * Collaboration presence tracking.
 *
 * Receives online users via LiveView props and provides helper methods.
 *
 * Usage:
 *   const { onlineUsers, isUserOnline } = usePresence(props)
 */

import { computed } from "vue"

export function usePresence(props) {
  const onlineUsers = computed(() => props.onlineUsers || [])

  function isUserOnline(userId) {
    return onlineUsers.value.some((u) => u.id === userId)
  }

  function userColor(userId) {
    const user = onlineUsers.value.find((u) => u.id === userId)
    return user?.color || "#888"
  }

  return { onlineUsers, isUserOnline, userColor }
}
