import { readFile } from "node:fs/promises";
import { getSessionsPath } from "./paths";
import { timestamp } from "./dates";
import { AGENTS, type PerchAgent, type PerchSession, type PerchStatus, type StatusFilter } from "./types";

export class SessionsFileMissingError extends Error {
  constructor(public readonly path: string) {
    super(`Perch sessions file not found at ${path}`);
    this.name = "SessionsFileMissingError";
  }
}

export class SessionsParseError extends Error {
  constructor(
    public readonly path: string,
    public readonly causeMessage: string,
  ) {
    super(`Could not parse ${path}: ${causeMessage}`);
    this.name = "SessionsParseError";
  }
}

export async function readSessions(path = getSessionsPath()): Promise<PerchSession[]> {
  let text: string;
  try {
    text = await readFile(path, "utf8");
  } catch (error) {
    if (isNodeError(error) && error.code === "ENOENT") {
      throw new SessionsFileMissingError(path);
    }
    throw error;
  }

  let raw: unknown;
  try {
    raw = JSON.parse(text || "[]");
  } catch (error) {
    throw new SessionsParseError(path, error instanceof Error ? error.message : String(error));
  }

  if (!Array.isArray(raw)) {
    throw new SessionsParseError(path, "expected a JSON array");
  }

  return raw.map(normalizeSession).sort((a, b) => timestamp(b) - timestamp(a));
}

export function filterSessions(
  sessions: PerchSession[],
  statusFilter: StatusFilter,
  agentFilter: string,
): PerchSession[] {
  return sessions.filter((session) => {
    const statusMatches = statusFilter === "all" || session.status === statusFilter;
    const agentMatches = agentFilter === "all" || session.agent === agentFilter;
    return statusMatches && agentMatches;
  });
}

export function normalizeSession(value: unknown): PerchSession {
  if (!value || typeof value !== "object") {
    throw new Error("invalid session entry");
  }
  const candidate = value as Record<string, unknown>;
  const agent = asAgent(candidate.agent);
  const status = asStatus(candidate.status);
  const workingDir = asString(candidate.working_dir, "working_dir");
  const sessionId = asString(candidate.session_id, "session_id");
  return {
    id: asString(candidate.id, "id"),
    agent,
    session_id: sessionId,
    working_dir: workingDir,
    title: asString(candidate.title, "title"),
    note: typeof candidate.note === "string" ? candidate.note : "",
    priority:
      candidate.priority === "low" || candidate.priority === "medium" || candidate.priority === "high"
        ? candidate.priority
        : "medium",
    status,
    created_at: asString(candidate.created_at, "created_at"),
    updated_at: typeof candidate.updated_at === "string" ? candidate.updated_at : undefined,
    resume_cmd: typeof candidate.resume_cmd === "string" ? candidate.resume_cmd : "",
  };
}

function asString(value: unknown, field: string): string {
  if (typeof value !== "string") throw new Error(`invalid ${field}`);
  return value;
}

function asAgent(value: unknown): PerchAgent {
  if (typeof value === "string" && (AGENTS as readonly string[]).includes(value)) return value as PerchAgent;
  return "claude";
}

function asStatus(value: unknown): PerchStatus {
  if (value === "pending" || value === "in-progress" || value === "done") return value;
  return "pending";
}

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && "code" in error;
}
