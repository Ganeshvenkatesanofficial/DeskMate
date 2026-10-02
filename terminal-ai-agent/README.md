# FileLens Terminal AI Agent

## Backend

Run the FastAPI backend from the `terminal-ai-agent` folder:

```bash
cd d:/FileLens/terminal-ai-agent
d:/FileLens/.venv/Scripts/python.exe -m uvicorn backend:app --reload --host 127.0.0.1 --port 8000
```

## Frontend

The React Vite UI lives in `terminal-ai-agent/frontend`.

You need Node.js installed to run the frontend locally.

```bash
cd d:/FileLens/terminal-ai-agent/frontend
npm install
npm run dev
```

Set `VITE_BACKEND_URL` in `frontend/.env` if your backend is running on a different host or port.
