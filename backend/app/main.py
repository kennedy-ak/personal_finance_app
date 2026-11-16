"""Personal Finance backend — the FastAPI replacement for Supabase.

One server for both clients (the Flutter app and web/). It owns auth, the
ledger tables, the SMS import guarantees and the coach proxy; the financial
reasoning stays in the clients' money engines, exactly as before.

Run it:
    cd backend
    python -m venv .venv && .venv\\Scripts\\pip install -r requirements.txt
    .venv\\Scripts\\uvicorn app.main:app --host 0.0.0.0 --port 8000
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .db import engine
from .models import Base
from .routers import accounts, auth, categories, coach, goals, obligations, sms, transactions

app = FastAPI(title="Personal Finance API", version="1.0.0")

origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins or ["*"],
    allow_credentials=False,  # bearer tokens, not cookies
    allow_methods=["*"],
    allow_headers=["*"],
)

# A personal server migrates by just creating what is missing.
Base.metadata.create_all(bind=engine)

app.include_router(auth.router)
app.include_router(accounts.router)
app.include_router(transactions.router)
app.include_router(obligations.router)
app.include_router(goals.router)
app.include_router(categories.router)
app.include_router(coach.router)
app.include_router(sms.router)


@app.get("/health")
def health():
    return {"ok": True}
