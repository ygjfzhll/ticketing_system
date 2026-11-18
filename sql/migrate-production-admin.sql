USE ticketing_system;

SET @sql=(SELECT IF(COUNT(*)=0,"ALTER TABLE users ADD COLUMN external_id VARCHAR(128) NULL", "SELECT 1") FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='users' AND column_name='external_id'); PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;
SET @sql=(SELECT IF(COUNT(*)=0,"ALTER TABLE users ADD COLUMN department_id VARCHAR(128) NULL", "SELECT 1") FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='users' AND column_name='department_id'); PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;
SET @sql=(SELECT IF(COUNT(*)=0,"ALTER TABLE users ADD COLUMN source VARCHAR(30) NOT NULL DEFAULT 'LOCAL'", "SELECT 1") FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='users' AND column_name='source'); PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;
CREATE TABLE IF NOT EXISTS audit_logs (id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT, actor_id BIGINT UNSIGNED NULL, action VARCHAR(80) NOT NULL, target_type VARCHAR(40) NOT NULL, target_id VARCHAR(80) NULL, detail JSON NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, INDEX idx_audit_created(created_at), FOREIGN KEY(actor_id) REFERENCES users(id) ON DELETE SET NULL) ENGINE=InnoDB;

INSERT IGNORE INTO user_system_roles(user_id,system_role_id) SELECT u.id,sr.id FROM users u JOIN system_roles sr ON sr.code='admin' WHERE u.username='admin';
