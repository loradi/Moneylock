from datetime import datetime
from pydantic import BaseModel, Field


class UserCreate(BaseModel):
    email: str = Field(min_length=3, max_length=255)


class UserOut(BaseModel):
    id: str
    api_key: str


class SyncTransaction(BaseModel):
    amount: float = Field(gt=0)
    currency: str = Field(default="USD", pattern="^(USD|CAD)$")
    merchant: str = Field(default="", max_length=255)
    category: str = Field(default="Other", max_length=80)
    source: str = Field(pattern="^(shortcut|voice|manual)$")
    raw_text: str = Field(max_length=2000)
    timestamp: datetime
    dedup_hash: str = Field(min_length=8, max_length=64)


class SyncRequest(BaseModel):
    transactions: list[SyncTransaction]


class SyncResult(BaseModel):
    inserted: int
    duplicates: int