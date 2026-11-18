import test from "node:test";
import assert from "node:assert/strict";
import { nextStatus } from "../server/workflow-config.js";
import { handlerIds } from "../server/flow-handlers.js";

const steps = [
  { code: "CREATE", action: null, status: null, enabled: 1, next_code: "SUBMITTER_LEADER", fail_code: null },
  { code: "SUBMITTER_LEADER", action: "submitter_approve", status: "PENDING_SUBMITTER_LEADER_APPROVAL", enabled: 1, next_code: "ASSIGN", fail_code: null },
  { code: "ASSIGN", action: "assign", status: "PENDING_ASSIGNMENT", enabled: 1, next_code: "SKIP", fail_code: null },
  { code: "SKIP", action: "custom_skip", status: "STATUS_SKIP", enabled: 0, next_code: "EXECUTE", fail_code: null },
  { code: "EXECUTE", action: "complete", status: "IN_PROGRESS", enabled: 1, next_code: "VERIFY", fail_code: null },
  { code: "VERIFY", action: "verify_ok", status: "PENDING_VERIFICATION", enabled: 1, next_code: "DONE", fail_code: "EXECUTE" },
  { code: "DONE", action: null, status: "COMPLETED", enabled: 1, next_code: null, fail_code: null },
  { code: "CUSTOM", action: "custom_review", status: "STATUS_CUSTOM_REVIEW", enabled: 1, next_code: "DONE", fail_code: "EXECUTE" }
];

test("pass follows next_code and skips disabled", () => {
  assert.equal(nextStatus(steps, "PENDING_ASSIGNMENT", "assign"), "IN_PROGRESS");
});

test("fail follows fail_code", () => {
  assert.equal(nextStatus(steps, "PENDING_VERIFICATION", "verify_fail"), "IN_PROGRESS");
  assert.equal(nextStatus(steps, "STATUS_CUSTOM_REVIEW", "custom_review__fail"), "IN_PROGRESS");
  assert.equal(nextStatus(steps, "STATUS_CUSTOM_REVIEW", "custom_review"), "COMPLETED");
});

test("fail without config is rejected", () => {
  assert.throws(() => nextStatus(steps, "PENDING_SUBMITTER_LEADER_APPROVAL", "submitter_approve__fail"), /没有配置不通过/);
});

test("handlers follow actor", () => {
  const ticket = { submitter_id: 1, verifier_id: 1, assignee_id: 4, role_id: 9 };
  const people = { submitterLeader: 2, executorLeader: 3, groupLeaders: [8, 9] };
  assert.deepEqual(handlerIds(ticket, { actor: "submitter_leader" }, people), [2]);
  assert.deepEqual(handlerIds(ticket, { actor: "executor_leader" }, people), [3]);
  assert.deepEqual(handlerIds({ ...ticket, assignee_id: null }, { actor: "executor_leader" }, { ...people, executorLeader: 0 }), [8, 9]);
  assert.deepEqual(handlerIds(ticket, { actor: "assignee" }, people), [4]);
});
