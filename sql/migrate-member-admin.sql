SET @sql=(SELECT IF(COUNT(*)=0,"ALTER TABLE users ADD COLUMN last_login_at DATETIME NULL","SELECT 1") FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='users' AND column_name='last_login_at');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;
