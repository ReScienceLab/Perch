import {
  Action,
  ActionPanel,
  Clipboard,
  Color,
  Icon,
  List,
  Toast,
  getPreferenceValues,
  openExtensionPreferences,
  showToast,
} from "@raycast/api";
import { useCallback, useEffect, useMemo, useState, type ReactElement } from "react";
import { markDone, PerchCliMissingError, reopen } from "./lib/cli";
import { timeAgo } from "./lib/dates";
import { displayPath, getSessionsPath, projectName } from "./lib/paths";
import { filterSessions, readSessions, SessionsFileMissingError, SessionsParseError } from "./lib/store";
import { fullResumeCommand } from "./lib/shell";
import { AGENTS, type PerchSession, type Preferences, type StatusFilter } from "./lib/types";

type LoadState =
  | { kind: "loading"; sessions: PerchSession[] }
  | { kind: "ready"; sessions: PerchSession[] }
  | { kind: "missing"; path: string; sessions: PerchSession[] }
  | { kind: "parse-error"; path: string; message: string; sessions: PerchSession[] }
  | { kind: "error"; message: string; sessions: PerchSession[] };

export default function SearchSessions() {
  const preferences = getPreferenceValues<Preferences>();
  const [statusFilter, setStatusFilter] = useState<StatusFilter>(preferences.defaultStatusFilter || "pending");
  const [agentFilter, setAgentFilter] = useState("all");
  const [state, setState] = useState<LoadState>({ kind: "loading", sessions: [] });

  const load = useCallback(async () => {
    setState((previous) => ({ kind: "loading", sessions: previous.sessions }));
    try {
      const sessions = await readSessions();
      setState({ kind: "ready", sessions });
    } catch (error) {
      if (error instanceof SessionsFileMissingError) {
        setState({ kind: "missing", path: error.path, sessions: [] });
      } else if (error instanceof SessionsParseError) {
        setState({ kind: "parse-error", path: error.path, message: error.causeMessage, sessions: [] });
      } else {
        setState({ kind: "error", message: error instanceof Error ? error.message : String(error), sessions: [] });
      }
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const sessions = useMemo(
    () => filterSessions(state.sessions, statusFilter, agentFilter),
    [state.sessions, statusFilter, agentFilter],
  );

  const emptyView = getEmptyView(state, statusFilter);

  return (
    <List
      isLoading={state.kind === "loading"}
      searchBarPlaceholder="Search title, project, agent, or session ID"
      searchBarAccessory={
        <List.Dropdown
          tooltip="Filter Sessions"
          value={`${statusFilter}:${agentFilter}`}
          onChange={(value) => {
            const [status, agent] = value.split(":");
            setStatusFilter(status as StatusFilter);
            setAgentFilter(agent);
          }}
        >
          <List.Dropdown.Section title="Status">
            <List.Dropdown.Item title="Pending" value="pending:all" />
            <List.Dropdown.Item title="Done" value="done:all" />
            <List.Dropdown.Item title="All" value="all:all" />
          </List.Dropdown.Section>
          <List.Dropdown.Section title="Agent">
            <List.Dropdown.Item title="All Agents" value={`${statusFilter}:all`} />
            {AGENTS.map((agent) => (
              <List.Dropdown.Item key={agent} title={agent} value={`${statusFilter}:${agent}`} />
            ))}
          </List.Dropdown.Section>
        </List.Dropdown>
      }
    >
      {sessions.length === 0 ? emptyView : null}
      {sessions.map((session) => (
        <SessionItem key={session.id} session={session} onMutated={load} />
      ))}
    </List>
  );
}

function SessionItem({ session, onMutated }: { session: PerchSession; onMutated: () => Promise<void> }) {
  const preferences = getPreferenceValues<Preferences>();
  const command = fullResumeCommand(session);
  const updated = session.updated_at || session.created_at;
  const primaryTitle = preferences.resumeBehavior === "paste" ? "Paste Resume Command" : "Copy Resume Command";

  async function runPrimaryAction() {
    if (preferences.resumeBehavior === "paste") {
      await Clipboard.paste(command);
      await showToast({ style: Toast.Style.Success, title: "Pasted Resume Command" });
    } else {
      await Clipboard.copy(command);
      await showToast({ style: Toast.Style.Success, title: "Copied Resume Command" });
    }
  }

  async function setDone() {
    await mutateSession(() => markDone(session.id.slice(0, 8)), onMutated, "Marked Done");
  }

  async function setReopen() {
    await mutateSession(() => reopen(session.id.slice(0, 8)), onMutated, "Reopened Session");
  }

  return (
    <List.Item
      icon={agentIcon(session.agent)}
      title={session.title}
      subtitle={`${session.agent} • ${displayPath(session.working_dir)}`}
      keywords={[
        session.agent,
        session.session_id,
        session.id,
        session.working_dir,
        projectName(session.working_dir),
        session.note || "",
      ]}
      accessories={[
        { text: session.status, icon: statusIcon(session.status) },
        { text: timeAgo(updated), tooltip: updated },
      ]}
      detail={<List.Item.Detail markdown={detailMarkdown(session, command)} />}
      actions={
        <ActionPanel>
          <Action title={primaryTitle} icon={Icon.Terminal} onAction={runPrimaryAction} />
          <Action.CopyToClipboard
            title="Copy Resume Command"
            content={command}
            shortcut={{ modifiers: ["cmd"], key: "c" }}
          />
          <Action
            title="Paste Resume Command"
            icon={Icon.TextCursor}
            onAction={() => Clipboard.paste(command)}
            shortcut={{ modifiers: ["cmd"], key: "enter" }}
          />
          <ActionPanel.Section title="Manage">
            {session.status === "done" ? (
              <Action title="Reopen" icon={Icon.ArrowClockwise} onAction={setReopen} />
            ) : (
              <Action title="Mark Done" icon={Icon.CheckCircle} onAction={setDone} />
            )}
            <Action.Open title="Open Working Directory" target={session.working_dir} icon={Icon.Folder} />
          </ActionPanel.Section>
          <ActionPanel.Section title="Copy">
            <Action.CopyToClipboard title="Copy Session ID" content={session.session_id} />
            <Action.CopyToClipboard title="Copy Perch ID" content={session.id} />
            <Action.CopyToClipboard title="Copy Working Directory" content={session.working_dir} />
          </ActionPanel.Section>
          <ActionPanel.Section title="Support">
            <Action.Open title="Open Sessions File" target={getSessionsPath()} icon={Icon.Document} />
            <Action title="Open Extension Preferences" icon={Icon.Gear} onAction={openExtensionPreferences} />
          </ActionPanel.Section>
        </ActionPanel>
      }
    />
  );
}

async function mutateSession(operation: () => Promise<string>, onMutated: () => Promise<void>, successTitle: string) {
  const toast = await showToast({ style: Toast.Style.Animated, title: successTitle });
  try {
    const message = await operation();
    toast.style = Toast.Style.Success;
    toast.message = message;
    await onMutated();
  } catch (error) {
    toast.style = Toast.Style.Failure;
    toast.title = error instanceof PerchCliMissingError ? "Perch CLI Not Found" : "Perch Command Failed";
    toast.message = error instanceof Error ? error.message : String(error);
  }
}

function getEmptyView(state: LoadState, statusFilter: StatusFilter): ReactElement {
  if (state.kind === "missing") {
    return (
      <List.EmptyView
        icon={Icon.ExclamationMark}
        title="Perch Sessions File Not Found"
        description={`Expected ${state.path}. Run ./install.sh or save a session with /perch first.`}
        actions={
          <ActionPanel>
            <Action title="Open Extension Preferences" icon={Icon.Gear} onAction={openExtensionPreferences} />
          </ActionPanel>
        }
      />
    );
  }
  if (state.kind === "parse-error") {
    return (
      <List.EmptyView
        icon={Icon.Warning}
        title="Could Not Parse sessions.json"
        description={`${state.path}: ${state.message}`}
        actions={
          <ActionPanel>
            <Action.Open title="Open Sessions File" target={state.path} icon={Icon.Document} />
          </ActionPanel>
        }
      />
    );
  }
  if (state.kind === "error") {
    return <List.EmptyView icon={Icon.Warning} title="Could Not Load Sessions" description={state.message} />;
  }
  return (
    <List.EmptyView
      icon={Icon.Tray}
      title={statusFilter === "pending" ? "No Pending Sessions" : "No Sessions Found"}
      description={
        statusFilter === "pending"
          ? "Switch the filter to All or save one with /perch."
          : "Try a different filter or search."
      }
    />
  );
}

function detailMarkdown(session: PerchSession, command: string): string {
  const rows = [
    ["Title", session.title],
    ["Agent", session.agent],
    ["Status", session.status],
    ["Project", session.working_dir],
    ["Session ID", session.session_id],
    ["Perch ID", session.id],
    ["Created", session.created_at],
    ["Updated", session.updated_at || "—"],
  ];
  return [
    `# ${escapeMarkdown(session.title)}`,
    session.note ? `\n${escapeMarkdown(session.note)}` : "",
    "\n```sh",
    command,
    "```\n",
    ...rows.map(([key, value]) => `- **${key}:** ${escapeMarkdown(value)}`),
  ].join("\n");
}

function statusIcon(status: string) {
  if (status === "done") return { source: Icon.CheckCircle, tintColor: Color.Green };
  if (status === "in-progress") return { source: Icon.Clock, tintColor: Color.Yellow };
  return { source: Icon.Circle, tintColor: Color.Blue };
}

function agentIcon(agent: string) {
  switch (agent) {
    case "claude":
      return { source: Icon.Message, tintColor: Color.Orange };
    case "codex":
      return { source: Icon.Code, tintColor: Color.Purple };
    case "pi":
      return { source: Icon.CommandSymbol, tintColor: Color.Red };
    default:
      return { source: Icon.Terminal, tintColor: Color.SecondaryText };
  }
}

function escapeMarkdown(value: string): string {
  return value.replace(/([\\`*_{}[\]()#+\-.!|>])/g, "\\$1");
}
