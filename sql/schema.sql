-- FlowDesk 工单系统完整初始化脚本
-- MySQL 8.0+，字符集 utf8mb4。可在空环境离线执行。
-- 不包含业务工单、成员和飞书密钥。

CREATE DATABASE IF NOT EXISTS ticketing_system
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;
USE ticketing_system;

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS ticket_handlers;
DROP TABLE IF EXISTS attachments;
DROP TABLE IF EXISTS ticket_events;
DROP TABLE IF EXISTS tickets;
DROP TABLE IF EXISTS system_role_permissions;
DROP TABLE IF EXISTS user_system_roles;
DROP TABLE IF EXISTS role_members;
DROP TABLE IF EXISTS roles;
DROP TABLE IF EXISTS workflow_steps;
DROP TABLE IF EXISTS audit_logs;
DROP TABLE IF EXISTS system_settings;
DROP TABLE IF EXISTS feishu_settings;
DROP TABLE IF EXISTS permissions;
DROP TABLE IF EXISTS system_roles;
DROP TABLE IF EXISTS departments;
DROP TABLE IF EXISTS users;

SET FOREIGN_KEY_CHECKS = 1;

CREATE TABLE users (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  feishu_open_id VARCHAR(128) NOT NULL,
  name VARCHAR(100) NOT NULL,
  avatar_url VARCHAR(500) NULL,
  department_name VARCHAR(100) NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  username VARCHAR(80) NULL,
  password_hash VARCHAR(128) NULL,
  password_salt VARCHAR(80) NULL,
  external_id VARCHAR(128) NULL,
  department_id VARCHAR(128) NULL,
  source VARCHAR(30) NOT NULL DEFAULT 'LOCAL',
  last_login_at DATETIME NULL,
  manager_user_id BIGINT UNSIGNED NULL,
  manager_open_id VARCHAR(128) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_feishu_open_id (feishu_open_id),
  UNIQUE KEY uq_users_username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE departments (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(100) NOT NULL,
  code VARCHAR(80) NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  feishu_open_id VARCHAR(128) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_departments_name (name),
  UNIQUE KEY uq_departments_code (code),
  UNIQUE KEY uq_departments_feishu (feishu_open_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE roles (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code VARCHAR(50) NOT NULL,
  name VARCHAR(50) NOT NULL,
  leader_user_id BIGINT UNSIGNED NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  description VARCHAR(255) NULL,
  backup_leader_user_id BIGINT UNSIGNED NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  UNIQUE KEY uq_roles_code (code),
  KEY idx_roles_leader (leader_user_id),
  CONSTRAINT fk_roles_leader FOREIGN KEY (leader_user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE role_members (
  role_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  relation_type ENUM('MEMBER','LEADER','BACKUP_LEADER') NOT NULL DEFAULT 'MEMBER',
  PRIMARY KEY (role_id, user_id),
  KEY idx_role_members_user (user_id),
  CONSTRAINT fk_role_members_role FOREIGN KEY (role_id) REFERENCES roles (id) ON DELETE CASCADE,
  CONSTRAINT fk_role_members_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE tickets (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ticket_no VARCHAR(30) NOT NULL,
  title VARCHAR(200) NOT NULL,
  description TEXT NOT NULL,
  role_id BIGINT UNSIGNED NOT NULL,
  submitter_id BIGINT UNSIGNED NULL,
  leader_id BIGINT UNSIGNED NULL,
  assignee_id BIGINT UNSIGNED NULL,
  verifier_id BIGINT UNSIGNED NULL,
  status VARCHAR(60) NOT NULL DEFAULT 'PENDING_SUBMITTER_LEADER_APPROVAL',
  priority ENUM('LOW','NORMAL','HIGH','URGENT') NOT NULL DEFAULT 'NORMAL',
  due_at DATETIME NULL,
  verification_round INT UNSIGNED NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  submitter_leader_id BIGINT UNSIGNED NULL,
  exec_leader_id BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_tickets_no (ticket_no),
  KEY idx_tickets_status (status),
  KEY idx_tickets_submitter (submitter_id),
  KEY idx_tickets_assignee (assignee_id),
  KEY idx_tickets_role (role_id),
  KEY idx_tickets_leader (leader_id),
  KEY idx_tickets_verifier (verifier_id),
  CONSTRAINT fk_tickets_role FOREIGN KEY (role_id) REFERENCES roles (id),
  CONSTRAINT fk_tickets_submitter FOREIGN KEY (submitter_id) REFERENCES users (id),
  CONSTRAINT fk_tickets_leader FOREIGN KEY (leader_id) REFERENCES users (id),
  CONSTRAINT fk_tickets_assignee FOREIGN KEY (assignee_id) REFERENCES users (id),
  CONSTRAINT fk_tickets_verifier FOREIGN KEY (verifier_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE ticket_events (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ticket_id BIGINT UNSIGNED NOT NULL,
  actor_id BIGINT UNSIGNED NULL,
  action VARCHAR(50) NOT NULL,
  from_status VARCHAR(60) NULL,
  to_status VARCHAR(60) NULL,
  comment TEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_ticket_events_ticket_time (ticket_id, created_at),
  KEY idx_ticket_events_actor (actor_id),
  CONSTRAINT fk_events_ticket FOREIGN KEY (ticket_id) REFERENCES tickets (id) ON DELETE CASCADE,
  CONSTRAINT fk_events_actor FOREIGN KEY (actor_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE ticket_handlers (
  ticket_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (ticket_id, user_id),
  KEY idx_ticket_handlers_user (user_id, ticket_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE attachments (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ticket_id BIGINT UNSIGNED NOT NULL,
  uploader_id BIGINT UNSIGNED NULL,
  file_name VARCHAR(255) NOT NULL,
  file_url VARCHAR(1000) NOT NULL,
  file_size BIGINT UNSIGNED NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_attachments_ticket (ticket_id),
  KEY idx_attachments_uploader (uploader_id),
  CONSTRAINT fk_attachments_ticket FOREIGN KEY (ticket_id) REFERENCES tickets (id) ON DELETE CASCADE,
  CONSTRAINT fk_attachments_uploader FOREIGN KEY (uploader_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE audit_logs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  actor_id BIGINT UNSIGNED NULL,
  action VARCHAR(80) NOT NULL,
  target_type VARCHAR(40) NOT NULL,
  target_id VARCHAR(80) NULL,
  detail JSON NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_audit_created (created_at),
  KEY idx_audit_actor (actor_id),
  CONSTRAINT fk_audit_actor FOREIGN KEY (actor_id) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE system_settings (
  setting_key VARCHAR(80) NOT NULL,
  setting_value TEXT NULL,
  updated_by BIGINT UNSIGNED NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (setting_key),
  CONSTRAINT fk_settings_user FOREIGN KEY (updated_by) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE feishu_settings (
  id TINYINT NOT NULL,
  app_id VARCHAR(128) NOT NULL DEFAULT '',
  app_secret VARCHAR(256) NOT NULL DEFAULT '',
  redirect_uri VARCHAR(500) NOT NULL DEFAULT '',
  enabled TINYINT(1) NOT NULL DEFAULT 1,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE permissions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code VARCHAR(80) NOT NULL,
  name VARCHAR(100) NOT NULL,
  description VARCHAR(255) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_permissions_code (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE system_roles (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code VARCHAR(50) NOT NULL,
  name VARCHAR(80) NOT NULL,
  description VARCHAR(255) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_system_roles_code (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE system_role_permissions (
  system_role_id BIGINT UNSIGNED NOT NULL,
  permission_id BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (system_role_id, permission_id),
  KEY idx_srp_permission (permission_id),
  CONSTRAINT fk_srp_role FOREIGN KEY (system_role_id) REFERENCES system_roles (id) ON DELETE CASCADE,
  CONSTRAINT fk_srp_permission FOREIGN KEY (permission_id) REFERENCES permissions (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE user_system_roles (
  user_id BIGINT UNSIGNED NOT NULL,
  system_role_id BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (user_id, system_role_id),
  KEY idx_usr_role (system_role_id),
  CONSTRAINT fk_usr_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_usr_role FOREIGN KEY (system_role_id) REFERENCES system_roles (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE workflow_steps (
  id INT NOT NULL AUTO_INCREMENT,
  code VARCHAR(40) NOT NULL,
  name VARCHAR(80) NOT NULL,
  detail VARCHAR(160) NOT NULL DEFAULT '',
  actor VARCHAR(40) NOT NULL,
  action VARCHAR(40) NULL,
  status VARCHAR(60) NULL,
  sort_order INT NOT NULL,
  enabled TINYINT(1) NOT NULL DEFAULT 1,
  locked TINYINT(1) NOT NULL DEFAULT 0,
  next_code VARCHAR(40) NULL,
  fail_code VARCHAR(40) NULL,
  pos_x INT NULL,
  pos_y INT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_workflow_code (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 本地管理员账号 admin。密码哈希沿用系统初始管理员，导入后请尽快修改密码。
INSERT INTO users (feishu_open_id, username, password_hash, password_salt, name, department_name, source)
VALUES (
  'local-admin',
  'admin',
  '7c6d5db6bf2a78a00e6791d6c7cd4f231abb4acc9fd5f4ba039a0aac09aa4905d1a97532f9f846fcd6e93319653f412b63719f5ecc0744006d40a26c2cf8ae1c',
  'flowdesk-salt',
  '本地管理员',
  '系统管理',
  'LOCAL'
);

INSERT INTO departments (name, code) VALUES
  ('系统管理', 'system'),
  ('研发部', 'rd'),
  ('运维部', 'ops'),
  ('测试部门', 'test');

INSERT INTO roles (code, name, description, leader_user_id, is_active) VALUES
  ('development', '开发支持组', '负责开发类工单的分析、修复与技术支持', (SELECT id FROM users WHERE username='admin'), 1),
  ('operations', '运维服务组', '负责服务器、网络、账号与基础设施运维', (SELECT id FROM users WHERE username='admin'), 1),
  ('testing', '测试支持组', '负责测试验证、质量保障与缺陷复现', (SELECT id FROM users WHERE username='admin'), 1),
  ('product', '产品需求组', '负责产品需求澄清、评审与业务验收', (SELECT id FROM users WHERE username='admin'), 1),
  ('ui', '设计支持组', '负责交互、视觉与设计相关支持', NULL, 1);

INSERT INTO system_roles (code, name, description) VALUES
  ('employee', '普通员工', '创建工单、查看自己的工单、提交验证'),
  ('leader', '审批人', '处理分配给自己的审批节点'),
  ('executor', '执行者', '处理被指派工单'),
  ('admin', '系统管理员', '管理成员、角色、流程和报表');

INSERT INTO user_system_roles (user_id, system_role_id)
SELECT u.id, sr.id FROM users u JOIN system_roles sr ON sr.code='admin' WHERE u.username='admin';

INSERT INTO permissions (code, name, description) VALUES
  ('ticket.create', '创建工单', '提交新的工单'),
  ('ticket.view_own', '查看本人工单', '查看自己提交或参与的工单'),
  ('ticket.approve', '审批工单', '处理审批节点'),
  ('ticket.assign', '指派工单', '选择执行人员'),
  ('ticket.execute', '执行工单', '处理被分配的工单'),
  ('ticket.verify', '验证工单', '验证处理结果'),
  ('admin.members', '管理成员', '新增、编辑、停用成员'),
  ('admin.roles', '管理角色', '管理业务角色与成员关系'),
  ('admin.workflow', '管理流程', '配置工单流程'),
  ('report.view', '查看报表', '查看统计报表');

INSERT INTO system_role_permissions (system_role_id, permission_id)
SELECT sr.id, p.id FROM system_roles sr JOIN permissions p
WHERE (sr.code='employee' AND p.code IN ('ticket.create','ticket.view_own','ticket.verify'))
   OR (sr.code='leader' AND p.code IN ('ticket.approve','ticket.assign'))
   OR (sr.code='executor' AND p.code IN ('ticket.execute'))
   OR (sr.code='admin' AND p.code IN (
        'ticket.create','ticket.view_own','ticket.approve','ticket.assign','ticket.execute','ticket.verify',
        'admin.members','admin.roles','admin.workflow','report.view'
      ));

INSERT INTO workflow_steps (code, name, detail, actor, action, status, sort_order, enabled, locked, next_code, fail_code, pos_x, pos_y) VALUES
  ('CREATE', '提交工单', '员工提交问题', 'submitter', NULL, NULL, 1, 1, 1, 'SUBMITTER_LEADER', NULL, 40, 70),
  ('SUBMITTER_LEADER', 'Leader 审批', '提交人的上级审批', 'submitter_leader', 'submitter_approve', 'PENDING_SUBMITTER_LEADER_APPROVAL', 2, 1, 0, 'EXEC_LEADER', 'CREATE', 250, 70),
  ('EXEC_LEADER', '部门Leader 审批', '执行人的上级审批', 'executor_leader', 'approve', 'PENDING_LEADER_APPROVAL', 3, 1, 0, 'ASSIGN', 'CREATE', 460, 70),
  ('ASSIGN', '指派执行者', '具体处理事情的人', 'group_leader', 'assign', 'PENDING_ASSIGNMENT', 4, 1, 0, 'EXECUTE', NULL, 670, 70),
  ('EXECUTE', '执行处理', '执行人处理并反馈', 'assignee', 'complete', 'IN_PROGRESS', 5, 1, 1, 'VERIFY', NULL, 880, 70),
  ('VERIFY', '验证环节', '提交人进行验证环节', 'submitter', 'verify_ok', 'PENDING_VERIFICATION', 6, 1, 1, 'DONE', 'EXECUTE', 1090, 70),
  ('DONE', '验证通过', '验证通过后工单结束', 'submitter', NULL, 'COMPLETED', 7, 1, 1, NULL, NULL, 1300, 70);

INSERT INTO feishu_settings (id, app_id, app_secret, redirect_uri, enabled)
VALUES (1, '', '', 'http://127.0.0.1:3000/api/auth/feishu/callback', 0);
