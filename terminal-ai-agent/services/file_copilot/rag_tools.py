"""
services.file_copilot.rag_tools — Semantic Search & RAG Vector Tools
====================================================================
Offline vector indexing and semantic retrieval powered by local Qdrant and FastEmbed.
"""

from pathlib import Path
from smolagents import Tool

try:
    from qdrant_client import QdrantClient
except ImportError:
    class _DummyQdrantClient:
        def __init__(self, *args, **kwargs):
            pass
        def collection_exists(self, collection_name: str) -> bool:
            return False
        def add(self, *args, **kwargs):
            pass
        def query(self, *args, **kwargs):
            return []
    QdrantClient = _DummyQdrantClient

from core.config import get_user_data_dir

# Storage directory for Qdrant database (guaranteed-writable location)
QDRANT_PATH = str(get_user_data_dir() / ".qdrant_data")
COLLECTION_NAME = "local_documents"

_client = None

def get_qdrant_client():
    """Lazy initializer for Qdrant client."""
    global _client
    if _client is None:
        from qdrant_client import QdrantClient
        _client = QdrantClient(path=QDRANT_PATH)
    return _client

def chunk_text(text: str, chunk_size: int = 1000, overlap: int = 200) -> list[str]:
    """Simple text chunking utility."""
    chunks = []
    for i in range(0, len(text), max(1, chunk_size - overlap)):
        chunks.append(text[i : i + chunk_size])
    return chunks

class IndexDocumentTool(Tool):
    name = "index_document"
    description = "Reads a text-based file, chunks it, and indexes it into the local Qdrant database using local embeddings."
    inputs = {
        "file_path": {
            "type": "string",
            "description": "The absolute or relative path to the file to index.",
        }
    }
    output_type = "string"

    def forward(self, file_path: str) -> str:
        try:
            path = Path(file_path).resolve()
            if not path.is_file():
                return f"Error: '{file_path}' is not a valid file."

            with open(path, "r", encoding="utf-8") as f:
                content = f.read()

            chunks = chunk_text(content)
            documents = [{"text": chunk, "source": str(path.name)} for chunk in chunks]

            get_qdrant_client().add(
                collection_name=COLLECTION_NAME,
                documents=[doc["text"] for doc in documents],
                metadata=[{"source": doc["source"]} for doc in documents],
            )
            return f"Successfully indexed {len(chunks)} chunks from '{path.name}' into Qdrant vector database."
        except Exception as e:
            return f"Error indexing document: {str(e)}"

class SearchQdrantTool(Tool):
    name = "search_qdrant"
    description = "Searches the local Qdrant database for semantic context relevant to the query."
    inputs = {
        "query": {
            "type": "string",
            "description": "The semantic search query string.",
        },
        "limit": {
            "type": "integer",
            "description": "The maximum number of relevant chunks to retrieve. Default is 3.",
            "nullable": True,
        },
    }
    output_type = "string"

    def forward(self, query: str, limit: int = 3) -> str:
        try:
            client = get_qdrant_client()
            if not client.collection_exists(COLLECTION_NAME):
                return "No documents have been indexed yet. Please use the 'index_document' tool first."

            results = client.query(
                collection_name=COLLECTION_NAME,
                query_text=query,
                limit=limit,
            )

            if not results:
                return "No relevant context found in the vector database."

            context = []
            for i, res in enumerate(results):
                source = res.metadata.get("source", "Unknown")
                text = getattr(res, "document", res.metadata.get("document", str(res)))
                context.append(f"--- Result {i+1} (Source: {source}) ---\n{text}\n")

            return "\n".join(context)
        except Exception as e:
            return f"Error searching Qdrant: {str(e)}"

index_document = IndexDocumentTool()
search_qdrant = SearchQdrantTool()
