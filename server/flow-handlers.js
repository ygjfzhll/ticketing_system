import { pool } from "./db.js";
import { listSteps, stepByStatus } from "./workflow-config.js";

export async function ensureFlowModel() {
  await pool.query("ALTER TABLE tickets MODIFY COLUMN status VARCHAR(60) NOT NULL DEFAULT 'PENDING_SUBMITTER_LEADER_APPROVAL'").catch(() => {});
  await pool.query("ALTER TABLE ticket_events MODIFY COLUMN from_status VARCHAR(60) NULL").catch(() => {});
  await pool.query("ALTER TABLE ticket_events MODIFY COLUMN to_status VARCHAR(60) NULL").catch(() => {});
  await pool.query("ALTER TABLE users ADD COLUMN manager_user_id BIGINT UNSIGNED NULL").catch(error => { if (error.code !== "ER_DUP_FIELDNAME") throw error; });
  await pool.query("ALTER TABLE users ADD COLUMN manager_open_id VARCHAR(128) NULL").catch(error => { if (error.code !== "ER_DUP_FIELDNAME") throw error; });
  await pool.query("ALTER TABLE tickets ADD COLUMN submitter_leader_id BIGINT UNSIGNED NULL").catch(error => { if (error.code !== "ER_DUP_FIELDNAME") throw error; });
  await pool.query("ALTER TABLE tickets ADD COLUMN exec_leader_id BIGINT UNSIGNED NULL").catch(error => { if (error.code !== "ER_DUP_FIELDNAME") throw error; });
  await pool.query("CREATE TABLE IF NOT EXISTS ticket_handlers (ticket_id BIGINT UNSIGNED NOT NULL, user_id BIGINT UNSIGNED NOT NULL, PRIMARY KEY (ticket_id, user_id), INDEX idx_ticket_handlers_user (user_id, ticket_id)) ENGINE=InnoDB");
}

export async function resolvePeople(db, ticket) {
  const [[role]] = await db.query("SELECT r.leader_user_id, r.backup_leader_user_id, (SELECT user_id FROM role_members WHERE role_id=r.id AND relation_type='LEADER' LIMIT 1) relation_leader_id, (SELECT user_id FROM role_members WHERE role_id=r.id AND relation_type='BACKUP_LEADER' LIMIT 1) relation_backup_id FROM roles r WHERE r.id=?", [ticket.role_id]);
  const groupLeaders = [...new Set([role?.leader_user_id, role?.backup_leader_user_id, role?.relation_leader_id, role?.relation_backup_id].filter(Boolean).map(Number))];
  const [[submitter]] = await db.query("SELECT manager_user_id FROM users WHERE id=?", [ticket.submitter_id]);
  const explicit = Number(ticket.submitter_leader_id) || 0;
  const manager = Number(submitter?.manager_user_id) || 0;
  const submitterLeader = explicit || (manager && manager !== Number(ticket.submitter_id) ? manager : 0);
  let executorLeader = 0;
  if (ticket.assignee_id) {
    const [[assignee]] = await db.query("SELECT manager_user_id FROM users WHERE id=?", [ticket.assignee_id]);
    const id = Number(assignee?.manager_user_id) || 0;
    executorLeader = id && id !== Number(ticket.assignee_id) ? id : 0;
  }
  return { groupLeaders, submitterLeader, executorLeader };
}

export function handlerIds(ticket, step, people) {
  if (!step) return [];
  if (step.action === "assign" || (step.actor === "assignee" && !Number(ticket.assignee_id))) {
    if (Number(ticket.exec_leader_id)) return [Number(ticket.exec_leader_id)];
    return [...new Set(people.groupLeaders.map(Number).filter(Boolean))];
  }
  const ids = {
    submitter: [ticket.submitter_id, ticket.verifier_id],
    submitter_leader: [people.submitterLeader],
    executor_leader: Number(ticket.exec_leader_id) ? [Number(ticket.exec_leader_id)] : people.groupLeaders,
    group_leader: people.groupLeaders,
    assignee: [ticket.assignee_id]
  }[step.actor] || [];
  return [...new Set(ids.map(Number).filter(Boolean))];
}

export async function refreshHandlers(db, ticketId) {
  const [[ticket]] = await db.query("SELECT * FROM tickets WHERE id=?", [ticketId]);
  if (!ticket) return [];
  const steps = await listSteps();
  const people = await resolvePeople(db, ticket);
  const ids = ticket.status === "RETURNED_TO_SUBMITTER" ? [Number(ticket.submitter_id)] : ticket.status === "SUSPENDED" ? [Number(ticket.assignee_id)].filter(Boolean) : handlerIds(ticket, stepByStatus(steps, ticket.status), people);
  await db.query("DELETE FROM ticket_handlers WHERE ticket_id=?", [ticketId]);
  for (const id of ids) await db.query("INSERT INTO ticket_handlers(ticket_id, user_id) VALUES(?,?)", [ticketId, id]);
  return ids;
}

export async function backfillHandlers() {
  const [rows] = await pool.query("SELECT id FROM tickets");
  for (const row of rows) await refreshHandlers(pool, row.id);
}

export async function resolveSubmitterLeader(db, userId) {
  const [[me]] = await db.query("SELECT manager_user_id FROM users WHERE id=?", [userId]);
  let leaderId = Number(me?.manager_user_id) || 0;
  if (!leaderId || leaderId === Number(userId)) {
    const [groups] = await db.query("SELECT r.leader_user_id, r.backup_leader_user_id FROM roles r WHERE (r.is_active=1 OR r.is_active IS NULL) AND (r.id IN (SELECT role_id FROM role_members WHERE user_id=?) OR r.leader_user_id=? OR r.backup_leader_user_id=?) ORDER BY r.id", [userId, userId, userId]);
    const group = groups[0];
    if (group) {
      const primary = Number(group.leader_user_id) || 0;
      const backup = Number(group.backup_leader_user_id) || 0;
      leaderId = primary && primary !== Number(userId) ? primary : (backup && backup !== Number(userId) ? backup : 0);
    } else leaderId = 0;
  }
  if (!leaderId) return null;
  const [[leader]] = await db.query("SELECT id,name,department_name FROM users WHERE id=? AND is_active=1", [leaderId]);
  return leader || null;
}
