import secrets


def new_api_key() -> str:
    return secrets.token_hex(32)