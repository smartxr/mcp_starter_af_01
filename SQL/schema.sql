/*
Run against the target database before data.sql. No database is created.
This is a one-time creation script, not a migration of existing tables.

Model decisions:
- FirstName stores the combined first/middle name described on slide 7.
- AuthorType is nullable; non-null values are restricted to Internal / External.
- PublicationLeadID references Authors; the Entra ID is stored separately.
- DiseaseAreas may reference a ProjectManager through PMID.
- AuthorAgreements retain the source file name and extracted names when IDs are unmatched.
- COIs retain manuscript metadata and support multiple disclosure rows per record.
- PublicationAuthors links authors to publications; author order is unique per publication.
- Publications combines publication details with its ACF file and metadata.
- MetadataExtractionStatus defaults to Pending.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'dbo.DiseaseAreas', N'U') IS NOT NULL
        OR OBJECT_ID(N'dbo.ProjectManagers', N'U') IS NOT NULL
        OR OBJECT_ID(N'dbo.Studies', N'U') IS NOT NULL
        OR OBJECT_ID(N'dbo.Authors', N'U') IS NOT NULL
        OR OBJECT_ID(N'dbo.Publications', N'U') IS NOT NULL
        OR OBJECT_ID(N'dbo.PublicationAuthors', N'U') IS NOT NULL
        OR OBJECT_ID(N'dbo.AuthorAgreements', N'U') IS NOT NULL
        OR OBJECT_ID(N'dbo.COIs', N'U') IS NOT NULL
        OR OBJECT_ID(N'dbo.COIDisclosures', N'U') IS NOT NULL
        OR OBJECT_ID(N'dbo.DiseaseArea', N'U') IS NOT NULL
        OR OBJECT_ID(N'dbo.ProjectManager', N'U') IS NOT NULL
        OR OBJECT_ID(N'dbo.Study', N'U') IS NOT NULL
        OR OBJECT_ID(N'dbo.Author', N'U') IS NOT NULL
        OR OBJECT_ID(N'dbo.Publication', N'U') IS NOT NULL
        OR OBJECT_ID(N'dbo.ACF', N'U') IS NOT NULL
        OR OBJECT_ID(N'dbo.ACF_Author', N'U') IS NOT NULL
        OR OBJECT_ID(N'dbo.Publications_Author', N'U') IS NOT NULL
        OR OBJECT_ID(N'dbo.Publication_Authors', N'U') IS NOT NULL
        OR OBJECT_ID(N'dbo.AuthorAgreement', N'U') IS NOT NULL
        OR OBJECT_ID(N'dbo.COI', N'U') IS NOT NULL
        THROW 50001, 'Model tables already exist. Use a reviewed migration instead of rerunning schema.sql.', 1;

    CREATE TABLE dbo.ProjectManagers
    (
        PMID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ProjectManagers PRIMARY KEY,
        FirstName NVARCHAR(100) NOT NULL,
        LastName NVARCHAR(100) NOT NULL,
        Email NVARCHAR(320) NOT NULL,
        EntraObjectID UNIQUEIDENTIFIER NULL,
        CreatedOn DATETIME2(7) NOT NULL CONSTRAINT DF_ProjectManagers_CreatedOn DEFAULT (SYSUTCDATETIME()),
        ModifiedOn DATETIME2(7) NOT NULL CONSTRAINT DF_ProjectManagers_ModifiedOn DEFAULT (SYSUTCDATETIME()),
        IsDeleted BIT NOT NULL CONSTRAINT DF_ProjectManagers_IsDeleted DEFAULT (0),
        CONSTRAINT UQ_ProjectManagers_Email UNIQUE (Email)
    );
    CREATE UNIQUE INDEX UX_ProjectManagers_EntraObjectID
        ON dbo.ProjectManagers (EntraObjectID) WHERE EntraObjectID IS NOT NULL;

    CREATE TABLE dbo.DiseaseAreas
    (
        DiseaseAreaID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DiseaseAreas PRIMARY KEY,
        DiseaseAreaName NVARCHAR(200) NOT NULL,
        PMID INT NULL,
        CreatedOn DATETIME2(7) NOT NULL CONSTRAINT DF_DiseaseAreas_CreatedOn DEFAULT (SYSUTCDATETIME()),
        ModifiedOn DATETIME2(7) NOT NULL CONSTRAINT DF_DiseaseAreas_ModifiedOn DEFAULT (SYSUTCDATETIME()),
        IsDeleted BIT NOT NULL CONSTRAINT DF_DiseaseAreas_IsDeleted DEFAULT (0),
        CONSTRAINT UQ_DiseaseAreas_Name UNIQUE (DiseaseAreaName),
        CONSTRAINT FK_DiseaseAreas_ProjectManagers FOREIGN KEY (PMID) REFERENCES dbo.ProjectManagers (PMID)
    );

    CREATE TABLE dbo.Studies
    (
        StudyID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Studies PRIMARY KEY,
        StudyTitle NVARCHAR(500) NOT NULL,
        DiseaseAreaID INT NULL,
        CreatedOn DATETIME2(7) NOT NULL CONSTRAINT DF_Studies_CreatedOn DEFAULT (SYSUTCDATETIME()),
        ModifiedOn DATETIME2(7) NOT NULL CONSTRAINT DF_Studies_ModifiedOn DEFAULT (SYSUTCDATETIME()),
        IsDeleted BIT NOT NULL CONSTRAINT DF_Studies_IsDeleted DEFAULT (0),
        CONSTRAINT FK_Studies_DiseaseAreas FOREIGN KEY (DiseaseAreaID) REFERENCES dbo.DiseaseAreas (DiseaseAreaID)
    );
    CREATE INDEX IX_Studies_DiseaseAreaID ON dbo.Studies (DiseaseAreaID);

    CREATE TABLE dbo.Authors
    (
        AuthorID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Authors PRIMARY KEY,
        FirstName NVARCHAR(100) NOT NULL,
        LastName NVARCHAR(100) NOT NULL,
        Title NVARCHAR(100) NULL,
        Email NVARCHAR(320) NULL,
        Phone NVARCHAR(50) NULL,
        Address NVARCHAR(500) NULL,
        CityState NVARCHAR(200) NULL, 
        Country NVARCHAR(100) NULL, 
        Affiliation NVARCHAR(500) NULL,
        AuthorType NVARCHAR(20) NULL,
        Validated BIT NOT NULL CONSTRAINT DF_Authors_Validated DEFAULT (0),
        AutoupdateLocked BIT NOT NULL CONSTRAINT DF_Authors_AutoupdateLocked DEFAULT (0),
        CreatedOn DATETIME2(7) NOT NULL CONSTRAINT DF_Authors_CreatedOn DEFAULT (SYSUTCDATETIME()),
        ModifiedOn DATETIME2(7) NOT NULL CONSTRAINT DF_Authors_ModifiedOn DEFAULT (SYSUTCDATETIME()),
        IsDeleted BIT NOT NULL CONSTRAINT DF_Authors_IsDeleted DEFAULT (0),
        CONSTRAINT CK_Authors_AuthorType CHECK (AuthorType IN (N'Internal', N'External'))
    );
    CREATE INDEX IX_Authors_Email ON dbo.Authors (Email);

    CREATE TABLE dbo.Publications
    (
        PublicationID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Publications PRIMARY KEY,
        StudyID INT NULL,
        PublicationTitle NVARCHAR(500) NOT NULL,
        PublicationLeadID INT NULL,
        PublicationLeadEntraID UNIQUEIDENTIFIER NULL,
        PublicationLeadName NVARCHAR(100) NULL,
        PublicationDate DATE NULL,
        Status NVARCHAR(30) NOT NULL CONSTRAINT DF_Publications_Status DEFAULT (N'Draft'),
        FileName NVARCHAR(260) NOT NULL,
        FileURL NVARCHAR(2000) NULL,
        UploadedAt DATETIME2(7) NOT NULL CONSTRAINT DF_Publications_UploadedAt DEFAULT (SYSUTCDATETIME()),
        DocumentID NVARCHAR(260) NULL,
        CreatedOn DATETIME2(7) NOT NULL CONSTRAINT DF_Publications_CreatedOn DEFAULT (SYSUTCDATETIME()),
        ModifiedOn DATETIME2(7) NOT NULL CONSTRAINT DF_Publications_ModifiedOn DEFAULT (SYSUTCDATETIME()),
        IsDeleted BIT NOT NULL CONSTRAINT DF_Publications_IsDeleted DEFAULT (0),
        CONSTRAINT FK_Publications_Studies FOREIGN KEY (StudyID) REFERENCES dbo.Studies (StudyID),
        CONSTRAINT FK_Publications_Authors FOREIGN KEY (PublicationLeadID) REFERENCES dbo.Authors (AuthorID)
    );
    CREATE INDEX IX_Publications_StudyID ON dbo.Publications (StudyID);
    CREATE INDEX IX_Publications_PublicationLeadID ON dbo.Publications (PublicationLeadID);

    CREATE TABLE dbo.PublicationAuthors
    (
        PublicationID INT NOT NULL,
        AuthorID INT NOT NULL,
        AuthorOrder INT NOT NULL,
        PMVerified BIT NOT NULL CONSTRAINT DF_PublicationAuthors_PMVerified DEFAULT (0),
        VerifiedByPMID INT NULL,
        PublicationLeadID INT NULL,
        PublicationLeadEntraID UNIQUEIDENTIFIER NULL,
        PublicationLeadName NVARCHAR(100) NULL,
        VerifiedAt DATETIME2(7) NULL,
        CreatedOn DATETIME2(7) NOT NULL CONSTRAINT DF_PublicationAuthors_CreatedOn DEFAULT (SYSUTCDATETIME()),
        ModifiedOn DATETIME2(7) NOT NULL CONSTRAINT DF_PublicationAuthors_ModifiedOn DEFAULT (SYSUTCDATETIME()),
        IsDeleted BIT NOT NULL CONSTRAINT DF_PublicationAuthors_IsDeleted DEFAULT (0),
        CONSTRAINT PK_PublicationAuthors PRIMARY KEY (PublicationID, AuthorID),
        CONSTRAINT FK_PublicationAuthors_Publications FOREIGN KEY (PublicationID) REFERENCES dbo.Publications (PublicationID),
        CONSTRAINT FK_PublicationAuthors_Authors FOREIGN KEY (AuthorID) REFERENCES dbo.Authors (AuthorID),
        CONSTRAINT UQ_PublicationAuthors_AuthorOrder UNIQUE (PublicationID, AuthorOrder),
        CONSTRAINT FK_PublicationAuthors_VerifiedByProjectManagers FOREIGN KEY (VerifiedByPMID) REFERENCES dbo.ProjectManagers (PMID),
        CONSTRAINT FK_PublicationAuthors_PublicationLead FOREIGN KEY (PublicationLeadID) REFERENCES dbo.Authors (AuthorID)
    );
    CREATE INDEX IX_PublicationAuthors_AuthorID ON dbo.PublicationAuthors (AuthorID);
    CREATE INDEX IX_PublicationAuthors_VerifiedByPMID ON dbo.PublicationAuthors (VerifiedByPMID);

    CREATE TABLE dbo.AuthorAgreements
    (
        AAID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AuthorAgreements PRIMARY KEY,
        StudyID INT NULL,
        StudyExtractedName NVARCHAR(500) NULL,
        AuthorID INT NULL,
        AuthorExtractedFirstName NVARCHAR(100) NULL,
        AuthorExtractedLastName NVARCHAR(100) NULL,
        Status NVARCHAR(30) NOT NULL CONSTRAINT DF_AuthorAgreements_Status DEFAULT (N'Not Started'),
        PublicationLeadID INT NULL,
        PublicationLeadEntraID UNIQUEIDENTIFIER NULL,
        PublicationLeadName NVARCHAR(100) NULL,
        DocumentDate DATE NULL,
        FileName NVARCHAR(260) NULL,
        DocumentURL NVARCHAR(2000) NULL,
        CreatedOn DATETIME2(7) NOT NULL CONSTRAINT DF_AuthorAgreements_CreatedOn DEFAULT (SYSUTCDATETIME()),
        ModifiedOn DATETIME2(7) NOT NULL CONSTRAINT DF_AuthorAgreements_ModifiedOn DEFAULT (SYSUTCDATETIME()),
        IsDeleted BIT NOT NULL CONSTRAINT DF_AuthorAgreements_IsDeleted DEFAULT (0),
        CONSTRAINT FK_AuthorAgreements_Studies FOREIGN KEY (StudyID) REFERENCES dbo.Studies (StudyID),
        CONSTRAINT FK_AuthorAgreements_Authors FOREIGN KEY (AuthorID) REFERENCES dbo.Authors (AuthorID),
        CONSTRAINT FK_AuthorAgreements_PublicationLead FOREIGN KEY (PublicationLeadID) REFERENCES dbo.Authors (AuthorID)
    );
    CREATE UNIQUE INDEX UX_AuthorAgreements_Study_Author
        ON dbo.AuthorAgreements (StudyID, AuthorID)
        WHERE StudyID IS NOT NULL AND AuthorID IS NOT NULL;
    CREATE INDEX IX_AuthorAgreements_PublicationLead ON dbo.AuthorAgreements (PublicationLeadID);

    CREATE TABLE dbo.COIs
    (
        COIID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_COIs PRIMARY KEY,
        DiseaseAreaID INT NULL,
        AuthorID INT NULL,
        AuthorExtractedFirstName NVARCHAR(100) NULL,
        AuthorExtractedLastName NVARCHAR(100) NULL,
        ManuscriptTitle NVARCHAR(500) NOT NULL,
        ManuscriptNumber NVARCHAR(100) NULL,
        FileName NVARCHAR(260) NOT NULL,
        Status NVARCHAR(30) NOT NULL CONSTRAINT DF_COIs_Status DEFAULT (N'Draft'),
        DocumentDate DATE NULL,
        DocumentURL NVARCHAR(2000) NULL,
        CreatedOn DATETIME2(7) NOT NULL CONSTRAINT DF_COIs_CreatedOn DEFAULT (SYSUTCDATETIME()),
        ModifiedOn DATETIME2(7) NOT NULL CONSTRAINT DF_COIs_ModifiedOn DEFAULT (SYSUTCDATETIME()),
        IsDeleted BIT NOT NULL CONSTRAINT DF_COIs_IsDeleted DEFAULT (0),
        CONSTRAINT FK_COIs_DiseaseAreas FOREIGN KEY (DiseaseAreaID) REFERENCES dbo.DiseaseAreas (DiseaseAreaID),
        CONSTRAINT FK_COIs_Authors FOREIGN KEY (AuthorID) REFERENCES dbo.Authors (AuthorID)
    );

    CREATE TABLE dbo.COIDisclosures
    (
        COIDisclosureID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_COIDisclosures PRIMARY KEY,
        COIID INT NOT NULL,
        EntityData NVARCHAR(MAX) NOT NULL,
        RelationshipData NVARCHAR(MAX) NOT NULL,
        CreatedOn DATETIME2(7) NOT NULL CONSTRAINT DF_COIDisclosures_CreatedOn DEFAULT (SYSUTCDATETIME()),
        ModifiedOn DATETIME2(7) NOT NULL CONSTRAINT DF_COIDisclosures_ModifiedOn DEFAULT (SYSUTCDATETIME()),
        IsDeleted BIT NOT NULL CONSTRAINT DF_COIDisclosures_IsDeleted DEFAULT (0),
        CONSTRAINT FK_COIDisclosures_COIs FOREIGN KEY (COIID) REFERENCES dbo.COIs (COIID)
    );
    CREATE INDEX IX_COIDisclosures_COIID ON dbo.COIDisclosures (COIID);

    DECLARE @TimestampTables TABLE
    (
        TableName SYSNAME NOT NULL,
        PrimaryKeyName SYSNAME NOT NULL,
        PrimaryKey2Name SYSNAME NULL
    );
    INSERT INTO @TimestampTables (TableName, PrimaryKeyName, PrimaryKey2Name) VALUES
        (N'ProjectManagers', N'PMID', NULL),
        (N'DiseaseAreas', N'DiseaseAreaID', NULL),
        (N'Studies', N'StudyID', NULL),
        (N'Authors', N'AuthorID', NULL),
        (N'Publications', N'PublicationID', NULL),
        (N'PublicationAuthors', N'PublicationID', N'AuthorID'),
        (N'AuthorAgreements', N'AAID', NULL),
        (N'COIs', N'COIID', NULL),
        (N'COIDisclosures', N'COIDisclosureID', NULL);

    DECLARE @TableName SYSNAME;
    DECLARE @PrimaryKeyName SYSNAME;
    DECLARE @PrimaryKey2Name SYSNAME;
    DECLARE @TriggerName SYSNAME;
    DECLARE @TriggerSql NVARCHAR(MAX);
    DECLARE TimestampTriggerCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT TableName, PrimaryKeyName, PrimaryKey2Name FROM @TimestampTables;

    OPEN TimestampTriggerCursor;
    FETCH NEXT FROM TimestampTriggerCursor INTO @TableName, @PrimaryKeyName, @PrimaryKey2Name;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @TriggerName = N'TR_' + @TableName + N'_SetModifiedOn';
        SET @TriggerSql =
            N'CREATE TRIGGER dbo.' + QUOTENAME(@TriggerName) +
            N' ON dbo.' + QUOTENAME(@TableName) + N' AFTER UPDATE AS
            BEGIN
                SET NOCOUNT ON;
                IF TRIGGER_NESTLEVEL(OBJECT_ID(N''dbo.' + @TriggerName + N''', N''TR''), ''AFTER'', ''DML'') > 1 RETURN;
                UPDATE target
                SET ModifiedOn = SYSUTCDATETIME()
                FROM dbo.' + QUOTENAME(@TableName) + N' AS target
                INNER JOIN inserted AS source
                    ON target.' + QUOTENAME(@PrimaryKeyName) + N' = source.' + QUOTENAME(@PrimaryKeyName) +
                    CASE WHEN @PrimaryKey2Name IS NULL THEN N'' ELSE
                        N' AND target.' + QUOTENAME(@PrimaryKey2Name) + N' = source.' + QUOTENAME(@PrimaryKey2Name)
                    END + N';
            END;';
        EXEC sys.sp_executesql @TriggerSql;
        FETCH NEXT FROM TimestampTriggerCursor INTO @TableName, @PrimaryKeyName, @PrimaryKey2Name;
    END;
    CLOSE TimestampTriggerCursor;
    DEALLOCATE TimestampTriggerCursor;

    EXEC sys.sp_executesql N'
        CREATE VIEW dbo.vw_StudiesWithDiseaseArea
        AS
        SELECT [st].[StudyID]
              ,[st].[StudyTitle]
              ,[st].[DiseaseAreaID]
              ,[da].[DiseaseAreaName]
              ,[st].[CreatedOn]
              ,[st].[ModifiedOn]
              ,[st].[IsDeleted]
        FROM [dbo].[Studies] [st]
        LEFT JOIN [dbo].[DiseaseAreas] [da]
            ON [st].[DiseaseAreaID] = [da].[DiseaseAreaID];';

    EXEC sys.sp_executesql N'
        CREATE VIEW dbo.vw_ActivePublications
        AS
        SELECT
            [pb].[PublicationID],
            [pb].[PublicationTitle],
            [st].[StudyTitle],
            [da].[DiseaseAreaName],
            [pb].[Status],
            COUNT([pa].[AuthorID]) AS AuthorCount,
            [pb].[FileName],
            [pb].[DocumentID],
            [pb].[CreatedOn],
            [pb].[ModifiedOn],
            [pb].[IsDeleted]
        FROM [dbo].[Publications] AS [pb]
        LEFT JOIN [dbo].[Studies] AS [st]
            ON [pb].[StudyID] = [st].[StudyID]
        LEFT JOIN [dbo].[DiseaseAreas] AS [da]
            ON [st].[DiseaseAreaID] = [da].[DiseaseAreaID]
        LEFT JOIN [dbo].[PublicationAuthors] AS [pa]
            ON [pa].[PublicationID] = [pb].[PublicationID]
        WHERE [pb].[IsDeleted] = 0
        AND [pb].[Status] IN (N''Draft'', N''Pending PM Review'', N''Active'')
        GROUP BY
            [pb].[PublicationID],
            [pb].[PublicationTitle],
            [st].[StudyTitle],
            [da].[DiseaseAreaName],
            [pb].[Status],
            [pb].[FileName],
            [pb].[DocumentID],
            [pb].[CreatedOn],
            [pb].[ModifiedOn],
            [pb].[IsDeleted]
        ;';

    EXEC sys.sp_executesql N'
        CREATE VIEW dbo.vw_PublicationAuthorDocumentStatus
        AS
        SELECT
            p.PublicationID,
            p.PublicationTitle,
            a.AuthorID,
            a.FirstName,
            a.LastName,
            pa.AuthorOrder,
            aa_latest.AgreementDate,
            CASE
                WHEN aa_latest.AgreementDate IS NULL THEN NULL
                ELSE DATEDIFF(DAY, CAST(GETDATE() AS date), DATEADD(YEAR, 1, aa_latest.AgreementDate))
            END AS AuthorAgreementDaysRemaining,
            coi_latest.COIDate,
            CASE
                WHEN coi_latest.COIDate IS NULL THEN NULL
                ELSE DATEDIFF(DAY, CAST(GETDATE() AS date), DATEADD(YEAR, 1, coi_latest.COIDate))
            END AS COIDaysRemaining
        FROM dbo.Publications AS p
        JOIN dbo.PublicationAuthors AS pa
            ON pa.PublicationID = p.PublicationID
        JOIN dbo.Authors AS a
            ON a.AuthorID = pa.AuthorID
        OUTER APPLY
        (
            SELECT TOP (1)
                aa.DocumentDate AS AgreementDate
            FROM dbo.AuthorAgreements AS aa
            WHERE aa.AuthorID = a.AuthorID
            ORDER BY aa.DocumentDate DESC
        ) AS aa_latest
        OUTER APPLY
        (
            SELECT TOP (1)
                c.DocumentDate AS COIDate
            FROM dbo.COIs AS c
            WHERE c.AuthorID = a.AuthorID
            ORDER BY c.DocumentDate DESC
        ) AS coi_latest;';

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;