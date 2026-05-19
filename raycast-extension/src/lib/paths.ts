import { getPreferenceValues } from "@raycast/api";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { access } from "node:fs/promises";
import { constants } from "node:fs";
import type { Preferences } from "./types";

export function expandHome(path: string): string {
  if (path === "~") return homedir();
  if (path.startsWith("~/")) return join(homedir(), path.slice(2));
  return path;
}

export function defaultSessionsPath(): string {
  return join(homedir(), ".config", "perch", "sessions.json");
}

export function getSessionsPath(): string {
  const preferences = getPreferenceValues<Preferences>();
  const configured = preferences.sessionsPath?.trim();
  return configured ? resolve(expandHome(configured)) : defaultSessionsPath();
}

export function displayPath(path: string): string {
  const home = homedir();
  if (path === home) return "~";
  if (path.startsWith(`${home}/`)) return `~/${path.slice(home.length + 1)}`;
  return path;
}

export function projectName(path: string): string {
  const normalized = path.replace(/\/+$/, "");
  const base = normalized.split("/").pop();
  return base || path;
}

export async function pathExists(path: string): Promise<boolean> {
  try {
    await access(path, constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

export function containingDirectory(path: string): string {
  return isAbsolute(path) ? dirname(path) : dirname(resolve(path));
}
