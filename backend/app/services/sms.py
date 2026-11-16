"""Atomic SMS import — the port of the RPCs from migrations 0006 and 0008.

Each public function runs inside the caller's session and the router commits
once at the end, so the all-or-nothing guarantee the SQL functions gave is
kept: a fee is never charged without its message being marked, and a message
is never marked imported without its transaction landing.
"""

from datetime import date as date_type
from datetime import datetime

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models import SmsInbox, Transaction
from .balances import recompute_for_txn


def _parse_date(s: str) -> date_type:
    return date_type.fromisoformat(s[:10])


def _parse_ts(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def insert_planned_txn(db: Session, user_id: str, txn: dict) -> str:
    """Insert one planned transaction, tolerating a re-import.

    Returns the row's id whether this call created it or an earlier sweep did
    — same contract as sms_insert_planned_txn().
    """
    ref = (txn.get("external_ref") or "").strip()
    if not ref:
        raise HTTPException(status_code=400, detail="external_ref is required")

    existing = db.execute(
        select(Transaction).where(
            Transaction.user_id == user_id, Transaction.external_ref == ref
        )
    ).scalar_one_or_none()
    if existing is not None:
        return existing.id

    to_account = txn.get("to_account_id") or None
    row = Transaction(
        user_id=user_id,
        account_id=txn["account_id"],
        to_account_id=to_account,
        type=txn["type"],
        amount=txn["amount"],
        category=txn["category"],
        description=(txn.get("description") or None),
        date=_parse_date(txn["date"]),
        source="sms",
        external_ref=ref,
    )
    db.add(row)
    db.flush()
    recompute_for_txn(db, row.account_id, row.to_account_id)
    return row.id


def import_txn(
    db: Session,
    user_id: str,
    *,
    sender: str,
    body: str,
    received_at: str,
    dedupe_key: str,
    parsed: dict | None,
    txn: dict,
    fee: dict | None,
) -> str:
    txn_id = insert_planned_txn(db, user_id, txn)
    if fee:
        insert_planned_txn(db, user_id, fee)

    inbox = _inbox_by_key(db, user_id, dedupe_key)
    if inbox is not None:
        inbox.status = "imported"
        inbox.transaction_id = txn_id
        inbox.parsed = parsed
    else:
        db.add(
            SmsInbox(
                user_id=user_id,
                sender=sender,
                body=body,
                received_at=_parse_ts(received_at),
                status="imported",
                parsed=parsed,
                transaction_id=txn_id,
                dedupe_key=dedupe_key,
            )
        )
    return txn_id


def hold_for_review(
    db: Session,
    user_id: str,
    *,
    sender: str,
    body: str,
    received_at: str,
    dedupe_key: str,
    parsed: dict | None,
    fee: dict | None,
) -> None:
    if fee:
        insert_planned_txn(db, user_id, fee)
    if _inbox_by_key(db, user_id, dedupe_key) is not None:
        return  # on conflict do nothing

    # A message nothing could be parsed from is 'unparsed': both clients show
    # it as unreadable and only offer to dismiss it.
    unreadable = not parsed or parsed.get("verdict") == "unparsed"
    db.add(
        SmsInbox(
            user_id=user_id,
            sender=sender,
            body=body,
            received_at=_parse_ts(received_at),
            status="unparsed" if unreadable else "pending",
            parsed=parsed,
            dedupe_key=dedupe_key,
        )
    )


def ignore_message(
    db: Session,
    user_id: str,
    *,
    sender: str,
    body: str,
    received_at: str,
    dedupe_key: str,
) -> None:
    if _inbox_by_key(db, user_id, dedupe_key) is not None:
        return
    db.add(
        SmsInbox(
            user_id=user_id,
            sender=sender,
            body=body,
            received_at=_parse_ts(received_at),
            status="ignored",
            dedupe_key=dedupe_key,
        )
    )


def resolve_review(db: Session, user_id: str, inbox_id: str, txn: dict) -> str:
    inbox = db.get(SmsInbox, inbox_id)
    if inbox is None or inbox.user_id != user_id:
        raise HTTPException(status_code=404, detail="No such message")

    txn_id = insert_planned_txn(db, user_id, txn)
    inbox.status = "imported"
    inbox.transaction_id = txn_id
    return txn_id


def _inbox_by_key(db: Session, user_id: str, dedupe_key: str | None) -> SmsInbox | None:
    if not dedupe_key:
        return None
    return db.execute(
        select(SmsInbox).where(
            SmsInbox.user_id == user_id, SmsInbox.dedupe_key == dedupe_key
        )
    ).scalar_one_or_none()
