export const AGENTS = [
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
] as const;

export type PerchAgent = (typeof AGENTS)[number];
export type PerchStatus = "pending" | "in-progress" | "done";
export type PerchPriority = "low" | "medium" | "high";

export interface PerchSession {
  id: string;
  agent: PerchAgent;
  session_id: string;
  working_dir: string;
  title: string;
  note?: string;
  priority?: PerchPriority;
  status: PerchStatus;
  created_at: string;
  updated_at?: string;
  resume_cmd: string;
}

export interface Preferences {
  sessionsPath?: string;
  perchBinaryPath?: string;
  defaultStatusFilter?: "pending" | "done" | "all";
  resumeBehavior?: "copy" | "paste";
}

export type StatusFilter = "pending" | "done" | "all";
