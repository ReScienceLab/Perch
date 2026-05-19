import { Action, ActionPanel, Form, Icon, Toast, popToRoot, showToast } from "@raycast/api";
import { useState } from "react";
import { addSession, PerchCliMissingError } from "./lib/cli";
import { expandHome } from "./lib/paths";
import { AGENTS, type PerchAgent } from "./lib/types";

interface FormValues {
  title: string;
  agent: PerchAgent;
  sessionId: string;
  workingDir?: string;
  note?: string;
}

export default function AddSession() {
  const [titleError, setTitleError] = useState<string | undefined>();
  const [sessionIdError, setSessionIdError] = useState<string | undefined>();
  const [workingDirError, setWorkingDirError] = useState<string | undefined>();

  async function submit(values: FormValues) {
    const title = values.title.trim();
    const sessionId = values.sessionId.trim();
    const workingDir = values.workingDir?.trim() ? expandHome(values.workingDir.trim()) : undefined;

    let invalid = false;
    if (!title) {
      setTitleError("Title is required");
      invalid = true;
    } else if (title.length > 60) {
      setTitleError("Title must be 60 characters or fewer");
      invalid = true;
    }
    if (!sessionId) {
      setSessionIdError("Session ID is required");
      invalid = true;
    }
    if (workingDir && !workingDir.startsWith("/")) {
      setWorkingDirError("Working directory must be an absolute path");
      invalid = true;
    }
    if (invalid) return;

    const toast = await showToast({ style: Toast.Style.Animated, title: "Adding Session" });
    try {
      const message = await addSession({
        title,
        agent: values.agent,
        sessionId,
        workingDir,
        note: values.note?.trim(),
      });
      toast.style = Toast.Style.Success;
      toast.title = "Added Session";
      toast.message = message || title;
      await popToRoot({ clearSearchBar: true });
    } catch (error) {
      toast.style = Toast.Style.Failure;
      toast.title = error instanceof PerchCliMissingError ? "Perch CLI Not Found" : "Could Not Add Session";
      toast.message =
        error instanceof PerchCliMissingError
          ? "Install Perch with the one-line installer or set Perch CLI Path, then run perch doctor."
          : error instanceof Error
            ? error.message
            : String(error);
    }
  }

  return (
    <Form
      navigationTitle="Add Perch Session"
      actions={
        <ActionPanel>
          <Action.SubmitForm title="Add Session" icon={Icon.Plus} onSubmit={submit} />
        </ActionPanel>
      }
    >
      <Form.TextField
        id="title"
        title="Title"
        placeholder="Project: continue task"
        error={titleError}
        onChange={() => setTitleError(undefined)}
        onBlur={(event) => {
          const value = event.target.value?.trim() || "";
          if (!value) setTitleError("Title is required");
          else if (value.length > 60) setTitleError("Title must be 60 characters or fewer");
        }}
      />
      <Form.Dropdown id="agent" title="Agent" defaultValue="claude">
        {AGENTS.map((agent) => (
          <Form.Dropdown.Item key={agent} value={agent} title={agent} />
        ))}
      </Form.Dropdown>
      <Form.TextField
        id="sessionId"
        title="Session ID"
        placeholder="Agent-native session ID"
        error={sessionIdError}
        onChange={() => setSessionIdError(undefined)}
        onBlur={(event) => {
          if (!event.target.value?.trim()) setSessionIdError("Session ID is required");
        }}
      />
      <Form.TextField
        id="workingDir"
        title="Working Directory"
        placeholder="/absolute/path/to/project (optional)"
        error={workingDirError}
        onChange={() => setWorkingDirError(undefined)}
        onBlur={(event) => {
          const value = event.target.value?.trim();
          if (value && !expandHome(value).startsWith("/"))
            setWorkingDirError("Working directory must be an absolute path");
        }}
      />
      <Form.TextArea id="note" title="Note" placeholder="Optional note" />
    </Form>
  );
}
