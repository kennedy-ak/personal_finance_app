"""Row → JSON dicts in exactly the shape Supabase/PostgREST used to return.

Both clients parse snake_case keys, numerics as numbers, dates as YYYY-MM-DD
and timestamps as ISO-8601 strings; keeping that contract is what lets their
domain models (Account.fromJson, Txn.fromRow, …) stay untouched.
"""

from datetime import date, datetime, timezone
from decimal import Decimal


def _num(v) -> float:
    if isinstance(v, Decimal):
        return float(v)
    return float(v or 0)


def _ts(v: datetime | None) -> str | None:
    if v is None:
        return None
    if v.tzinfo is None:
        v = v.replace(tzinfo=timezone.utc)
    return v.isoformat()


def _d(v: date | None) -> str | None:
    return None if v is None else v.isoformat()


def user_row(u) -> dict:
    return {
        "id": u.id,
        "email": u.email,
        "full_name": u.full_name,
        "created_at": _ts(u.created_at),
    }


def account_row(a) -> dict:
    return {
        "id": a.id,
        "user_id": a.user_id,
        "name": a.name,
        "balance": _num(a.balance),
        "kind": a.kind,
        "liquidity": a.liquidity,
        "min_balance": _num(a.min_balance),
        "purpose": a.purpose,
        "opening_balance": _num(a.opening_balance),
        "is_archived": bool(a.is_archived),
        "sort_order": a.sort_order,
        "created_at": _ts(a.created_at),
    }


def transaction_row(t) -> dict:
    return {
        "id": t.id,
        "user_id": t.user_id,
        "account_id": t.account_id,
        "to_account_id": t.to_account_id,
        "type": t.type,
        "amount": _num(t.amount),
        "category": t.category,
        "description": t.description,
        "date": _d(t.date),
        "source": t.source,
        "external_ref": t.external_ref,
        "created_at": _ts(t.created_at),
    }


def obligation_row(o) -> dict:
    return {
        "id": o.id,
        "user_id": o.user_id,
        "name": o.name,
        "direction": o.direction,
        "amount": _num(o.amount),
        "cadence": o.cadence,
        "next_due": _d(o.next_due),
        "account_id": o.account_id,
        "category": o.category,
        "is_active": bool(o.is_active),
        "created_at": _ts(o.created_at),
    }


def goal_row(g) -> dict:
    return {
        "id": g.id,
        "user_id": g.user_id,
        "name": g.name,
        "target_amount": _num(g.target_amount),
        "saved_amount": _num(g.saved_amount),
        "target_date": _d(g.target_date),
        "account_id": g.account_id,
        "priority": g.priority,
        "is_active": bool(g.is_active),
        "created_at": _ts(g.created_at),
    }


def category_row(c) -> dict:
    return {
        "id": c.id,
        "user_id": c.user_id,
        "name": c.name,
        "kind": c.kind,
        "icon": c.icon,
        "is_hidden": bool(c.is_hidden),
        "is_builtin": bool(c.is_builtin),
        "sort_order": c.sort_order,
        "created_at": _ts(c.created_at),
    }


def ai_thread_row(t) -> dict:
    return {
        "id": t.id,
        "user_id": t.user_id,
        "title": t.title,
        "created_at": _ts(t.created_at),
        "updated_at": _ts(t.updated_at),
    }


def ai_message_row(m) -> dict:
    return {
        "id": m.id,
        "thread_id": m.thread_id,
        "user_id": m.user_id,
        "role": m.role,
        "content": m.content,
        "tool_calls": m.tool_calls,
        "tool_call_id": m.tool_call_id,
        "name": m.name,
        "actions": m.actions,
        "created_at": _ts(m.created_at),
    }


def ai_chat_row(c) -> dict:
    return {
        "id": c.id,
        "user_id": c.user_id,
        "question": c.question,
        "answer": c.answer,
        "created_at": _ts(c.created_at),
    }


def sms_link_row(l) -> dict:
    return {
        "id": l.id,
        "user_id": l.user_id,
        "parser_id": l.parser_id,
        "account_id": l.account_id,
        "identifiers": l.identifiers or [],
        "created_at": _ts(l.created_at),
    }


def sms_rule_row(r) -> dict:
    return {
        "id": r.id,
        "user_id": r.user_id,
        "parser_id": r.parser_id,
        "match_text": r.match_text,
        "match_kind": r.match_kind,
        "txn_type": r.txn_type,
        "category": r.category,
        "counterpart_account_id": r.counterpart_account_id,
        "priority": r.priority,
        "created_at": _ts(r.created_at),
    }


def sms_inbox_row(i) -> dict:
    return {
        "id": i.id,
        "user_id": i.user_id,
        "sender": i.sender,
        "body": i.body,
        "received_at": _ts(i.received_at),
        "status": i.status,
        "parsed": i.parsed,
        "transaction_id": i.transaction_id,
        "dedupe_key": i.dedupe_key,
        "created_at": _ts(i.created_at),
    }
