import json
from functools import wraps
import logging
import os
import re
from datetime import date
from pathlib import Path

import azure.functions as func
import pyodbc
from azure.core.credentials import AzureKeyCredential
from azure.search.documents import SearchClient
from dotenv import load_dotenv

load_dotenv(Path(__file__).with_name(".env"))

app = func.FunctionApp()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(name)s | %(levelname)-7s | %(message)s",
    # format="%(asctime)s | %(levelname)-7s | %(message)s",
    force=True,  # reconfigure cleanly if the cell is re-run
)


excluded_log_namespaces = ['azure.core.pipeline.policies.http_logging_policy']

for namespace in excluded_log_namespaces:
    logging.getLogger(namespace).setLevel(logging.WARNING)

logging.info("Azure function invocation started.")
# logger = logging.getLogger("function_app")

# Placeholder data. Replace with your real study data source.
PUBLICATIONS = {
    "1": {"id": "1", "name": "Study A", "year": 2020},
    "2": {"id": "2", "name": "Study B", "year": 2021},
}

STUDY_TOOL_PROPERTIES = json.dumps([
    {
        "propertyName": "publication_id",
        "propertyType": "string",
        "description": "The id of the publication to look up.",
    },
    {
        "propertyName": "publication_name",
        "propertyType": "string",
        "description": "The name of the publication to look up.",
    }
])


@app.generic_trigger(
    arg_name="context",
    type="mcpToolTrigger",
    toolName="get_publication",
    description="Get a publication record by optional id and/or name.",
    toolProperties=STUDY_TOOL_PROPERTIES,
)
def get_publication(context: str) -> str:
    logging.info(f"Processing get_publication request with context: {context}")
    args = json.loads(context).get("arguments", {})
    study_id = args.get("publication_id")
    study_name = args.get("publication_name")

    if study_id is None and study_name is None:
        matches = list(PUBLICATIONS.values())
        logging.info("get_publication returned %d result(s).", len(matches))
        return json.dumps(matches)

    matches = list(PUBLICATIONS.values())
    if study_id is not None:
        matches = [study for study in matches if study["id"] == study_id]
    if study_name is not None:
        normalized_name = study_name.casefold()
        matches = [study for study in matches if study["name"].casefold() == normalized_name]

    logging.info("get_publication returned %d result(s).", len(matches))
    return json.dumps(matches[0] if matches else {"error": "publication not found"})


@app.mcp_tool()
def get_author(author_name: str) -> str:
    """
    Search authors by name.
    Match either supplied name and return up to 10 complete search results.
    With neither name supplied, return the first 10 authors.
    """
    logging.info(f"Executing get_author search request for author_name: {author_name}")
    clauses = [
        f"{term}~2"
        for term in re.findall(r"\w{2,}", author_name)
    ]
    search_text = " ".join(clauses) if clauses else "*"
    logging.info(f"get_author search request: {search_text}")

    api_key = os.getenv("AZURE_SEARCH_API_KEY")
    if not api_key:
        logging.error("AZURE_SEARCH_API_KEY is not configured.")
        raise ValueError("Set AZURE_SEARCH_API_KEY in .env before using get_author.")
    search_name = os.getenv("AZURE_SEARCH_NAME")
    index_name = os.getenv("AZURE_SEARCH_AUTHORS_INDEX_NAME")
    if not search_name or not index_name:
        logging.error("Azure Search name or authors index is not configured.")
        raise ValueError("Set AZURE_SEARCH_NAME and AZURE_SEARCH_AUTHORS_INDEX_NAME in local.settings.json.")

    try:
        with SearchClient(
            endpoint=f"https://{search_name}.search.windows.net",
            index_name=index_name,
            credential=AzureKeyCredential(api_key),
        ) as client:
            results = client.search(
                search_text=search_text,
                query_type="full",
                search_mode="any",
                # search_fields=["first_name", "last_name"],
                search_fields=["firstname", "lastname"],
                # search_fields="firstname,lastname,email",
                # select="authorid,firstname,lastname,title,email",
                select=["authorid","firstname","lastname","title","email"],
                top=10)
            authors = list(results)
            logging.info("get_author returned %d result(s).", len(authors))
            return json.dumps(authors)
    except Exception:
        logging.exception("get_author failed while querying Azure AI Search.")
        raise


@app.mcp_tool()
def get_study(study_name: str) -> str:
    """
    Search studies by title.
    Match supplied name and return up to 10 complete search results.
    """
    logging.info(f"Executing get_study search request for study_name: {study_name}")
    clauses = [
        f"{term}~2"
        for term in re.findall(r"\w{2,}", study_name)
    ]
    search_text = " ".join(clauses) if clauses else "*"
    logging.info(f"get_study search request: {search_text}")

    api_key = os.getenv("AZURE_SEARCH_API_KEY")
    if not api_key:
        logging.error("AZURE_SEARCH_API_KEY is not configured.")
        raise ValueError("Set AZURE_SEARCH_API_KEY in .env before using get_study.")
    search_name = os.getenv("AZURE_SEARCH_NAME")
    index_name = os.getenv("AZURE_SEARCH_STUDIES_INDEX_NAME")
    if not search_name or not index_name:
        logging.error("Azure Search name or studies index is not configured.")
        raise ValueError("Set AZURE_SEARCH_NAME and AZURE_SEARCH_STUDIES_INDEX_NAME in local.settings.json.")

    try:
        with SearchClient(
            endpoint=f"https://{search_name}.search.windows.net",
            index_name=index_name,
            credential=AzureKeyCredential(api_key),
        ) as client:
            results = client.search(
                search_text=search_text,
                query_type="full",
                search_mode="any",
                search_fields=["studytitle"],
                select=["studyid","studytitle","diseaseareaname"],
                top=10)
            studies = list(results)
            logging.info("get_study returned %d result(s).", len(studies))
            return json.dumps(studies)
    except Exception:
        logging.exception("get_study failed while querying Azure AI Search.")
        raise


def _parse_sql_id(value, field_name, nullable=False):
    if value is None and nullable:
        return None
    if isinstance(value, bool) or not isinstance(value, (str, int)):
        raise ValueError(f"{field_name} must be a positive integer or null.")
    try:
        parsed_value = int(value)
    except ValueError as error:
        raise ValueError(f"{field_name} must be a positive integer or null.") from error
    if parsed_value < 1 or parsed_value > 2147483647:
        raise ValueError(f"{field_name} must be a positive SQL int or null.")
    return parsed_value


def _optional_text(value, field_name, max_length):
    if value is None or value == "":
        return None
    if not isinstance(value, str):
        raise ValueError(f"{field_name} must be a string or null.")
    if len(value) > max_length:
        raise ValueError(f"{field_name} must be {max_length} characters or fewer.")
    return value


def _required_text(value, field_name, max_length=None):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field_name} must be a non-empty string.")
    if max_length is not None and len(value) > max_length:
        raise ValueError(f"{field_name} must be {max_length} characters or fewer.")
    return value


def _parse_json_object(value, field_name):
    try:
        parsed_value = json.loads(value)
    except (json.JSONDecodeError, TypeError) as error:
        raise ValueError(f"{field_name} must be a valid JSON string.") from error
    if not isinstance(parsed_value, dict):
        raise ValueError(f"{field_name} must contain a JSON object.")
    return parsed_value


def _parse_document_author(document):
    author = document.get("author")
    if not isinstance(author, dict):
        raise ValueError("author must be an object.")
    return {
        "author_id": _parse_sql_id(author.get("authorid"), "author.authorid", nullable=True),
        "firstname": _required_text(author.get("firstname"), "author.firstname", 100),
        "lastname": _required_text(author.get("lastname"), "author.lastname", 100),
    }


def _parse_document_date(value):
    if value is None or value == "":
        return None
    if not isinstance(value, str):
        raise ValueError("date must use YYYY-MM-DD or be null.")
    try:
        return date.fromisoformat(value)
    except ValueError as error:
        raise ValueError("date must use YYYY-MM-DD or be null.") from error


def _return_tool_errors(tool_name, action="save"):
    def decorate(handler):
        @wraps(handler)
        def wrapped(*args, **kwargs):
            try:
                return handler(*args, **kwargs)
            except (TypeError, ValueError) as error:
                return f"Invalid {tool_name} request: {error}"
            except RuntimeError as error:
                return f"Unable to process {tool_name} request: {error}"
            except Exception:
                logging.exception("Failed to process %s request.", tool_name)
                no_records_saved = "No records were saved; " if action == "save" else ""
                return f"Unable to {action} {tool_name}: {no_records_saved}check the database schema and connection."
        return wrapped
    return decorate


def _query_sql_json(query, *parameters):
    connection_string = os.getenv("AZURE_SQL_CONNECTION_STRING")
    if not connection_string:
        raise RuntimeError("Set AZURE_SQL_CONNECTION_STRING in local.settings.json or Azure Function App settings.")

    connection = None
    cursor = None
    try:
        connection = pyodbc.connect(connection_string, autocommit=True)
        cursor = connection.cursor()
        cursor.execute(query, *parameters)
        column_names = [column[0] for column in cursor.description]
        rows = [dict(zip(column_names, row)) for row in cursor.fetchall()]
        return json.dumps(rows, default=str)
    finally:
        if cursor is not None:
            cursor.close()
        if connection is not None:
            connection.close()


@app.mcp_tool()
@_return_tool_errors("active publications", action="retrieve")
def get_active_publications() -> str:
    """List active publications from dbo.vw_ActivePublications."""
    return _query_sql_json(
        """
        SELECT *
        FROM dbo.vw_ActivePublications
        ORDER BY ModifiedOn DESC
        """
    )


@app.mcp_tool()
@_return_tool_errors("publication authors", action="retrieve")
def get_publication_authors(publication_id: int) -> str:
    """List a publication's authors with their agreement and COI status."""
    parsed_publication_id = _parse_sql_id(publication_id, "publication_id")
    return _query_sql_json(
        """
        SELECT *
        FROM dbo.vw_PublicationAuthorDocumentStatus
        WHERE PublicationID = ?
        ORDER BY AuthorOrder
        """,
        parsed_publication_id,
    )


@app.mcp_tool()
@_return_tool_errors("author agreement")
def save_author_agreement(author_agreement_object: str) -> str:
    """Save an author agreement in JSON format."""
    agreement = _parse_json_object(author_agreement_object, "author_agreement_object")
    study = agreement.get("study")
    if not isinstance(study, dict):
        raise ValueError("study must be an object.")
    study_id = _parse_sql_id(study.get("id"), "study.id", nullable=True)
    study_name = _required_text(study.get("name"), "study.name", 500)
    author = _parse_document_author(agreement)
    file_name = _required_text(agreement.get("filename"), "filename", 260)
    document_date = _parse_document_date(agreement.get("date"))

    connection_string = os.getenv("AZURE_SQL_CONNECTION_STRING")
    if not connection_string:
        raise RuntimeError("Set AZURE_SQL_CONNECTION_STRING in local.settings.json or Azure Function App settings.")

    connection = None
    cursor = None
    try:
        connection = pyodbc.connect(connection_string, autocommit=False)
        cursor = connection.cursor()
        agreement_id = cursor.execute(
            """
            INSERT INTO dbo.AuthorAgreements
                (StudyID, StudyExtractedName, AuthorID, AuthorExtractedFirstName,
                 AuthorExtractedLastName, DocumentDate, FileName, Status)
            OUTPUT INSERTED.AAID
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            study_id,
            study_name,
            author["author_id"],
            author["firstname"],
            author["lastname"],
            document_date,
            file_name,
            "Pending PM Review"
        ).fetchone()[0]
        connection.commit()
        logging.info("Saved author agreement %s.", agreement_id)
        return f"Successfully saved author agreement ID: {agreement_id}."
    except Exception:
        if connection is not None:
            connection.rollback()
        raise
    finally:
        if cursor is not None:
            cursor.close()
        if connection is not None:
            connection.close()


@app.mcp_tool()
@_return_tool_errors("COI")
def save_coi(coi_object: str) -> str:
    """Save a COI and its entity/relationship disclosures from the agent instruction JSON format."""
    coi = _parse_json_object(coi_object, "coi_object")
    manuscript_title = _required_text(coi.get("manuscript_title"), "manuscript_title", 500)
    manuscript_number = _optional_text(coi.get("manuscript_number"), "manuscript_number", 100)
    file_name = _required_text(coi.get("filename"), "filename", 260)
    author = _parse_document_author(coi)

    disclosures = coi.get("disclosures")
    if not isinstance(disclosures, list):
        raise ValueError("disclosures must be a list.")
    validated_disclosures = []
    for index, disclosure in enumerate(disclosures):
        if not isinstance(disclosure, dict):
            raise ValueError(f"disclosures[{index}] must be an object.")
        validated_disclosures.append({
            "entity": _required_text(disclosure.get("entity"), f"disclosures[{index}].entity"),
            "relationship": _required_text(
                disclosure.get("relationship"), f"disclosures[{index}].relationship"
            ),
        })

    connection_string = os.getenv("AZURE_SQL_CONNECTION_STRING")
    if not connection_string:
        raise RuntimeError("Set AZURE_SQL_CONNECTION_STRING in local.settings.json or Azure Function App settings.")

    connection = None
    cursor = None
    try:
        connection = pyodbc.connect(connection_string, autocommit=False)
        cursor = connection.cursor()
        coi_id = cursor.execute(
            """
            INSERT INTO dbo.COIs
                (DiseaseAreaID, AuthorID, AuthorExtractedFirstName, AuthorExtractedLastName,
                 ManuscriptTitle, ManuscriptNumber, FileName, Status)
            OUTPUT INSERTED.COIID
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            None,
            author["author_id"],
            author["firstname"],
            author["lastname"],
            manuscript_title,
            manuscript_number,
            file_name,
            "Pending PM Review"
        ).fetchone()[0]

        for disclosure in validated_disclosures:
            cursor.execute(
                """
                INSERT INTO dbo.COIDisclosures (COIID, EntityData, RelationshipData)
                VALUES (?, ?, ?)
                """,
                coi_id,
                disclosure["entity"],
                disclosure["relationship"],
            )

        connection.commit()
        logging.info("Saved COI %s with %d disclosure(s).", coi_id, len(validated_disclosures))
        return f"Successfully saved COI ID: {coi_id} with {len(validated_disclosures)} disclosure(s)."
    except Exception:
        if connection is not None:
            connection.rollback()
        raise
    finally:
        if cursor is not None:
            cursor.close()
        if connection is not None:
            connection.close()


@app.mcp_tool()
@_return_tool_errors("publication")
def save_publication(publication_object: str) -> str:
    """Save a publication, its new authors, and ordered author links in Azure SQL."""
    try:
        publication = json.loads(publication_object)
    except (json.JSONDecodeError, TypeError) as error:
        raise ValueError("publication_object must be a valid JSON string.") from error
    if not isinstance(publication, dict):
        raise ValueError("publication_object must contain a JSON object.")

    publication_title = publication.get("publication")
    if not isinstance(publication_title, str) or not publication_title.strip():
        raise ValueError("publication must be a non-empty title string.")
    if len(publication_title) > 500:
        raise ValueError("publication must be 500 characters or fewer.")

    study = publication.get("study")
    if study is None:
        study = {}
    if not isinstance(study, dict):
        raise ValueError("study must be an object or null.")
    study_id = _parse_sql_id(study.get("id"), "study.id", nullable=True)

    authors = publication.get("authors")
    if not isinstance(authors, list):
        raise ValueError("authors must be a list.")

    validated_authors = []
    seen_placements = set()
    seen_author_ids = set()
    for author in authors:
        if not isinstance(author, dict):
            raise ValueError("Each author must be an object.")
        first_name = _optional_text(author.get("firstname"), "author.firstname", 100)
        last_name = _optional_text(author.get("lastname"), "author.lastname", 100)
        if not first_name or not last_name:
            raise ValueError("Each author must have non-empty firstname and lastname values.")

        author_id = _parse_sql_id(author.get("authorid"), "author.authorid", nullable=True)
        placement = _parse_sql_id(author.get("placement"), "author.placement")
        if placement in seen_placements:
            raise ValueError("Author placement values must be unique.")
        seen_placements.add(placement)
        if author_id is not None:
            if author_id in seen_author_ids:
                raise ValueError("An author cannot appear more than once in the author list.")
            seen_author_ids.add(author_id)

        validated_authors.append({
            "author_id": author_id,
            "firstname": first_name,
            "lastname": last_name,
            "affiliation": _optional_text(author.get("institution"), "author.institution", 500),
            "citystate": _optional_text(author.get("citystate"), "author.citystate", 200),
            "country": _optional_text(author.get("country"), "author.country", 100),
            "placement": placement,
        })

    connection_string = os.getenv("AZURE_SQL_CONNECTION_STRING")
    if not connection_string:
        raise RuntimeError("Set AZURE_SQL_CONNECTION_STRING in local.settings.json or Azure Function App settings.")

    file_name = _optional_text(publication.get("filename"), "filename", 260)
    if file_name is None:
        file_name = publication_title[:260]

    connection = None
    cursor = None
    try:
        connection = pyodbc.connect(connection_string, autocommit=False)
        cursor = connection.cursor()

        publication_id = cursor.execute(
            """
            INSERT INTO dbo.Publications (StudyID, PublicationTitle, FileName, Status)
            OUTPUT INSERTED.PublicationID
            VALUES (?, ?, ?, ?)
            """,
            study_id,
            publication_title,
            file_name,
            "Pending PM Review"
        ).fetchone()[0]

        for author in validated_authors:
            author_id = author["author_id"]
            if author_id is None:
                author_id = cursor.execute(
                    """
                    INSERT INTO dbo.Authors (FirstName, LastName, Affiliation, CityState, Country, AuthorType)
                    OUTPUT INSERTED.AuthorID
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    author["firstname"],
                    author["lastname"],
                    author["affiliation"],
                    author["citystate"],
                    author["country"],
                    "Autogenerated"
                ).fetchone()[0]

            cursor.execute(
                """
                INSERT INTO dbo.PublicationAuthors (PublicationID, AuthorID, AuthorOrder)
                VALUES (?, ?, ?)
                """,
                publication_id,
                author_id,
                author["placement"],
            )

        connection.commit()
        logging.info(
            "Saved publication %s with %d author link(s).",
            publication_id,
            len(validated_authors),
        )
        return f"Successfully saved publication ID: {publication_id} with {len(validated_authors)} author(s)."
    except Exception:
        if connection is not None:
            connection.rollback()
        raise
    finally:
        if cursor is not None:
            cursor.close()
        if connection is not None:
            connection.close()
