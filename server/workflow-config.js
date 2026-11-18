import { pool } from "./db.js";
export const DEFAULT_STEPS = [
  ["CREATE","提交工单","员工提交问题","submitter",null,null,1,1,1],
  ["SUBMITTER_LEADER","提交人审批","提交人的上级审批，同意继续，不同意退回提交人","submitter_leader","submitter_approve","PENDING_SUBMITTER_LEADER_APPROVAL",2,1,0],
  ["EXEC_LEADER","执行审批","执行人的上级审批，同意继续，不同意退回提交人","executor_leader","approve","PENDING_LEADER_APPROVAL",3,1,0],
  ["ASSIGN","指派执行者","业务组 Leader 选择执行人","group_leader","assign","PENDING_ASSIGNMENT",4,1,0],
  ["EXECUTE","执行处理","执行人处理并反馈","assignee","complete","IN_PROGRESS",5,1,1],
  ["VERIFY","验证环节","提交人验证环节是否可用","submitter","verify_ok","PENDING_VERIFICATION",6,1,1],
  ["DONE","验证通过","验证通过后工单结束","submitter",null,"COMPLETED",7,1,1]
];
export async function ensureWorkflow() {
  await pool.query("CREATE TABLE IF NOT EXISTS workflow_steps (id INT PRIMARY KEY AUTO_INCREMENT, code VARCHAR(40) NOT NULL UNIQUE, name VARCHAR(80) NOT NULL, detail VARCHAR(160) NOT NULL DEFAULT '', actor VARCHAR(40) NOT NULL, action VARCHAR(40) NULL, status VARCHAR(60) NULL, sort_order INT NOT NULL, enabled TINYINT(1) NOT NULL DEFAULT 1, locked TINYINT(1) NOT NULL DEFAULT 0, next_code VARCHAR(40) NULL, pos_x INT NULL, pos_y INT NULL)");
  for (const column of ["next_code VARCHAR(40) NULL","fail_code VARCHAR(40) NULL","pos_x INT NULL","pos_y INT NULL"]) {
    const name = column.split(" ")[0];
    await pool.query("ALTER TABLE workflow_steps ADD COLUMN " + column).catch(error => { if (error.code !== "ER_DUP_FIELDNAME") throw error; });
  }
  await pool.query("UPDATE workflow_steps SET fail_code='EXECUTE' WHERE code='VERIFY' AND (fail_code IS NULL OR fail_code='')");
  const [linked] = await pool.query("SELECT code FROM workflow_steps WHERE next_code IS NOT NULL LIMIT 1");
  if (!linked.length) {
    const [rows] = await pool.query("SELECT code FROM workflow_steps ORDER BY sort_order, id");
    for (let i = 0; i < rows.length; i++) {
      await pool.query("UPDATE workflow_steps SET next_code=?, pos_x=?, pos_y=? WHERE code=?", [rows[i+1]?rows[i+1].code:null, 40+i*210, 70, rows[i].code]);
    }
  }
  const [[count]] = await pool.query("SELECT COUNT(*) c FROM workflow_steps");
  if (!count.c) {
    for (const step of DEFAULT_STEPS) {
      await pool.query("INSERT INTO workflow_steps(code,name,detail,actor,action,status,sort_order,enabled,locked) VALUES(?,?,?,?,?,?,?,?,?)", step);
    }
  }
}
export async function listSteps() {
  const [rows] = await pool.query("SELECT code,name,detail,actor,action,status,sort_order,enabled,locked,next_code,fail_code,pos_x,pos_y FROM workflow_steps ORDER BY sort_order, id");
  return rows;
}
export async function saveSteps(steps) {
  const current = await listSteps();
  const byCode = new Map(current.map(step => [step.code, step]));
  const incoming = new Set(steps.map(step => step.code));
  for (const old of current) {
    if (String(old.code).startsWith("CUSTOM_") && !incoming.has(old.code)) await pool.query("DELETE FROM workflow_steps WHERE code=?", [old.code]);
  }
  for (const step of steps) {
    const old = byCode.get(step.code);
    const enabled = old && old.locked ? 1 : (step.enabled ? 1 : 0);
    const values = [String(step.name||old?.name||"新节点").slice(0,80), String(step.detail||"").slice(0,160), String(step.actor||"group_leader"), Number(step.sort_order)||1, enabled, step.next_code||null, step.fail_code||null, Number(step.pos_x)||40, Number(step.pos_y)||70];
    if (!old) {
      if (!String(step.code).startsWith("CUSTOM_")) continue;
      await pool.query("INSERT INTO workflow_steps(code,name,detail,actor,action,status,sort_order,enabled,locked,next_code,fail_code,pos_x,pos_y) VALUES(?,?,?,?,?,?,?,?,0,?,?,?,?)", [step.code, values[0], values[1], values[2], step.action||step.code, step.status||("STATUS_"+step.code), values[3], values[4], values[5], values[6], values[7], values[8]]);
    } else {
      await pool.query("UPDATE workflow_steps SET name=?, detail=?, actor=?, sort_order=?, enabled=?, next_code=?, fail_code=?, pos_x=?, pos_y=? WHERE code=?", [...values, step.code]);
    }
  }
  return listSteps();
}
export function orderedSteps(steps) {
  const list = [...steps].sort((a,b) => a.sort_order - b.sort_order);
  if (!list.some(step => step.next_code)) return list;
  const byCode = new Map(list.map(step => [step.code, step]));
  const chain = [];
  const seen = new Set();
  let cursor = byCode.get("CREATE") || list[0];
  while (cursor && !seen.has(cursor.code)) {
    seen.add(cursor.code);
    chain.push(cursor);
    cursor = cursor.next_code ? byCode.get(cursor.next_code) : null;
  }
  list.filter(step => !seen.has(step.code)).forEach(step => chain.push(step));
  return chain;
}
function reject(message) {
  const error = new Error(message);
  error.statusCode = 409;
  throw error;
}
function enabledTarget(steps, code, seen) {
  const byCode = new Map(steps.map(step => [step.code, step]));
  let cursor = code ? byCode.get(code) : null;
  while (cursor && !seen.has(cursor.code)) {
    seen.add(cursor.code);
    if (Number(cursor.enabled) === 1 && cursor.status) return cursor.status;
    cursor = cursor.next_code ? byCode.get(cursor.next_code) : null;
  }
  return null;
}
export function nextStatus(steps, status, action) {
  if (action === "withdraw") return "REJECTED";
  if (action === "close") return "CLOSED";
  if (action === "reassign") return status;
  if (action === "suspend") return "SUSPENDED";
  if (action === "resume") return "IN_PROGRESS";
  if (action === "resubmit") {
    const chain = orderedSteps(steps).filter(step => Number(step.enabled) === 1 && step.status);
    return chain[0] ? chain[0].status : "PENDING_SUBMITTER_LEADER_APPROVAL";
  }
  const fail = action === "verify_fail" || String(action).endsWith("__fail");
  const base = action === "verify_fail" ? "verify_ok" : fail ? String(action).slice(0, -6) : action;
  const current = steps.find(step => step.status === status && step.action === base);
  if (!current) reject("当前节点不允许执行该操作");
  if (fail) {
    const backToSubmitter = !current.fail_code && ["submitter_approve","approve"].includes(current.action);
    if (!current.fail_code && !backToSubmitter) reject("这个节点没有配置不通过后的去向");
    if (backToSubmitter || current.fail_code === "CREATE") return "RETURNED_TO_SUBMITTER";
    const targetStep = steps.find(step => step.code === current.fail_code);
    if (targetStep && !targetStep.status) return "RETURNED_TO_SUBMITTER";
    const target = enabledTarget(steps, current.fail_code, new Set([current.code]));
    if (!target) reject("不通过后的节点不存在或已停用");
    return target;
  }
  const skipped = enabledTarget(steps, current.next_code, new Set([current.code]));
  if (skipped) return skipped;
  const chain = orderedSteps(steps).filter(step => Number(step.enabled) === 1 && step.status);
  const index = chain.findIndex(step => step.code === current.code);
  if (index >= 0 && chain[index + 1]) return chain[index + 1].status;
  return "COMPLETED";
}
export function stepByStatus(steps, status) {
  return steps.find(step => step.status === status) || null;
}
