"""What a fresh user starts with — the port of handle_new_user() and
seed_default_categories() from the Supabase schema."""

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models import Account, Category

DEFAULT_ACCOUNTS = [
    # (name, kind, liquidity, sort_order)
    ("Fidelity Account", "bank", "liquid", 0),
    ("Access Account", "bank", "liquid", 1),
    ("Mobile Money", "momo", "liquid", 2),
    ("Cash", "cash", "liquid", 3),
]

DEFAULT_CATEGORIES = [
    # (name, kind, icon, sort_order)
    ("Food & Dining", "expense", "restaurant", 0),
    ("Transportation", "expense", "bus", 1),
    ("Shopping", "expense", "shopping", 2),
    ("Entertainment", "expense", "movie", 3),
    ("Bills & Utilities", "expense", "bolt", 4),
    ("Healthcare", "expense", "medical", 5),
    ("Education", "expense", "school", 6),
    ("Travel", "expense", "flight", 7),
    ("Housing", "expense", "home", 8),
    ("Insurance", "expense", "shield", 9),
    ("Gifts & Donations", "expense", "gift", 10),
    ("Bank Charges", "expense", "receipt", 11),
    ("Other", "expense", "category", 12),
    ("Salary", "income", "work", 0),
    ("Business", "income", "business", 1),
    ("Investment", "income", "trending_up", 2),
    ("Gift", "income", "gift", 3),
    ("Refund", "income", "replay", 4),
    ("Other", "income", "category", 5),
]


def create_default_accounts(db: Session, user_id: str) -> None:
    for name, kind, liquidity, sort_order in DEFAULT_ACCOUNTS:
        db.add(
            Account(
                user_id=user_id,
                name=name,
                balance=0,
                kind=kind,
                liquidity=liquidity,
                sort_order=sort_order,
            )
        )


def seed_default_categories(db: Session, user_id: str) -> None:
    """Idempotent, like the SQL original: existing rows are left alone."""
    existing = set(
        db.execute(
            select(Category.kind, Category.name).where(Category.user_id == user_id)
        ).all()
    )
    for name, kind, icon, sort_order in DEFAULT_CATEGORIES:
        if (kind, name) in existing:
            continue
        db.add(
            Category(
                user_id=user_id,
                name=name,
                kind=kind,
                icon=icon,
                is_builtin=True,
                sort_order=sort_order,
            )
        )
