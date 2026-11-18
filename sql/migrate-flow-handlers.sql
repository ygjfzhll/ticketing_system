USE ticketing_system;
ALTER TABLE tickets MODIFY COLUMN status VARCHAR(60) NOT NULL DEFAULT 'PENDING_SUBMITTER_LEADER_APPROVAL';
ALTER TABLE ticket_events MODIFY COLUMN from_status VARCHAR(60) NULL;
ALTER TABLE ticket_events MODIFY COLUMN to_status VARCHAR(60) NULL;
SET @sql=(SELECT IF(COUNT(*)=0,'ALTER TABLE users ADD COLUMN manager_user_id BIGINT UNSIGNED NULL','SELECT 1') FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='users' AND column_name='manager_user_id');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;
SET @sql=(SELECT IF(COUNT(*)=0,'ALTER TABLE users ADD COLUMN manager_open_id VARCHAR(128) NULL','SELECT 1') FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='users' AND column_name='manager_open_id');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;
SET @sql=(SELECT IF(COUNT(*)=0,'ALTER TABLE tickets ADD COLUMN submitter_leader_id BIGINT UNSIGNED NULL','SELECT 1') FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='tickets' AND column_name='submitter_leader_id');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;
CREATE TABLE IF NOT EXISTS ticket_handlers (
  ticket_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (ticket_id, user_id),
  INDEX idx_ticket_handlers_user (user_id, ticket_id)
) ENGINE=InnoDB;
