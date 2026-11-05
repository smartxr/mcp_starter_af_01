/*
WARNING: This permanently drops the model objects created by schema.sql.
It does not drop unrelated tables or objects in the database.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'dbo.vw_StudiesWithDiseaseArea', N'V') IS NOT NULL
        DROP VIEW dbo.vw_StudiesWithDiseaseArea;

    IF OBJECT_ID(N'dbo.vw_ActivePublications', N'V') IS NOT NULL
        DROP VIEW dbo.vw_ActivePublications;

    IF OBJECT_ID(N'dbo.vw_PublicationAuthorDocumentStatus', N'V') IS NOT NULL
        DROP VIEW dbo.vw_PublicationAuthorDocumentStatus;

    IF OBJECT_ID(N'dbo.PublicationAuthors', N'U') IS NOT NULL
        DROP TABLE dbo.PublicationAuthors;

    IF OBJECT_ID(N'dbo.AuthorAgreements', N'U') IS NOT NULL
        DROP TABLE dbo.AuthorAgreements;

    IF OBJECT_ID(N'dbo.COIDisclosures', N'U') IS NOT NULL
        DROP TABLE dbo.COIDisclosures;

    IF OBJECT_ID(N'dbo.COIs', N'U') IS NOT NULL
        DROP TABLE dbo.COIs;

    IF OBJECT_ID(N'dbo.Publications', N'U') IS NOT NULL
        DROP TABLE dbo.Publications;

    IF OBJECT_ID(N'dbo.Studies', N'U') IS NOT NULL
        DROP TABLE dbo.Studies;

    IF OBJECT_ID(N'dbo.DiseaseAreas', N'U') IS NOT NULL
        DROP TABLE dbo.DiseaseAreas;

    IF OBJECT_ID(N'dbo.Authors', N'U') IS NOT NULL
        DROP TABLE dbo.Authors;

    IF OBJECT_ID(N'dbo.ProjectManagers', N'U') IS NOT NULL
        DROP TABLE dbo.ProjectManagers;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
