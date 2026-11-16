"""The coach: thread memory plus the model proxy.

/coach/complete is the port of supabase/functions/coach — deliberately dumb.
It holds the API key and caps the request; all financial reasoning stays in
the clients' money engines, which call back in with tool results.
"""

from datetime import timedelta

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import settings
from ..db import get_db
from ..models import AiChat, AiMessage, AiThread, User
from ..models import utcnow
from ..security import current_user
from ..serialize import ai_chat_row, ai_message_row, ai_thread_row

router = APIRouter(prefix="/coach", tags=["coach"])

OPENAI_URL = "https://api.openai.com/v1/chat/completions"
MAX_TOKENS = 1500
MAX_MESSAGES = 60


# ---------------------------------------------------------------- complete


class CompleteBody(BaseModel):
    messages: list[dict]
    tools: list[dict] | None = None
    temperature: float | None = None
    max_tokens: int | None = None


@router.post("/complete")
async def complete(body: CompleteBody, _user: User = Depends(current_user)):
    if not settings.openai_api_key:
        raise HTTPException(
            status_code=500,
            detail="The coach is not configured. Set OPENAI_API_KEY in backend/.env.",
        )
    if not body.messages:
        raise HTTPException(status_code=400, detail="No messages supplied.")
    if len(body.messages) > MAX_MESSAGES:
        raise HTTPException(status_code=413, detail="Conversation too long.")

    payload: dict = {
        # The model is chosen server-side; the client does not get to pick
        # something expensive.
        "model": settings.coach_model,
        "messages": body.messages,
        "temperature": body.temperature if body.temperature is not None else 0.4,
        "max_tokens": min(body.max_tokens or 900, MAX_TOKENS),
    }
    if body.tools:
        payload["tools"] = body.tools
        payload["tool_choice"] = "auto"

    try:
        async with httpx.AsyncClient(timeout=60) as client:
            upstream = await client.post(
                OPENAI_URL,
                headers={"Authorization": f"Bearer {settings.openai_api_key}"},
                json=payload,
            )
    except httpx.HTTPError as e:
        raise HTTPException(status_code=502, detail=f"Could not reach the model: {e}")

    if upstream.status_code != 200:
        message = f"Model error ({upstream.status_code})"
        try:
            parsed = upstream.json()
            if isinstance(parsed.get("error"), dict) and parsed["error"].get("message"):
                message = parsed["error"]["message"]
        except ValueError:
            pass
        raise HTTPException(status_code=upstream.status_code, detail=message)

    return upstream.json()


# ---------------------------------------------------------------- threads


class MessageIn(BaseModel):
    role: str
    content: str | None = None
    tool_calls: list | None = None
    tool_call_id: str | None = None
    name: str | None = None
    actions: list | None = None


class SaveTurnBody(BaseModel):
    messages: list[MessageIn]


def _own_thread(db: Session, user: User, thread_id: str) -> AiThread:
    thread = db.get(AiThread, thread_id)
    if thread is None or thread.user_id != user.id:
        raise HTTPException(status_code=404, detail="Thread not found")
    return thread


@router.get("/threads")
def list_threads(user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Newest first, with the first user question as a preview — what the web
    ai-history page used to assemble from a nested select."""
    threads = (
        db.execute(
            select(AiThread)
            .where(AiThread.user_id == user.id)
            .order_by(AiThread.updated_at.desc())
            .limit(50)
        )
        .scalars()
        .all()
    )
    out = []
    for t in threads:
        first_user = db.execute(
            select(AiMessage.content)
            .where(AiMessage.thread_id == t.id, AiMessage.role == "user")
            .order_by(AiMessage.created_at.asc())
            .limit(1)
        ).scalar_one_or_none()
        out.append({**ai_thread_row(t), "preview": first_user})
    return out


@router.get("/threads/current")
def current_thread(user: User = Depends(current_user), db: Session = Depends(get_db)):
    existing = db.execute(
        select(AiThread)
        .where(AiThread.user_id == user.id)
        .order_by(AiThread.updated_at.desc())
        .limit(1)
    ).scalar_one_or_none()
    if existing is not None:
        return {"id": existing.id}
    thread = AiThread(user_id=user.id)
    db.add(thread)
    db.commit()
    return {"id": thread.id}


@router.post("/threads")
def new_thread(user: User = Depends(current_user), db: Session = Depends(get_db)):
    thread = AiThread(user_id=user.id)
    db.add(thread)
    db.commit()
    return {"id": thread.id}


@router.post("/threads/{thread_id}/touch")
def touch_thread(
    thread_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    thread = _own_thread(db, user, thread_id)
    thread.updated_at = utcnow()
    db.commit()
    return {"ok": True}


@router.get("/threads/{thread_id}/messages")
def thread_messages(
    thread_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    _own_thread(db, user, thread_id)
    rows = (
        db.execute(
            select(AiMessage)
            .where(AiMessage.thread_id == thread_id)
            .order_by(AiMessage.created_at.asc())
        )
        .scalars()
        .all()
    )
    return [ai_message_row(m) for m in rows]


@router.post("/threads/{thread_id}/messages")
def save_turn(
    thread_id: str,
    body: SaveTurnBody,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    thread = _own_thread(db, user, thread_id)
    if not body.messages:
        return {"ok": True}

    # created_at ordering is what reconstructs the conversation, so each row
    # in the turn gets a strictly later timestamp than the one before it.
    base = utcnow()
    for i, m in enumerate(body.messages):
        if m.role not in ("user", "assistant", "tool"):
            raise HTTPException(status_code=400, detail="Unknown message role")
        db.add(
            AiMessage(
                thread_id=thread_id,
                user_id=user.id,
                role=m.role,
                content=m.content,
                tool_calls=m.tool_calls,
                tool_call_id=m.tool_call_id,
                name=m.name,
                actions=m.actions if m.actions else None,
                created_at=base + timedelta(microseconds=i),
            )
        )
    thread.updated_at = utcnow()  # the touch trigger's job
    db.commit()
    return {"ok": True}


@router.delete("/threads/{thread_id}")
def delete_thread(
    thread_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    thread = _own_thread(db, user, thread_id)
    db.delete(thread)  # messages cascade
    db.commit()
    return {"ok": True}


# ---------------------------------------------------------------- legacy chats


class ChatCreate(BaseModel):
    question: str
    answer: str


@router.get("/chats")
def list_chats(
    limit: int = 50, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    rows = (
        db.execute(
            select(AiChat)
            .where(AiChat.user_id == user.id)
            .order_by(AiChat.created_at.desc())
            .limit(limit)
        )
        .scalars()
        .all()
    )
    return [ai_chat_row(c) for c in rows]


@router.post("/chats")
def create_chat(
    body: ChatCreate, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    row = AiChat(user_id=user.id, question=body.question, answer=body.answer)
    db.add(row)
    db.commit()
    return ai_chat_row(row)


@router.delete("/chats/{chat_id}")
def delete_chat(chat_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    row = db.get(AiChat, chat_id)
    if row is None or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="Not found")
    db.delete(row)
    db.commit()
    return {"ok": True}


@router.delete("/chats")
def clear_chats(user: User = Depends(current_user), db: Session = Depends(get_db)):
    for row in (
        db.execute(select(AiChat).where(AiChat.user_id == user.id)).scalars().all()
    ):
        db.delete(row)
    db.commit()
    return {"ok": True}
