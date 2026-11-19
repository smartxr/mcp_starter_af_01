If the agent extracts ACF data and is unable to find Study match (new study):  
```Publication.StudyID = Null; Publication.StudyName = "New study name from ACF"```  
Nothing getting written to Studies

If the agent was able to match the study to the existing one (Study selected from dropdown):  
```Publication.StudyID = 123; Publication.StudyName = null```  
Study is reference from Studies directory.

---------------------------------------------------------------------------------------------------------------


How this is being presented in the UI (SQL):
```
SELECT 
	COALESCE(s.StudyName, p.StudyName)
FROM Publications [p]
	LEFT JOIN Studies [s] ON p.StudyID = s.StudyID
```

---------------------------------------------------------------------------------------------------------------
How this is converted on confirmation:

If we have a new study on ACF (Publication.StudyID = Null; Publication.StudyName = "New study name from ACF")  
> _when_
>> - the user clicks on Confirm button on ACF/Publication validation form  

> _then_  
>> - Study created in Studies directory with Studies.StudyName taken from Publication.StudyName;  
>> - StudyID of that new study recorded in Publication.StudyID;  
>> - Publication.StudyName set to null (wiped)  

