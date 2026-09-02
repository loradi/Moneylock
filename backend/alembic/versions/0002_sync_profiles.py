"""add private sync profiles

Revision ID: 90b943cd0e58
Revises: 50caa1656e27
Create Date: 2026-09-02
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "90b943cd0e58"
down_revision: Union[str, None] = "50caa1656e27"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "sync_profiles",
        sa.Column("user_id", sa.String(length=36), nullable=False),
        sa.Column("payload", sa.Text(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("user_id"),
    )


def downgrade() -> None:
    op.drop_table("sync_profiles")
