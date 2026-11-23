-- 01_backup.sql: full backup of the current database (DemoHR) before the update (step 2 of sql/extend_data.sql)
-- Saves <database>_<yyyymmdd_hhmmss>_before_update.bak in the <database> subfolder of the SQL Server default backup folder
-- (no path is written in this repository), checks the file with RESTORE VERIFYONLY, and keeps the newest 10 backups.
-- If anything fails the script stops (run sqlcmd with -b) and no data is touched.
SET NOCOUNT ON;

DECLARE @Keep   int           = 10;   -- number of backups to keep
DECLARE @Root   nvarchar(260) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(260));
DECLARE @Db     sysname       = DB_NAME();
DECLARE @Folder nvarchar(300) = @Root + N'\' + @Db;
DECLARE @Stamp  varchar(15)   = FORMAT(SYSDATETIME(), 'yyyyMMdd_HHmmss');
DECLARE @File   nvarchar(400) = @Folder + N'\' + @Db + N'_' + @Stamp + N'_before_update.bak';
DECLARE @Sql    nvarchar(max);

EXEC master.dbo.xp_create_subdir @Folder;   -- does nothing if the folder exists

SET @Sql = N'BACKUP DATABASE ' + QUOTENAME(@Db) + N' TO DISK = N''' + REPLACE(@File, '''', '''''') + N''' WITH INIT, CHECKSUM, STATS = 25;';
EXEC (@Sql);

SET @Sql = N'RESTORE VERIFYONLY FROM DISK = N''' + REPLACE(@File, '''', '''''') + N''' WITH CHECKSUM;';
EXEC (@Sql);

-- Keep the newest @Keep backups: delete .bak files in this database's folder older than the finish time of the @Keep-th newest one
DECLARE @Cutoff datetime;
SELECT @Cutoff = MIN(backup_finish_date)
FROM (SELECT TOP (@Keep) s.backup_finish_date
      FROM msdb.dbo.backupset s
      JOIN msdb.dbo.backupmediafamily m ON m.media_set_id = s.media_set_id
      WHERE s.database_name = @Db AND s.type = 'D' AND m.physical_device_name LIKE @Folder + N'\%'
      ORDER BY s.backup_finish_date DESC) k;
IF @Cutoff IS NOT NULL
    EXEC master.dbo.xp_delete_file 0, @Folder, N'bak', @Cutoff;

PRINT 'Backup done and verified: ' + @File;
