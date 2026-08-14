import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.db import Base, engine

@pytest.fixture(autouse=True)
def _reset_db():
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    yield

def _client() -> TestClient:
    return TestClient(app)

def test_health():
    assert _client().get("/health").json() == {"status": "ok"}

def test_create_user_and_sync_roundtrip():
    c = _client()
    user = c.post("/users", json={"email": "a@b.co"}).json()
    api_key = user["api_key"]
    headers = {"X-API-Key": api_key}
    tx = {"amount": 12.5, "currency": "USD", "merchant": "Starbucks",
          "category": "Coffee & Dining", "source": "shortcut",
          "raw_text": "Starbucks $12.50", "timestamp": "2026-08-13T10:00:00",
          "dedup_hash": "abc12345"}
    r = c.post("/sync/transactions", headers=headers,
               json={"transactions": [tx]})
    assert r.status_code == 200
    assert r.json() == {"inserted": 1, "duplicates": 0}
    r2 = c.post("/sync/transactions", headers=headers,
                json={"transactions": [tx]})
    assert r2.json() == {"inserted": 0, "duplicates": 1}
    pulled = c.get("/sync/transactions?since=2026-01-01T00:00:00",
                   headers=headers).json()
    assert len(pulled["transactions"]) == 1

def test_sync_requires_api_key():
    r = _client().post("/sync/transactions", json={"transactions": []})
    assert r.status_code == 401