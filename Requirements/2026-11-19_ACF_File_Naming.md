Right after ACF data extraction and processing:
	[OriginalFileName] - exact file name that was uploaded
	[FileName] - Made up name following client's naming convention (ACF_[Date]_[Publication])
	[FileURL] - URL to SharePoint in Staging area


When ACF Confirm button is clicked:
	[OriginalFileName] - no change, stays the same forever
	[FileName] - User could change it, but it's locked if Publication status is NOT "Pending PM Review"
	[FileURL] - File renamed from [OriginalFileName] to [FileName] and placed in the permanent SharePoint area

---------------------------------------------------------------------------------------------------------------

Additional comments:
- Extension should not be exposed and cannot be overwritten by the user
- If a file with the same name exist in permanent SharePoint area - show an error on "Confirm" button click

---------------------------------------------------------------------------------------------------------------

Field associations:
- [Document Name] field on ACF/Publication validation form = [FileName] from the DB; 
- Document info title should be 'Document Information - [OriginalFileName]'

---------------------------------------------------------------------------------------------------------------

Dashboard view:
[Document field] = [OriginalFileName] if PublicationStatus == 'Pending PM Review' else [FileName]

