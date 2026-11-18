CREATE DATABASE IF NOT EXISTS `ticketing_system` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `ticketing_system`;

CREATE TABLE IF NOT EXISTS users (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  feishu_open_id VARCHAR(128) NOT NULL UNIQUE,
  manager_user_id BIGINT UNSIGNED NULL,
  username VARCHAR(80) NULL UNIQUE,
  password_hash VARCHAR(128) NULL,
  password_salt VARCHAR(80) NULL,
  name VARCHAR(100) NOT NULL,
  avatar_url VARCHAR(500) NULL,
  department_name VARCHAR(100) NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS roles (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  code VARCHAR(50) NOT NULL UNIQUE,
  name VARCHAR(50) NOT NULL,
  leader_user_id BIGINT UNSIGNED NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_roles_leader FOREIGN KEY (leader_user_id) REFERENCES users(id)
) ENGINE=InnoDB;

INSERT INTO users (feishu_open_id,username,password_hash,password_salt,name,department_name) VALUES ('local-admin','admin','7c6d5db6bf2a78a00e6791d6c7cd4f231abb4acc9fd5f4ba039a0aac09aa4905d1a97532f9f846fcd6e93319653f412b63719f5ecc0744006d40a26c2cf8ae1c','flowdesk-salt','本地管理员','系统管理') ON DUPLICATE KEY UPDATE username=VALUES(username),password_hash=VALUES(password_hash),password_salt=VALUES(password_salt),name=VALUES(name);
INSERT INTO roles (code,name,leader_user_id) SELECT 'development','开发',(SELECT id FROM users WHERE feishu_open_id='local-admin') WHERE NOT EXISTS (SELECT 1 FROM roles WHERE code='development');
INSERT INTO roles (code,name,leader_user_id) SELECT 'operations','运维',(SELECT id FROM users WHERE feishu_open_id='local-admin') WHERE NOT EXISTS (SELECT 1 FROM roles WHERE code='operations');
INSERT INTO roles (code,name,leader_user_id) SELECT 'testing','测试',(SELECT id FROM users WHERE feishu_open_id='local-admin') WHERE NOT EXISTS (SELECT 1 FROM roles WHERE code='testing');
INSERT INTO roles (code,name,leader_user_id) SELECT 'product','产品',(SELECT id FROM users WHERE feishu_open_id='local-admin') WHERE NOT EXISTS (SELECT 1 FROM roles WHERE code='product');

CREATE TABLE IF NOT EXISTS role_members (
  role_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (role_id, user_id),
  CONSTRAINT fk_role_members_role FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE,
  CONSTRAINT fk_role_members_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS tickets (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  ticket_no VARCHAR(30) NOT NULL UNIQUE,
  title VARCHAR(200) NOT NULL,
  description TEXT NOT NULL,
  role_id BIGINT UNSIGNED NOT NULL,
  submitter_id BIGINT UNSIGNED NOT NULL,
  leader_id BIGINT UNSIGNED NULL,
  submitter_leader_id BIGINT UNSIGNED NULL,
  assignee_id BIGINT UNSIGNED NULL,
  verifier_id BIGINT UNSIGNED NOT NULL,
  status VARCHAR(60) NOT NULL DEFAULT 'PENDING_SUBMITTER_LEADER_APPROVAL',
  priority ENUM('LOW','NORMAL','HIGH','URGENT') NOT NULL DEFAULT 'NORMAL',
  due_at DATETIME NULL,
  verification_round INT UNSIGNED NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_tickets_status (status), INDEX idx_tickets_submitter (submitter_id), INDEX idx_tickets_assignee (assignee_id),
  CONSTRAINT fk_tickets_role FOREIGN KEY (role_id) REFERENCES roles(id),
  CONSTRAINT fk_tickets_submitter FOREIGN KEY (submitter_id) REFERENCES users(id),
  CONSTRAINT fk_tickets_leader FOREIGN KEY (leader_id) REFERENCES users(id),
  CONSTRAINT fk_tickets_assignee FOREIGN KEY (assignee_id) REFERENCES users(id),
  CONSTRAINT fk_tickets_verifier FOREIGN KEY (verifier_id) REFERENCES users(id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS ticket_events (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  ticket_id BIGINT UNSIGNED NOT NULL,
  actor_id BIGINT UNSIGNED NOT NULL,
  action VARCHAR(50) NOT NULL,
  from_status VARCHAR(50) NULL,
  to_status VARCHAR(50) NULL,
  comment TEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_ticket_events_ticket_time (ticket_id, created_at),
  CONSTRAINT fk_events_ticket FOREIGN KEY (ticket_id) REFERENCES tickets(id) ON DELETE CASCADE,
  CONSTRAINT fk_events_actor FOREIGN KEY (actor_id) REFERENCES users(id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS attachments (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  ticket_id BIGINT UNSIGNED NOT NULL,
  uploader_id BIGINT UNSIGNED NOT NULL,
  file_name VARCHAR(255) NOT NULL,
  file_url VARCHAR(1000) NOT NULL,
  file_size BIGINT UNSIGNED NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_attachments_ticket FOREIGN KEY (ticket_id) REFERENCES tickets(id) ON DELETE CASCADE,
  CONSTRAINT fk_attachments_uploader FOREIGN KEY (uploader_id) REFERENCES users(id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS system_settings (
  setting_key VARCHAR(80) PRIMARY KEY,
  setting_value TEXT NULL,
  updated_by BIGINT UNSIGNED NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_settings_user FOREIGN KEY (updated_by) REFERENCES users(id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS system_roles (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  code VARCHAR(50) NOT NULL UNIQUE,
  name VARCHAR(80) NOT NULL,
  description VARCHAR(255) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS user_system_roles (
  user_id BIGINT UNSIGNED NOT NULL,
  system_role_id BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY(user_id,system_role_id),
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY(system_role_id) REFERENCES system_roles(id) ON DELETE CASCADE
) ENGINE=InnoDB;

INSERT INTO system_roles(code,name,description) VALUES
('employee','普通员工','创建工单、查看自己的工单、提交验证'),
('leader','Leader','审批本业务角色工单、指派执行者'),
('executor','执行者','处理被指派工单'),
('admin','系统管理员','管理成员、角色、流程和报表')
ON DUPLICATE KEY UPDATE name=VALUES(name),description=VALUES(description);
