Affiliation Byline

Create an MCP tool called create_affiliation_byline that takes one mandatory parameter PublicationID.

From that publication ID get all the authors on that publication. Each author has affiliation information (refer to the data schema).

Byline consists of two parts: 1 - is the list of authors. 2 - list of affiliations.

Authors _must_ follow in the same order as they are listed on the publication. List of affiliations should be in the order of author and affiliation appearance. Authors should have a superscript index referencing affiliation from the list. If two or more authors share the same affiliation, affiliations should not appear twice on the list. You can rely on affiliations being spelled identically and consistently.
