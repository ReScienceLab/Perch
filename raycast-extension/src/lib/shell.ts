import type { PerchSession } from "./types";

export function shellQuote(value: string): string {
  return `'${value.replace(/'/g, `'\\''`)}'`;
}

export function fallbackResumeCommand(session: PerchSession): string {
  const sessionId = session.session_id;
  switch (session.agent) {
    case "codex":
      return `codex resume ${shellQuoteBareArgument(sessionId)}`;
    case "pi":
      return `pi --session ${shellQuoteBareArgument(sessionId)}`;
    case "windsurf":
      return `windsurf ${shellQuote(session.working_dir)}`;
    case "cursor":
      return `cursor ${shellQuote(session.working_dir)}`;
    case "trae":
      return `trae ${shellQuote(session.working_dir)}`;
    case "droid":
      return `droid --resume ${shellQuoteBareArgument(sessionId)}`;
    case "goose":
      return `goose session -r --name ${shellQuoteBareArgument(sessionId)}`;
    case "opencode":
      return `opencode session resume ${shellQuoteBareArgument(sessionId)}`;
    case "kiro":
      return `kiro-cli chat --resume-id ${shellQuoteBareArgument(sessionId)}`;
    case "amp":
      return `amp threads continue ${shellQuoteBareArgument(sessionId)}`;
    case "hermes":
      return `hermes --resume ${shellQuoteBareArgument(sessionId)}`;
    case "claude":
    default:
      return `claude --resume ${shellQuoteBareArgument(sessionId)}`;
  }
}

export function fullResumeCommand(session: PerchSession): string {
  const resumeCommand = session.resume_cmd?.trim() || fallbackResumeCommand(session);
  return `cd ${shellQuote(session.working_dir)} && ${resumeCommand}`;
}

function shellQuoteBareArgument(value: string): string {
  return /^[A-Za-z0-9._/@:+-]+$/.test(value) ? value : shellQuote(value);
}
