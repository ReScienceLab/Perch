use std::fs;
use std::path::PathBuf;
use std::process::{Command, Output};
use std::sync::atomic::{AtomicUsize, Ordering};

static TEST_COUNTER: AtomicUsize = AtomicUsize::new(0);

fn temp_home(name: &str) -> PathBuf {
    let id = TEST_COUNTER.fetch_add(1, Ordering::SeqCst);
    let dir = std::env::temp_dir().join(format!(
        "perch-cli-tests-{}-{name}-{id}",
        std::process::id()
    ));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    dir
}

fn perch(home: &PathBuf, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_perch"))
        .args(args)
        .env("HOME", home)
        .current_dir(home)
        .output()
        .unwrap()
}

fn stdout(output: &Output) -> String {
    String::from_utf8(output.stdout.clone()).unwrap()
}

fn stderr(output: &Output) -> String {
    String::from_utf8(output.stderr.clone()).unwrap()
}

#[test]
fn add_list_done_and_reopen_end_to_end() {
    let home = temp_home("end-to-end");

    let add = perch(
        &home,
        &[
            "add",
            "--title",
            "Test title",
            "--agent",
            "pi",
            "--session-id",
            "pi-session",
            "--working-dir",
            "/tmp/project",
            "--note",
            "useful note",
        ],
    );
    assert!(add.status.success(), "stderr: {}", stderr(&add));
    assert_eq!(stdout(&add), "Test title\n");

    let sessions_path = home.join(".config/perch/sessions.json");
    let stored: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(&sessions_path).unwrap()).unwrap();
    let id = stored[0]["id"].as_str().unwrap().to_string();
    assert_eq!(stored[0]["agent"], "pi");
    assert_eq!(stored[0]["session_id"], "pi-session");
    assert_eq!(stored[0]["working_dir"], "/tmp/project");
    assert_eq!(stored[0]["note"], "useful note");
    assert_eq!(stored[0]["resume_cmd"], "pi --session pi-session");

    let list = perch(&home, &["list"]);
    assert!(list.status.success(), "stderr: {}", stderr(&list));
    assert!(stdout(&list).contains("Test title"));

    let done = perch(&home, &["done", "--session-id", "pi-session"]);
    assert!(done.status.success(), "stderr: {}", stderr(&done));
    assert_eq!(stdout(&done), "Done: Test title\n");

    let pending_list = perch(&home, &["list"]);
    assert!(
        pending_list.status.success(),
        "stderr: {}",
        stderr(&pending_list)
    );
    assert_eq!(stdout(&pending_list), "No sessions.\n");

    let all_json = perch(&home, &["list", "--all", "--json"]);
    assert!(all_json.status.success(), "stderr: {}", stderr(&all_json));
    let all: serde_json::Value = serde_json::from_str(&stdout(&all_json)).unwrap();
    assert_eq!(all[0]["status"], "done");

    let update = perch(
        &home,
        &[
            "add",
            "--title",
            "Updated title",
            "--agent",
            "pi",
            "--session-id",
            "pi-session",
            "--working-dir",
            "/tmp/updated",
            "--note",
            "updated note",
        ],
    );
    assert!(update.status.success(), "stderr: {}", stderr(&update));
    assert_eq!(stdout(&update), "Updated title\n");

    let updated_json = perch(&home, &["list", "--all", "--json"]);
    assert!(
        updated_json.status.success(),
        "stderr: {}",
        stderr(&updated_json)
    );
    let updated: serde_json::Value = serde_json::from_str(&stdout(&updated_json)).unwrap();
    assert_eq!(updated.as_array().unwrap().len(), 1);
    assert_eq!(updated[0]["id"], id);
    assert_eq!(updated[0]["status"], "pending");
    assert_eq!(updated[0]["title"], "Updated title");
    assert_eq!(updated[0]["working_dir"], "/tmp/updated");
    assert_eq!(updated[0]["note"], "updated note");
    assert!(updated[0]["updated_at"].as_str().is_some());

    let done_by_id = perch(&home, &["done", &id]);
    assert!(done_by_id.status.success(), "stderr: {}", stderr(&done_by_id));
    assert_eq!(stdout(&done_by_id), "Done: Updated title\n");

    let reopen = perch(&home, &["reopen", &id]);
    assert!(reopen.status.success(), "stderr: {}", stderr(&reopen));
    assert_eq!(stdout(&reopen), "Reopened: Updated title\n");

    let reopened_list = perch(&home, &["list"]);
    assert!(
        reopened_list.status.success(),
        "stderr: {}",
        stderr(&reopened_list)
    );
    assert!(stdout(&reopened_list).contains("Updated title"));
}

#[test]
fn empty_list_json_outputs_empty_array() {
    let home = temp_home("empty-json");

    let list = perch(&home, &["list", "--json"]);

    assert!(list.status.success(), "stderr: {}", stderr(&list));
    assert_eq!(stdout(&list), "[]\n");
}

#[test]
fn done_errors_exit_nonzero() {
    let home = temp_home("errors");

    let missing_selector = perch(&home, &["done"]);
    assert!(!missing_selector.status.success());
    assert!(stderr(&missing_selector).contains("Provide a session ID or --session-id"));

    let no_match = perch(&home, &["done", "missing"]);
    assert!(!no_match.status.success());
    assert!(stderr(&no_match).contains("No session found"));
}
