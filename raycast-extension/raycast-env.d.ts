/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {
  /** Sessions File - Path to Perch sessions.json. Leave empty to use ~/.config/perch/sessions.json. */
  "sessionsPath"?: string,
  /** Perch CLI Path - Optional path to the perch binary for add, done, and reopen actions. */
  "perchBinaryPath"?: string,
  /** Default Status Filter - Which sessions to show by default. */
  "defaultStatusFilter": "pending" | "all" | "done",
  /** Default Resume Action - What pressing Enter on a session does. */
  "resumeBehavior": "copy" | "paste"
}

/** Preferences accessible in all the extension's commands */
declare type Preferences = ExtensionPreferences

declare namespace Preferences {
  /** Preferences accessible in the `search-sessions` command */
  export type SearchSessions = ExtensionPreferences & {}
  /** Preferences accessible in the `add-session` command */
  export type AddSession = ExtensionPreferences & {}
}

declare namespace Arguments {
  /** Arguments passed to the `search-sessions` command */
  export type SearchSessions = {}
  /** Arguments passed to the `add-session` command */
  export type AddSession = {}
}

