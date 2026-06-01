import os, uuid, bcrypt
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import FastAPI, Depends, HTTPException, status, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from pydantic import BaseModel, EmailStr, field_validator
from jose import JWTError, jwt
from sqlalchemy import create_engine, Column, String, DateTime, JSON, Integer
from sqlalchemy.orm import declarative_base, sessionmaker, Session
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

# ── Consts ────────────────────────────────────────────────────────────────────
SECRET_KEY  = os.environ.get("JWT_SECRET", "CHANGE_ME_IN_PRODUCTION_USE_RANDOM_64_CHARS")
ALGORITHM   = "HS256"
TOKEN_DAYS  = 30

DATABASE_URL = "sqlite:///./noterun.db"

# ── DB ────────────────────────────────────────────────────────────────────
engine  = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
Session_ = sessionmaker(bind=engine, autoflush=False, autocommit=False)
Base    = declarative_base()

class User(Base):
    __tablename__ = "users"
    id         = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    email      = Column(String, unique=True, nullable=False, index=True)
    username   = Column(String, nullable=False)
    password   = Column(String, nullable=False)   # bcrypt hash
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    progress   = Column(JSON, default=dict)        # campaign, scales, chords

class LeaderboardEntry(Base):
    __tablename__ = "leaderboard"
    id         = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id    = Column(String, nullable=False, index=True)
    username   = Column(String, nullable=False)
    mode       = Column(String, nullable=False, index=True)  # "sight_reading" | "campaign_N"
    score      = Column(Integer, nullable=False)
    updated_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

Base.metadata.create_all(engine)

limiter = Limiter(key_func=get_remote_address)

# ── app ────────────────────────────────────────────────────────────────────
app = FastAPI(title="NoteRun API", version="1.0")
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.add_middleware(CORSMiddleware,
    allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

oauth2 = OAuth2PasswordBearer(tokenUrl="/auth/login")

def get_db():
    db = Session_()
    try:
        yield db
    finally:
        db.close()

def hash_password(plain: str) -> str:
    return bcrypt.hashpw(plain.encode(), bcrypt.gensalt(rounds=12)).decode()

def verify_password(plain: str, hashed: str) -> bool:
    return bcrypt.checkpw(plain.encode(), hashed.encode())

def create_token(user_id: str) -> str:
    exp = datetime.now(timezone.utc) + timedelta(days=TOKEN_DAYS)
    return jwt.encode({"sub": user_id, "exp": exp}, SECRET_KEY, algorithm=ALGORITHM)

def current_user(token: str = Depends(oauth2), db: Session = Depends(get_db)) -> User:
    exc = HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid token")
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        uid = payload.get("sub")
        if not uid:
            raise exc
    except JWTError:
        raise exc
    user = db.query(User).filter(User.id == uid).first()
    if not user:
        raise exc
    return user

# ── Schemas ────────────────────────────────────────────────────────────────────
class RegisterIn(BaseModel):
    email:    str
    username: str
    password: str

    @field_validator("password")
    @classmethod
    def pw_length(cls, v):
        if len(v) < 6:
            raise ValueError("Password must be at least 6 characters")
        return v

class TokenOut(BaseModel):
    access_token: str
    token_type:   str = "bearer"
    user_id:      str
    username:     str

class ProgressIn(BaseModel):
    campaign:     dict = {}   # {"1": {"best": 97, "history": [80,90,97]}, ...}
    scales:       dict = {}   # {"c_major": {"done": true, "perfect": false}}
    chords:       dict = {}   # {"c_maj": {"done": true}}
    sight_reading: dict = {}  # {"best": 42}

class LeaderboardIn(BaseModel):
    mode:  str   # "sight_reading" | "campaign_1" ... "campaign_5"
    score: int

class LeaderboardRow(BaseModel):
    rank:       int
    username:   str
    score:      int
    is_me:      bool
    updated_at: str

# ── auth ────────────────────────────────────────────────────────────────────
@app.post("/auth/register", response_model=TokenOut)
@limiter.limit("5/minute")
def register(request: Request, body: RegisterIn, db: Session = Depends(get_db)):
    if db.query(User).filter(User.email == body.email.lower()).first():
        raise HTTPException(400, "Email already registered")
    user = User(
        email    = body.email.lower(),
        username = body.username.strip(),
        password = hash_password(body.password),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return TokenOut(access_token=create_token(user.id),
                    user_id=user.id, username=user.username)

@app.post("/auth/login", response_model=TokenOut)
@limiter.limit("10/minute")
def login(request: Request,
          form: OAuth2PasswordRequestForm = Depends(),
          db:   Session = Depends(get_db)):
    user = db.query(User).filter(User.email == form.username.lower()).first()
    if not user or not verify_password(form.password, user.password):
        raise HTTPException(401, "Wrong email or password")
    return TokenOut(access_token=create_token(user.id),
                    user_id=user.id, username=user.username)

@app.get("/auth/me")
def me(user: User = Depends(current_user)):
    return {"id": user.id, "email": user.email, "username": user.username,
            "created_at": user.created_at}

# ── Progress ───────────────────────────────────────────────────────────
@app.get("/progress")
def get_progress(user: User = Depends(current_user)):
    return user.progress or {}

@app.post("/progress")
def save_progress(body: ProgressIn,
                  user: User = Depends(current_user),
                  db:   Session = Depends(get_db)):
    """Merge client progress with server, keep best values!"""
    srv = user.progress or {}

    # campaign
    for lvl, data in body.campaign.items():
        s = srv.setdefault("campaign", {}).setdefault(lvl, {})
        if data.get("best", 0) > s.get("best", 0):
            s["best"] = data["best"]
        if "history" in data:
            s["history"] = data["history"]

    # Scales
    for key, data in body.scales.items():
        s = srv.setdefault("scales", {}).setdefault(key, {})
        s["done"]    = s.get("done", False)    or data.get("done", False)
        s["perfect"] = s.get("perfect", False) or data.get("perfect", False)

    # chords
    for key, data in body.chords.items():
        s = srv.setdefault("chords", {}).setdefault(key, {})
        s["done"] = s.get("done", False) or data.get("done", False)

    # Sight reading best
    sr = body.sight_reading.get("best", 0)
    if sr > srv.setdefault("sight_reading", {}).get("best", 0):
        srv["sight_reading"]["best"] = sr

    from sqlalchemy.orm.attributes import flag_modified
    user.progress = srv
    flag_modified(user, "progress")
    db.commit()
    return {"ok": True, "progress": user.progress}

# ── Leaderboard ────────────────────────────────────────────────────────
VALID_MODES = {"sight_reading"} | {f"campaign_{i}" for i in range(1, 6)}

@app.post("/leaderboard/submit")
def submit_score(body: LeaderboardIn,
                 user: User = Depends(current_user),
                 db:   Session = Depends(get_db)):
    if body.mode not in VALID_MODES:
        raise HTTPException(400, "Invalid mode")
    entry = db.query(LeaderboardEntry).filter(
        LeaderboardEntry.user_id == user.id,
        LeaderboardEntry.mode    == body.mode,
    ).first()
    if entry:
        if body.score > entry.score:
            entry.score      = body.score
            entry.updated_at = datetime.now(timezone.utc)
            db.commit()
    else:
        db.add(LeaderboardEntry(
            user_id=user.id, username=user.username,
            mode=body.mode, score=body.score))
        db.commit()
    return {"ok": True}

@app.get("/leaderboard/{mode}", response_model=list[LeaderboardRow])
def get_leaderboard(mode: str,
                    user: User = Depends(current_user),
                    db:   Session = Depends(get_db)):
    if mode not in VALID_MODES:
        raise HTTPException(400, "Invalid mode")
    rows = (db.query(LeaderboardEntry)
            .filter(LeaderboardEntry.mode == mode)
            .order_by(LeaderboardEntry.score.desc())
            .limit(50).all())
    result = []
    for i, row in enumerate(rows):
        result.append(LeaderboardRow(
            rank       = i + 1,
            username   = row.username,
            score      = row.score,
            is_me      = row.user_id == user.id,
            updated_at = row.updated_at.strftime("%d.%m.%Y"),
        ))
    return result

@app.get("/")
def root():
    return {"status": "NoteRun API running"}

# ── LLM─────────────────────────────────────
import asyncio, httpx, uuid as _uuid
from enum import Enum

class TaskStatus(str, Enum):
    pending  = "pending"
    running  = "running"
    done     = "done"
    error    = "error"

class AnalyzeTask:
    def __init__(self, task_id: str, prompt: str):
        self.task_id = task_id
        self.prompt  = prompt
        self.status  = TaskStatus.pending
        self.advice  : str | None = None
        self.error   : str | None = None

# In-memory store (survives uvicorn reload, lost on restart — acceptable)
_tasks:  dict[str, AnalyzeTask] = {}
_queue:  asyncio.Queue

async def _llm_worker():
    """Single background worker — processes one LLM request at a time."""
    while True:
        task: AnalyzeTask = await _queue.get()
        task.status = TaskStatus.running
        try:
            async with httpx.AsyncClient(timeout=180.0) as client:
                resp = await client.post(
                    "http://127.0.0.1:11434/api/generate",
                    json={"model": "phi3:mini", "prompt": task.prompt,
                          "stream": False},
                )
            resp.raise_for_status()
            task.advice = resp.json().get("response", "").strip()
            task.status = TaskStatus.done
        except Exception as e:
            task.error  = str(e)
            task.status = TaskStatus.error
        finally:
            _queue.task_done()
            # Keep only last 200 tasks in memory
            if len(_tasks) > 200:
                oldest = list(_tasks.keys())[0]
                _tasks.pop(oldest, None)

@app.on_event("startup")
async def _startup():
    global _queue
    _queue = asyncio.Queue()
    asyncio.create_task(_llm_worker())

class AnalyzeIn(BaseModel):
    piece_name:   str
    bpm:          int
    hit_pct:      float
    missed_notes: list[str]
    late_notes:   list[str]
    avg_delay_ms: int

@app.post("/analyze")
@limiter.limit("5/minute")
async def analyze_submit(request: Request, body: AnalyzeIn,
                         user: User = Depends(current_user)):
    missed_str = ", ".join(body.missed_notes) if body.missed_notes else "нет"
    late_str   = ", ".join(body.late_notes)   if body.late_notes   else "нет"

    prompt = (
        "Ты тренер по игре на фортепиано. "
        "Дай короткий конкретный совет на русском языке (3-5 предложений).\n\n"
        f"Результаты игры:\n"
        f"- Произведение: {body.piece_name}\n"
        f"- Темп: {body.bpm} BPM\n"
        f"- Точность: {body.hit_pct:.0f}%\n"
        f"- Пропущенные ноты: {missed_str}\n"
        f"- Ноты с опозданием (>150мс): {late_str}\n"
        f"- Средняя задержка: {body.avg_delay_ms} мс\n\n"
        "Что могло пойти не так и как это исправить?"
    )

    task_id = str(_uuid.uuid4())
    task    = AnalyzeTask(task_id, prompt)
    _tasks[task_id] = task
    await _queue.put(task)

    queue_pos = _queue.qsize()
    return {"task_id": task_id, "queue_position": queue_pos}

@app.get("/analyze/{task_id}")
async def analyze_status(task_id: str, user: User = Depends(current_user)):
    task = _tasks.get(task_id)
    if task is None:
        raise HTTPException(404, "Task not found")
    resp: dict = {"task_id": task_id, "status": task.status}
    if task.status == TaskStatus.done:
        resp["advice"] = task.advice
    elif task.status == TaskStatus.error:
        resp["error"] = task.error
    return resp
