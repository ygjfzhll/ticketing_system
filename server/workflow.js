export const STATUS = Object.freeze({
  SUBMITTER_APPROVAL: 'PENDING_SUBMITTER_LEADER_APPROVAL',
  APPROVAL: 'PENDING_LEADER_APPROVAL',
  ASSIGNMENT: 'PENDING_ASSIGNMENT',
  IN_PROGRESS: 'IN_PROGRESS',
  VERIFY: 'PENDING_VERIFICATION',
  REWORK: 'REWORK_REQUIRED',
  DONE: 'COMPLETED',
  CLOSED: 'CLOSED',
  REJECTED: 'REJECTED'
});

export const transitions = {
  submitter_approve: { from: [STATUS.SUBMITTER_APPROVAL], to: STATUS.APPROVAL },
  approve: { from: [STATUS.APPROVAL], to: STATUS.ASSIGNMENT },
  assign: { from: [STATUS.ASSIGNMENT], to: STATUS.IN_PROGRESS },
  complete: { from: [STATUS.IN_PROGRESS, STATUS.REWORK], to: STATUS.VERIFY },
  verify_ok: { from: [STATUS.VERIFY], to: STATUS.DONE },
  verify_fail: { from: [STATUS.VERIFY], to: STATUS.REWORK },
  withdraw: {
    from: [STATUS.SUBMITTER_APPROVAL, STATUS.APPROVAL, STATUS.ASSIGNMENT],
    to: STATUS.REJECTED
  },
  close: { from: [STATUS.DONE], to: STATUS.CLOSED },
  reassign: { from: [STATUS.IN_PROGRESS, STATUS.REWORK], to: STATUS.IN_PROGRESS }
};

export function assertTransition(status, action) {
  const rule = transitions[action];
  if (!rule || !rule.from.includes(status)) {
    throw Object.assign(new Error('当前节点不允许执行该操作'), { statusCode: 409 });
  }
  return rule.to;
}
