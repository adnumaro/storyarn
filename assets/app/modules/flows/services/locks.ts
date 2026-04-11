/**
 * Lock state management for collaborative node editing.
 * Tracks which nodes are locked by other users.
 * Visual indicators are rendered by FlowLockIndicators.vue component.
 */

export interface LockInfo {
  user_id: number;
  [key: string]: unknown;
}

export interface LocksUpdatedData {
  locks: Record<string | number, LockInfo>;
}

export interface LocksHandler {
  init(initialLocks?: Record<string | number, LockInfo>): void;
  handleLocksUpdated(data: LocksUpdatedData): void;
  isNodeLocked(nodeId: string | number): boolean;
  getLocks(): Record<string | number, LockInfo>;
  destroy(): void;
}

export function locks(_handleEvent: unknown, currentUserId: number): LocksHandler {
  let nodeLocks: Record<string | number, LockInfo> = {};

  return {
    init(initialLocks: Record<string | number, LockInfo> = {}) {
      nodeLocks = initialLocks;
    },

    handleLocksUpdated(data: LocksUpdatedData) {
      nodeLocks = data.locks || {};
    },

    isNodeLocked(nodeId: string | number): boolean {
      const lockInfo = nodeLocks[nodeId];
      return lockInfo && lockInfo.user_id !== currentUserId;
    },

    getLocks(): Record<string | number, LockInfo> {
      return nodeLocks;
    },

    destroy() {},
  };
}
