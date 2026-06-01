# Server

FastAPI backend for NoteRun. Handles auth, progress sync, leaderboard, and AI game analysis.

## Setup

Requires Python 3.11+.

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## Running

```bash
export JWT_SECRET=your_random_secret_here
uvicorn main:app --host 0.0.0.0 --port 8000
```

Generate a secret with `openssl rand -hex 32`.

## Production (systemd)

Copy and edit the service file:

```bash
cp noterun.service /etc/systemd/system/
# edit User, WorkingDirectory, JWT_SECRET inside the file
systemctl enable --now noterun
```

## Ollama (AI analysis)

```bash
curl -fsSL https://ollama.com/install.sh | sh
ollama pull phi3:mini
```

Ollama runs on `127.0.0.1:11434` by default. If it's not running the `/analyze` endpoint will fail but everything else works fine.

## Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/auth/register` | — | register, returns JWT |
| POST | `/auth/login` | — | login, returns JWT |
| GET | `/auth/me` | ✓ | current user info |
| GET | `/progress` | ✓ | get progress |
| POST | `/progress` | ✓ | sync progress (merge, best wins) |
| POST | `/leaderboard/submit` | ✓ | submit score |
| GET | `/leaderboard/{mode}` | ✓ | top 50 for mode |
| POST | `/analyze` | ✓ | submit game for AI analysis, returns task_id |
| GET | `/analyze/{task_id}` | ✓ | poll analysis status |