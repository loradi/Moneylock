from fastapi import FastAPI
from .routers import users, sync, sync_profile
from .db import Base, engine

Base.metadata.create_all(engine)

app = FastAPI(title="Moneylock Sync")
app.include_router(users.router, prefix="/users", tags=["users"])
app.include_router(sync.router, prefix="/sync/transactions", tags=["sync"])
app.include_router(sync_profile.router, prefix="/sync/profile", tags=["sync"])


@app.get("/health")
def health():
    return {"status": "ok"}
