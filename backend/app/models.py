"""The schema, ported table-for-table from supabase/migrate_fresh_project.sql.

What Postgres did with triggers and RLS the backend does in code:
  - ownership: every query filters on the signed-in user's id (see routers)
  - balance maintenance: services/balances.py, called after every write that
    touches transactions or opening_balance
  - signup defaults: services/defaults.py
IDs are UUID4 strings so existing client code, which treats ids as opaque
strings, keeps working against either database.
"""

import uuid
from datetime import date, datetime, timezone

from sqlalchemy import (
    JSON,
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


def new_id() -> str:
    return str(uuid.uuid4())


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    full_name: Mapped[str | None] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Account(Base):
    __tablename__ = "accounts"
    __table_args__ = (UniqueConstraint("user_id", "name", name="accounts_user_name_key"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(Text, nullable=False)
    balance: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    kind: Mapped[str] = mapped_column(String(20), nullable=False, default="bank")
    liquidity: Mapped[str] = mapped_column(String(20), nullable=False, default="liquid")
    min_balance: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    purpose: Mapped[str | None] = mapped_column(Text)
    opening_balance: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    is_archived: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Transaction(Base):
    __tablename__ = "transactions"
    __table_args__ = (
        Index("transactions_user_date_idx", "user_id", "date"),
        Index(
            "transactions_external_ref_key",
            "user_id",
            "external_ref",
            unique=True,
            sqlite_where=text("external_ref IS NOT NULL"),
            postgresql_where=text("external_ref IS NOT NULL"),
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    account_id: Mapped[str] = mapped_column(
        ForeignKey("accounts.id", ondelete="CASCADE"), nullable=False, index=True
    )
    to_account_id: Mapped[str | None] = mapped_column(
        ForeignKey("accounts.id", ondelete="CASCADE"), index=True
    )
    type: Mapped[str] = mapped_column(String(10), nullable=False)  # Income|Expense|Transfer
    amount: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    category: Mapped[str] = mapped_column(Text, nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    date: Mapped[date] = mapped_column(Date, nullable=False)
    source: Mapped[str] = mapped_column(String(10), nullable=False, default="manual")
    external_ref: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Obligation(Base):
    __tablename__ = "obligations"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(Text, nullable=False)
    direction: Mapped[str] = mapped_column(String(5), nullable=False, default="out")
    amount: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    cadence: Mapped[str] = mapped_column(String(12), nullable=False, default="monthly")
    next_due: Mapped[date] = mapped_column(Date, nullable=False)
    account_id: Mapped[str | None] = mapped_column(ForeignKey("accounts.id", ondelete="SET NULL"))
    category: Mapped[str | None] = mapped_column(Text)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Goal(Base):
    __tablename__ = "goals"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(Text, nullable=False)
    target_amount: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    saved_amount: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    target_date: Mapped[date | None] = mapped_column(Date)
    account_id: Mapped[str | None] = mapped_column(ForeignKey("accounts.id", ondelete="SET NULL"))
    priority: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Category(Base):
    __tablename__ = "categories"
    __table_args__ = (
        UniqueConstraint("user_id", "kind", "name", name="categories_user_kind_name_key"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(Text, nullable=False)
    kind: Mapped[str] = mapped_column(String(10), nullable=False)  # expense|income
    icon: Mapped[str | None] = mapped_column(Text)
    is_hidden: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    is_builtin: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class AiThread(Base):
    __tablename__ = "ai_threads"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    title: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class AiMessage(Base):
    __tablename__ = "ai_messages"
    __table_args__ = (Index("ai_messages_thread_idx", "thread_id", "created_at"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    thread_id: Mapped[str] = mapped_column(
        ForeignKey("ai_threads.id", ondelete="CASCADE"), nullable=False
    )
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    role: Mapped[str] = mapped_column(String(10), nullable=False)  # user|assistant|tool
    content: Mapped[str | None] = mapped_column(Text)
    tool_calls: Mapped[list | None] = mapped_column(JSON)
    tool_call_id: Mapped[str | None] = mapped_column(Text)
    name: Mapped[str | None] = mapped_column(Text)
    actions: Mapped[list | None] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class AiChat(Base):
    """Legacy single-shot Q&A rows (`ai_chats`), kept for the history screen."""

    __tablename__ = "ai_chats"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    question: Mapped[str] = mapped_column(Text, nullable=False)
    answer: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class SmsAccountLink(Base):
    __tablename__ = "sms_account_links"
    __table_args__ = (
        UniqueConstraint("user_id", "parser_id", name="sms_account_links_user_parser_key"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    parser_id: Mapped[str] = mapped_column(String(32), nullable=False)
    account_id: Mapped[str] = mapped_column(
        ForeignKey("accounts.id", ondelete="CASCADE"), nullable=False
    )
    identifiers: Mapped[list] = mapped_column(JSON, nullable=False, default=list)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class SmsRoutingRule(Base):
    __tablename__ = "sms_routing_rules"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    parser_id: Mapped[str | None] = mapped_column(String(32))
    match_text: Mapped[str] = mapped_column(Text, nullable=False)
    match_kind: Mapped[str] = mapped_column(String(10), nullable=False, default="contains")
    txn_type: Mapped[str] = mapped_column(String(10), nullable=False)
    category: Mapped[str | None] = mapped_column(Text)
    counterpart_account_id: Mapped[str | None] = mapped_column(
        ForeignKey("accounts.id", ondelete="CASCADE")
    )
    priority: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class SmsInbox(Base):
    __tablename__ = "sms_inbox"
    __table_args__ = (
        Index(
            "sms_inbox_dedupe_key",
            "user_id",
            "dedupe_key",
            unique=True,
            sqlite_where=text("dedupe_key IS NOT NULL"),
            postgresql_where=text("dedupe_key IS NOT NULL"),
        ),
        Index("sms_inbox_user_status_idx", "user_id", "status", "received_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    sender: Mapped[str] = mapped_column(Text, nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    received_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    status: Mapped[str] = mapped_column(String(10), nullable=False, default="pending")
    parsed: Mapped[dict | None] = mapped_column(JSON)
    transaction_id: Mapped[str | None] = mapped_column(
        ForeignKey("transactions.id", ondelete="SET NULL")
    )
    dedupe_key: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
