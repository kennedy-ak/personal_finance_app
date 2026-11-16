from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Account, SmsAccountLink, SmsInbox, SmsRoutingRule, User
from ..security import current_user
from ..serialize import sms_inbox_row, sms_link_row, sms_rule_row
from ..services import sms as sms_service

router = APIRouter(prefix="/sms", tags=["sms"])

TXN_TYPES = {"Income", "Expense", "Transfer"}


def _own_account(db: Session, user: User, account_id: str) -> None:
    account = db.get(Account, account_id)
    if account is None or account.user_id != user.id:
        raise HTTPException(status_code=404, detail="Account not found")


# ---------------------------------------------------------------- links


class LinkBody(BaseModel):
    parser_id: str
    account_id: str
    identifiers: list[str] = []


@router.get("/links")
def list_links(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = (
        db.execute(
            select(SmsAccountLink)
            .where(SmsAccountLink.user_id == user.id)
            .order_by(SmsAccountLink.created_at.asc())
        )
        .scalars()
        .all()
    )
    return [sms_link_row(l) for l in rows]


@router.put("/links")
def save_link(body: LinkBody, user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Upsert on (user, parser) — one sender speaks for one account."""
    _own_account(db, user, body.account_id)
    existing = db.execute(
        select(SmsAccountLink).where(
            SmsAccountLink.user_id == user.id, SmsAccountLink.parser_id == body.parser_id
        )
    ).scalar_one_or_none()
    if existing is not None:
        existing.account_id = body.account_id
        existing.identifiers = body.identifiers
        db.commit()
        return sms_link_row(existing)
    row = SmsAccountLink(
        user_id=user.id,
        parser_id=body.parser_id,
        account_id=body.account_id,
        identifiers=body.identifiers,
    )
    db.add(row)
    db.commit()
    return sms_link_row(row)


@router.delete("/links/{link_id}")
def delete_link(link_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    row = db.get(SmsAccountLink, link_id)
    if row is None or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="Not found")
    db.delete(row)
    db.commit()
    return {"ok": True}


# ---------------------------------------------------------------- rules


class RuleBody(BaseModel):
    match_text: str
    txn_type: str
    parser_id: str | None = None
    match_kind: str = "contains"
    category: str | None = None
    counterpart_account_id: str | None = None
    priority: int = 0


@router.get("/rules")
def list_rules(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = (
        db.execute(
            select(SmsRoutingRule)
            .where(SmsRoutingRule.user_id == user.id)
            .order_by(SmsRoutingRule.priority.desc())
        )
        .scalars()
        .all()
    )
    return [sms_rule_row(r) for r in rows]


@router.post("/rules")
def create_rule(body: RuleBody, user: User = Depends(current_user), db: Session = Depends(get_db)):
    if not body.match_text.strip():
        raise HTTPException(status_code=400, detail="match_text must not be empty")
    if body.txn_type not in TXN_TYPES:
        raise HTTPException(status_code=400, detail="Unknown txn_type")
    # The shape check from migration 0005: a transfer rule names the account at
    # the other end and no category; anything else names a category only.
    if body.txn_type == "Transfer":
        if not body.counterpart_account_id or body.category:
            raise HTTPException(
                status_code=400,
                detail="A transfer rule needs a counterpart account and no category.",
            )
        _own_account(db, user, body.counterpart_account_id)
    else:
        if body.counterpart_account_id or not body.category:
            raise HTTPException(
                status_code=400,
                detail="A non-transfer rule needs a category and no counterpart account.",
            )

    row = SmsRoutingRule(
        user_id=user.id,
        parser_id=body.parser_id,
        match_text=body.match_text,
        match_kind=body.match_kind,
        txn_type=body.txn_type,
        category=body.category,
        counterpart_account_id=body.counterpart_account_id,
        priority=body.priority,
    )
    db.add(row)
    db.commit()
    return sms_rule_row(row)


@router.delete("/rules/{rule_id}")
def delete_rule(rule_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    row = db.get(SmsRoutingRule, rule_id)
    if row is None or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="Not found")
    db.delete(row)
    db.commit()
    return {"ok": True}


# ---------------------------------------------------------------- inbox


@router.get("/inbox")
def review_queue(
    limit: int = 60,
    status: str = "review",
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    q = select(SmsInbox).where(SmsInbox.user_id == user.id)
    if status != "all":
        q = q.where(SmsInbox.status.in_(["pending", "unparsed"]))
    rows = (
        db.execute(q.order_by(SmsInbox.received_at.desc()).limit(limit)).scalars().all()
    )
    return [sms_inbox_row(i) for i in rows]


@router.get("/inbox/count")
def review_count(user: User = Depends(current_user), db: Session = Depends(get_db)):
    n = db.execute(
        select(func.count()).where(
            SmsInbox.user_id == user.id, SmsInbox.status.in_(["pending", "unparsed"])
        )
    ).scalar_one()
    return {"count": int(n)}


@router.get("/inbox/keys")
def dedupe_keys(user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Every dedupe key this user has ever dealt with — lets the app skip known
    messages before paying for a round trip, as before."""
    rows = db.execute(
        select(SmsInbox.dedupe_key).where(
            SmsInbox.user_id == user.id, SmsInbox.dedupe_key.is_not(None)
        )
    ).all()
    return [r[0] for r in rows if r[0]]


@router.post("/inbox/{inbox_id}/ignore")
def ignore_inbox_item(
    inbox_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    row = db.get(SmsInbox, inbox_id)
    if row is None or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="Not found")
    row.status = "ignored"
    db.commit()
    return {"ok": True}


# ------------------------------------------------- the atomic import RPCs


class ImportBody(BaseModel):
    sender: str
    body: str
    received_at: str
    dedupe_key: str
    parsed: dict | None = None
    txn: dict
    fee: dict | None = None


class HoldBody(BaseModel):
    sender: str
    body: str
    received_at: str
    dedupe_key: str
    parsed: dict | None = None
    fee: dict | None = None


class IgnoreBody(BaseModel):
    sender: str
    body: str
    received_at: str
    dedupe_key: str


class ResolveBody(BaseModel):
    txn: dict


@router.post("/import")
def import_txn(body: ImportBody, user: User = Depends(current_user), db: Session = Depends(get_db)):
    txn_id = sms_service.import_txn(
        db,
        user.id,
        sender=body.sender,
        body=body.body,
        received_at=body.received_at,
        dedupe_key=body.dedupe_key,
        parsed=body.parsed,
        txn=body.txn,
        fee=body.fee,
    )
    db.commit()
    return {"transaction_id": txn_id}


@router.post("/hold")
def hold_for_review(
    body: HoldBody, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    sms_service.hold_for_review(
        db,
        user.id,
        sender=body.sender,
        body=body.body,
        received_at=body.received_at,
        dedupe_key=body.dedupe_key,
        parsed=body.parsed,
        fee=body.fee,
    )
    db.commit()
    return {"ok": True}


@router.post("/ignore")
def ignore_message(
    body: IgnoreBody, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    sms_service.ignore_message(
        db,
        user.id,
        sender=body.sender,
        body=body.body,
        received_at=body.received_at,
        dedupe_key=body.dedupe_key,
    )
    db.commit()
    return {"ok": True}


@router.post("/inbox/{inbox_id}/resolve")
def resolve_review(
    inbox_id: str,
    body: ResolveBody,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    txn_id = sms_service.resolve_review(db, user.id, inbox_id, body.txn)
    db.commit()
    return {"transaction_id": txn_id}
