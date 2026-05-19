import { getPreferenceValues } from "@raycast/api";
import { access } from "node:fs/promises";
import { constants } from "node:fs";
import { delimiter, join } from "node:path";
import { homedir } from "node:os";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { expandHome } from "./paths";
import type { PerchAgent, Preferences } from "./types";

const execFileAsync = promisify(execFile);

export class PerchCliMissingError extends Error {
  constructor() {
    super("Perch CLI not found");
    this.name = "PerchCliMissingError";
  }
}

export async function resolvePerchBinary(): Promise<string | undefined> {
  const preferences = getPreferenceValues<Preferences>();
  const configured = preferences.perchBinaryPath?.trim();
  if (configured && (await canExecute(expandHome(configured)))) return expandHome(configured);

  const fromPath = await findOnPath("perch");
  if (fromPath) return fromPath;

  const localBin = join(homedir(), ".local", "bin", "perch");
  if (await canExecute(localBin)) return localBin;

  return undefined;
}

export async function runPerch(args: string[]): Promise<string> {
  const binary = await resolvePerchBinary();
  if (!binary) throw new PerchCliMissingError();
  const result = await execFileAsync(binary, args, { timeout: 15_000, maxBuffer: 1024 * 1024 });
  return result.stdout.trim();
}

export async function markDone(idPrefix: string): Promise<string> {
  return runPerch(["done", idPrefix]);
}

export async function reopen(idPrefix: string): Promise<string> {
  return runPerch(["reopen", idPrefix]);
}

export interface AddSessionInput {
  title: string;
  agent: PerchAgent;
  sessionId: string;
  workingDir?: string;
  note?: string;
}

export async function addSession(input: AddSessionInput): Promise<string> {
  const args = ["add", "--title", input.title, "--agent", input.agent, "--session-id", input.sessionId];
  if (input.workingDir?.trim()) args.push("--working-dir", input.workingDir.trim());
  if (input.note?.trim()) args.push("--note", input.note.trim());
  return runPerch(args);
}

async function findOnPath(binary: string): Promise<string | undefined> {
  for (const directory of (process.env.PATH || "").split(delimiter)) {
    if (!directory) continue;
    const candidate = join(directory, binary);
    if (await canExecute(candidate)) return candidate;
  }
  return undefined;
}

async function canExecute(path: string): Promise<boolean> {
  try {
    await access(path, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}
