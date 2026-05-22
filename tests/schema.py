#!/usr/bin/env python3
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
schema = json.loads((root / "schema" / "session.json").read_text())

expected_required = {
    "id",
    "agent",
    "session_id",
    "working_dir",
    "title",
    "status",
    "created_at",
    "resume_cmd",
}
expected_agents = [
    "claude",
    "codex",
    "pi",
    "windsurf",
    "cursor",
    "trae",
    "droid",
    "goose",
    "opencode",
    "kiro",
    "amp",
    "hermes",
]

assert schema["title"] == "PerchSession"
assert set(schema["required"]) == expected_required
assert schema["additionalProperties"] is False
assert schema["properties"]["agent"]["enum"] == expected_agents
assert schema["properties"]["priority"]["enum"] == ["low", "medium", "high"]
assert schema["properties"]["status"]["enum"] == ["pending", "in-progress", "done"]
assert schema["properties"]["updated_at"]["format"] == "date-time"
assert "updated_at" not in schema["required"]

for field in expected_required:
    assert field in schema["properties"], f"required field lacks schema: {field}"

print("schema tests passed")
