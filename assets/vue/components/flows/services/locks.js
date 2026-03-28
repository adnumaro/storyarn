/**
 * Lock state management for collaborative node editing.
 * Tracks which nodes are locked by other users.
 * Visual indicators are rendered by FlowLockIndicators.vue component.
 */

export function locks(handleEvent, currentUserId) {
	let nodeLocks = {};

	return {
		init(initialLocks = {}) {
			nodeLocks = initialLocks;
		},

		handleLocksUpdated(data) {
			nodeLocks = data.locks || {};
		},

		isNodeLocked(nodeId) {
			const lockInfo = nodeLocks[nodeId];
			return !!(lockInfo && lockInfo.user_id !== currentUserId);
		},

		getLocks() {
			return nodeLocks;
		},

		destroy() {},
	};
}
