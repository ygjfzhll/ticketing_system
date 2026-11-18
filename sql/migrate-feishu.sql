SET @sql=(SELECT IF(COUNT(*)=0,"ALTER TABLE departments ADD COLUMN feishu_open_id VARCHAR(128) NULL","SELECT 1") FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='departments' AND column_name='feishu_open_id');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;
