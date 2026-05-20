use anyhow::{anyhow, bail, Context, Result};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub const LABEL: &str = "com.resciencelab.perch";
const APP_PROCESS_NAME: &str = "PerchApp";

#[cfg(not(target_os = "macos"))]
pub fn start(_app_path: Option<PathBuf>) -> Result<()> {
    bail!("Perch menu bar app controls are only supported on macOS")
}

#[cfg(not(target_os = "macos"))]
pub fn stop() -> Result<()> {
    bail!("Perch menu bar app controls are only supported on macOS")
}

#[cfg(not(target_os = "macos"))]
pub fn status() -> Result<()> {
    bail!("Perch menu bar app controls are only supported on macOS")
}

#[cfg(not(target_os = "macos"))]
pub fn login_enable(_app_path: Option<PathBuf>) -> Result<()> {
    bail!("Perch menu bar launch-at-login controls are only supported on macOS")
}

#[cfg(not(target_os = "macos"))]
pub fn login_disable() -> Result<()> {
    bail!("Perch menu bar launch-at-login controls are only supported on macOS")
}

#[cfg(not(target_os = "macos"))]
pub fn login_status() -> Result<()> {
    bail!("Perch menu bar launch-at-login controls are only supported on macOS")
}

#[cfg(target_os = "macos")]
pub fn start(app_path: Option<PathBuf>) -> Result<()> {
    let app = find_app_path(app_path)?;
    let expected_executable = resolve_executable(&app)?;
    let running = running_instances()?;
    let matching_pids = matching_instance_pids(&running, &expected_executable);
    if !matching_pids.is_empty() {
        println!(
            "Perch menu bar app is already running: {}",
            format_pids(&matching_pids)
        );
        return Ok(());
    }

    if is_app_bundle(&app) {
        run_command("/usr/bin/open", &[app.as_os_str()])?;
    } else {
        Command::new(&expected_executable)
            .spawn()
            .with_context(|| format!("failed to start {}", expected_executable.display()))?;
    }
    println!("Started Perch menu bar app: {}", app.display());
    Ok(())
}

#[cfg(target_os = "macos")]
pub fn stop() -> Result<()> {
    let instances = running_instances()?;
    if instances.is_empty() {
        println!("Perch menu bar app is stopped.");
        return Ok(());
    }

    let pids: Vec<u32> = instances.iter().map(|instance| instance.pid).collect();
    for pid in &pids {
        let pid_arg = pid.to_string();
        run_command(
            "/bin/kill",
            &[
                std::ffi::OsStr::new("-TERM"),
                std::ffi::OsStr::new(&pid_arg),
            ],
        )?;
    }
    println!("Stopped Perch menu bar app: {}", format_pids(&pids));
    Ok(())
}

#[cfg(target_os = "macos")]
pub fn status() -> Result<()> {
    let instances = running_instances()?;
    if instances.is_empty() {
        println!("Perch menu bar app: stopped");
    } else {
        let pids: Vec<u32> = instances.iter().map(|instance| instance.pid).collect();
        println!("Perch menu bar app: running ({})", format_pids(&pids));
    }
    Ok(())
}

#[cfg(target_os = "macos")]
pub fn login_enable(app_path: Option<PathBuf>) -> Result<()> {
    let app = find_app_path(app_path)?;
    let executable = resolve_executable(&app)?;
    let home = home_dir()?;
    let plist = plist_path_for_home(&home);
    enable_login_at(&executable, &plist, run_launchctl)
}

#[cfg(target_os = "macos")]
pub fn login_disable() -> Result<()> {
    let home = home_dir()?;
    let plist = plist_path_for_home(&home);
    disable_login_at(&plist, run_launchctl)?;
    println!("Launch at login disabled.");
    Ok(())
}

#[cfg(target_os = "macos")]
pub fn login_status() -> Result<()> {
    let home = home_dir()?;
    let plist = plist_path_for_home(&home);
    if plist.exists() {
        let executable = fs::read_to_string(&plist)
            .ok()
            .and_then(|contents| configured_executable_from_plist(&contents));
        match executable {
            Some(path) => println!("Launch at login: enabled ({path})"),
            None => println!("Launch at login: enabled ({})", plist.display()),
        }
    } else {
        println!("Launch at login: disabled");
    }
    Ok(())
}

#[derive(Debug, Clone)]
struct RunningInstance {
    pid: u32,
    executable: PathBuf,
}

#[cfg(target_os = "macos")]
fn running_instances() -> Result<Vec<RunningInstance>> {
    let pgrep = env::var_os("PERCH_PGREP")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/usr/bin/pgrep"));
    let output = Command::new(&pgrep)
        .args(["-x", APP_PROCESS_NAME])
        .output()
        .context("failed to run pgrep")?;

    if !output.status.success() {
        return Ok(Vec::new());
    }

    let known_executables = known_executable_paths();
    let stdout = String::from_utf8(output.stdout).context("pgrep output was not UTF-8")?;
    let mut instances = Vec::new();
    for pid in stdout
        .lines()
        .filter_map(|line| line.trim().parse::<u32>().ok())
    {
        if let Some(executable) = process_executable_path(pid) {
            if known_executables
                .iter()
                .any(|known| paths_equal(known, &executable))
            {
                instances.push(RunningInstance { pid, executable });
            }
        }
    }
    Ok(instances)
}

#[cfg(target_os = "macos")]
fn process_executable_path(pid: u32) -> Option<PathBuf> {
    let override_name = format!("PERCH_PROCESS_PATH_{pid}");
    if let Some(path) = env::var_os(override_name) {
        return Some(PathBuf::from(path));
    }

    let mut buffer = vec![0u8; 4096];
    let length =
        unsafe { proc_pidpath(pid as i32, buffer.as_mut_ptr().cast(), buffer.len() as u32) };
    if length <= 0 {
        return None;
    }
    let path = String::from_utf8_lossy(&buffer[..length as usize]).to_string();
    Some(PathBuf::from(path))
}

#[cfg(target_os = "macos")]
extern "C" {
    fn proc_pidpath(pid: i32, buffer: *mut std::ffi::c_void, buffersize: u32) -> i32;
}

#[cfg(target_os = "macos")]
fn run_command(program: &str, args: &[&std::ffi::OsStr]) -> Result<()> {
    let program_path = tool_override(program);
    let output = Command::new(&program_path)
        .args(args)
        .output()
        .with_context(|| format!("failed to run {}", program_path.display()))?;
    if output.status.success() {
        return Ok(());
    }
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    if stderr.is_empty() {
        bail!("{program} failed with status {}", output.status);
    }
    bail!("{program} failed with status {}: {stderr}", output.status)
}

#[cfg(target_os = "macos")]
fn run_launchctl(args: &[String]) -> Result<()> {
    let launchctl = env::var_os("PERCH_LAUNCHCTL")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/bin/launchctl"));
    let output = Command::new(&launchctl)
        .args(args)
        .output()
        .with_context(|| format!("failed to run {}", launchctl.display()))?;
    if output.status.success() {
        return Ok(());
    }
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    let hint = launchctl_hint(args, &stderr);
    if stderr.is_empty() {
        bail!(
            "launchctl {} failed with status {}. {hint}",
            args.join(" "),
            output.status
        );
    }
    bail!(
        "launchctl {} failed with status {}: {stderr}. {hint}",
        args.join(" "),
        output.status
    )
}

fn tool_override(program: &str) -> PathBuf {
    match program {
        "/usr/bin/open" => env::var_os("PERCH_OPEN").map(PathBuf::from),
        "/bin/kill" => env::var_os("PERCH_KILL").map(PathBuf::from),
        _ => None,
    }
    .unwrap_or_else(|| PathBuf::from(program))
}

fn launchctl_hint(args: &[String], stderr: &str) -> &'static str {
    if stderr.contains("Permission denied") || stderr.contains("Operation not permitted") {
        "Check macOS permissions for the current user and LaunchAgents directory."
    } else if args.first().is_some_and(|arg| arg == "bootstrap") {
        "Verify the LaunchAgent plist is valid XML and references an executable PerchApp path."
    } else if args.first().is_some_and(|arg| arg == "enable") {
        "Verify the service label is com.resciencelab.perch in the current gui/$UID domain."
    } else {
        "Run `perch menubar login status` for the configured LaunchAgent path."
    }
}

fn format_pids(pids: &[u32]) -> String {
    pids.iter()
        .map(u32::to_string)
        .collect::<Vec<_>>()
        .join(", ")
}

fn home_dir() -> Result<PathBuf> {
    env::var_os("HOME")
        .map(PathBuf::from)
        .filter(|path| !path.as_os_str().is_empty())
        .ok_or_else(|| anyhow!("HOME is not set"))
}

fn plist_path_for_home(home: &Path) -> PathBuf {
    home.join("Library")
        .join("LaunchAgents")
        .join(format!("{LABEL}.plist"))
}

fn is_app_bundle(path: &Path) -> bool {
    path.extension().is_some_and(|extension| extension == "app")
}

fn resolve_executable(path: &Path) -> Result<PathBuf> {
    let executable = if is_app_bundle(path) {
        path.join("Contents").join("MacOS").join(APP_PROCESS_NAME)
    } else {
        path.to_path_buf()
    };
    validate_executable(&executable)?;
    Ok(executable)
}

fn validate_executable(path: &Path) -> Result<()> {
    if !path.exists() {
        bail!("PerchApp executable does not exist: {}", path.display());
    }
    if !path.is_file() {
        bail!("PerchApp executable is not a file: {}", path.display());
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = fs::metadata(path)
            .with_context(|| format!("failed to inspect {}", path.display()))?
            .permissions()
            .mode();
        if mode & 0o111 == 0 {
            bail!("PerchApp executable is not executable: {}", path.display());
        }
    }
    Ok(())
}

fn find_app_path(explicit: Option<PathBuf>) -> Result<PathBuf> {
    if let Some(path) = explicit {
        if is_app_bundle(&path) {
            if path.exists() {
                return Ok(path);
            }
            bail!("Perch.app bundle does not exist: {}", path.display());
        }
        validate_executable(&path)?;
        return Ok(path);
    }

    let candidates = candidate_app_paths(None);
    for candidate in candidates {
        if is_app_bundle(&candidate) {
            if candidate.exists() {
                return Ok(candidate);
            }
        } else if candidate.is_file() {
            return Ok(candidate);
        }
    }

    bail!(
        "PerchApp was not found. Current CLI releases look for ~/.local/share/perch/Perch.app, ~/.local/share/perch/PerchApp, ~/Applications/Perch.app, /Applications/Perch.app, or local App/.build outputs. Run PERCH_INSTALL_APP=1 ./install.sh to install it."
    )
}

fn candidate_app_paths(explicit: Option<PathBuf>) -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if let Some(path) = explicit {
        paths.push(path);
    }
    if let Some(home) = env::var_os("HOME").map(PathBuf::from) {
        paths.push(home.join(".local/share/perch/Perch.app"));
        paths.push(home.join(".local/share/perch/PerchApp"));
        paths.push(home.join("Applications/Perch.app"));
    }
    paths.push(PathBuf::from("/Applications/Perch.app"));

    if let Ok(current_dir) = env::current_dir() {
        for root in current_dir.ancestors() {
            paths.extend([
                root.join("App/.build/arm64-apple-macosx/release/PerchApp"),
                root.join("App/.build/x86_64-apple-macosx/release/PerchApp"),
                root.join("App/.build/release/PerchApp"),
                root.join("App/.build/arm64-apple-macosx/debug/PerchApp"),
                root.join("App/.build/x86_64-apple-macosx/debug/PerchApp"),
                root.join("App/.build/debug/PerchApp"),
            ]);
        }
    }

    paths
}

fn known_executable_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();
    for candidate in candidate_app_paths(None) {
        if let Ok(executable) = resolve_executable(&candidate) {
            paths.push(executable);
        }
    }
    if let Ok(home) = home_dir() {
        let plist = plist_path_for_home(&home);
        if let Ok(contents) = fs::read_to_string(plist) {
            if let Some(path) = configured_executable_from_plist(&contents) {
                paths.push(PathBuf::from(path));
            }
        }
    }
    paths
}

fn matching_instance_pids(instances: &[RunningInstance], executable: &Path) -> Vec<u32> {
    instances
        .iter()
        .filter(|instance| paths_equal(&instance.executable, executable))
        .map(|instance| instance.pid)
        .collect()
}

fn paths_equal(left: &Path, right: &Path) -> bool {
    let canonical_left = fs::canonicalize(left).unwrap_or_else(|_| left.to_path_buf());
    let canonical_right = fs::canonicalize(right).unwrap_or_else(|_| right.to_path_buf());
    canonical_left == canonical_right
}

fn launch_agent_plist(executable_path: &Path) -> String {
    format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n\
<plist version=\"1.0\">\n\
<dict>\n\
    <key>Label</key>\n\
    <string>{}</string>\n\
    <key>ProgramArguments</key>\n\
    <array>\n\
        <string>{}</string>\n\
    </array>\n\
    <key>RunAtLoad</key>\n\
    <true/>\n\
    <key>KeepAlive</key>\n\
    <false/>\n\
    <key>LimitLoadToSessionType</key>\n\
    <string>Aqua</string>\n\
    <key>ProcessType</key>\n\
    <string>Interactive</string>\n\
</dict>\n\
</plist>\n",
        xml_escape(LABEL),
        xml_escape(&executable_path.to_string_lossy())
    )
}

fn configured_executable_from_plist(contents: &str) -> Option<String> {
    let value = plist::Value::from_reader_xml(contents.as_bytes()).ok()?;
    let dictionary = value.as_dictionary()?;
    let arguments = dictionary.get("ProgramArguments")?.as_array()?;
    arguments.first()?.as_string().map(ToOwned::to_owned)
}

fn enable_login_at(
    executable: &Path,
    plist: &Path,
    launchctl: impl Fn(&[String]) -> Result<()>,
) -> Result<()> {
    validate_executable(executable)?;
    let parent = plist
        .parent()
        .ok_or_else(|| anyhow!("invalid LaunchAgent plist path: {}", plist.display()))?;
    fs::create_dir_all(parent).with_context(|| format!("failed to create {}", parent.display()))?;

    let tmp = plist.with_extension("plist.tmp");
    fs::write(&tmp, launch_agent_plist(executable))
        .with_context(|| format!("failed to write {}", tmp.display()))?;
    fs::rename(&tmp, plist).with_context(|| format!("failed to write {}", plist.display()))?;

    let uid = uid_string();
    let bootout = vec!["bootout".to_string(), format!("gui/{uid}/{LABEL}")];
    let bootstrap = vec![
        "bootstrap".to_string(),
        format!("gui/{uid}"),
        plist.display().to_string(),
    ];
    let enable = vec!["enable".to_string(), format!("gui/{uid}/{LABEL}")];

    if let Err(error) = launchctl(&bootout) {
        if !is_ignorable_bootout_error(&error) {
            return Err(error);
        }
    }
    if let Err(error) = launchctl(&bootstrap).and_then(|_| launchctl(&enable)) {
        let _ = fs::remove_file(plist);
        return Err(error);
    }

    println!("Launch at login enabled: {}", executable.display());
    Ok(())
}

fn disable_login_at(plist: &Path, launchctl: impl Fn(&[String]) -> Result<()>) -> Result<()> {
    let uid = uid_string();
    let bootout = vec!["bootout".to_string(), format!("gui/{uid}/{LABEL}")];
    if let Err(error) = launchctl(&bootout) {
        if !is_ignorable_bootout_error(&error) {
            return Err(error);
        }
    }
    if plist.exists() {
        fs::remove_file(plist).with_context(|| format!("failed to remove {}", plist.display()))?;
    }
    Ok(())
}

fn is_ignorable_bootout_error(error: &anyhow::Error) -> bool {
    let message = error.to_string();
    message.contains("No such service")
        || message.contains("not found")
        || message.contains("service is not loaded")
        || message.contains("Could not find service")
}

#[cfg(unix)]
fn uid_string() -> String {
    unsafe { libc_getuid() }.to_string()
}

#[cfg(unix)]
extern "C" {
    #[link_name = "getuid"]
    fn libc_getuid() -> u32;
}

#[cfg(not(unix))]
fn uid_string() -> String {
    "0".to_string()
}

fn xml_escape(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use std::os::unix::fs::PermissionsExt;
    use std::rc::Rc;
    use std::sync::atomic::{AtomicUsize, Ordering};

    static TEST_COUNTER: AtomicUsize = AtomicUsize::new(0);

    fn temp_dir(name: &str) -> PathBuf {
        let id = TEST_COUNTER.fetch_add(1, Ordering::SeqCst);
        let dir = env::temp_dir().join(format!(
            "perch-menubar-tests-{}-{name}-{id}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn executable(path: &Path) {
        fs::write(path, "#!/bin/sh\nexit 0\n").unwrap();
        let mut permissions = fs::metadata(path).unwrap().permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(path, permissions).unwrap();
    }

    #[test]
    fn plist_generation_escapes_executable_path() {
        let plist = launch_agent_plist(Path::new("/tmp/Perch & <App>'\""));
        assert!(plist.contains("<string>com.resciencelab.perch</string>"));
        assert!(plist.contains("/tmp/Perch &amp; &lt;App&gt;&apos;&quot;"));
        assert!(plist.contains("<key>RunAtLoad</key>"));
        assert!(plist.contains("<false/>"));
    }

    #[test]
    fn configured_executable_reads_first_program_argument() {
        let plist = launch_agent_plist(Path::new("/tmp/Perch & App"));
        assert_eq!(
            configured_executable_from_plist(&plist).as_deref(),
            Some("/tmp/Perch & App")
        );
    }

    #[test]
    fn validate_executable_rejects_missing_and_non_executable_paths() {
        let dir = temp_dir("validate");
        let missing = dir.join("missing");
        assert!(validate_executable(&missing).is_err());

        let non_executable = dir.join("PerchApp");
        fs::write(&non_executable, "not executable").unwrap();
        let mut permissions = fs::metadata(&non_executable).unwrap().permissions();
        permissions.set_mode(0o644);
        fs::set_permissions(&non_executable, permissions).unwrap();
        assert!(validate_executable(&non_executable).is_err());
    }

    #[test]
    fn resolve_executable_supports_app_bundle() {
        let dir = temp_dir("bundle");
        let app_executable = dir.join("Perch.app/Contents/MacOS/PerchApp");
        fs::create_dir_all(app_executable.parent().unwrap()).unwrap();
        executable(&app_executable);
        assert_eq!(
            resolve_executable(&dir.join("Perch.app")).unwrap(),
            app_executable
        );
    }

    #[test]
    fn matching_instance_pids_filters_by_executable_path() {
        let dir = temp_dir("matching");
        let expected = dir.join("PerchApp");
        let unrelated = dir.join("Other/PerchApp");
        fs::create_dir_all(unrelated.parent().unwrap()).unwrap();
        executable(&expected);
        executable(&unrelated);

        let instances = vec![
            RunningInstance {
                pid: 10,
                executable: expected.clone(),
            },
            RunningInstance {
                pid: 20,
                executable: unrelated,
            },
        ];

        assert_eq!(matching_instance_pids(&instances, &expected), vec![10]);
    }

    #[test]
    fn find_app_path_rejects_invalid_explicit_path_instead_of_falling_back() {
        let dir = temp_dir("explicit");
        let missing = dir.join("missing-PerchApp");
        assert!(find_app_path(Some(missing)).is_err());
    }

    #[test]
    fn enable_login_writes_plist_and_runs_launchctl_sequence() {
        let dir = temp_dir("enable");
        let app = dir.join("PerchApp");
        executable(&app);
        let plist = dir.join("Library/LaunchAgents/com.resciencelab.perch.plist");
        let calls = Rc::new(RefCell::new(Vec::<Vec<String>>::new()));
        let observed = calls.clone();

        enable_login_at(&app, &plist, |args| {
            observed.borrow_mut().push(args.to_vec());
            Ok(())
        })
        .unwrap();

        let contents = fs::read_to_string(&plist).unwrap();
        assert!(contents.contains(&app.display().to_string()));
        let calls = calls.borrow();
        assert_eq!(calls[0][0], "bootout");
        assert_eq!(calls[0].len(), 2);
        assert!(calls[0][1].contains(LABEL));
        assert_eq!(calls[1][0], "bootstrap");
        assert_eq!(calls[2][0], "enable");
    }

    #[test]
    fn enable_login_reports_unexpected_bootout_failure() {
        let dir = temp_dir("bootout-fail");
        let app = dir.join("PerchApp");
        executable(&app);
        let plist = dir.join("Library/LaunchAgents/com.resciencelab.perch.plist");

        let result = enable_login_at(&app, &plist, |args| {
            if args.first().is_some_and(|arg| arg == "bootout") {
                bail!("Permission denied");
            }
            Ok(())
        });

        assert!(result.is_err());
    }

    #[test]
    fn enable_login_ignores_missing_service_bootout_failure() {
        let dir = temp_dir("bootout-missing");
        let app = dir.join("PerchApp");
        executable(&app);
        let plist = dir.join("Library/LaunchAgents/com.resciencelab.perch.plist");

        enable_login_at(&app, &plist, |args| {
            if args.first().is_some_and(|arg| arg == "bootout") {
                bail!("No such service");
            }
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn enable_login_removes_plist_when_bootstrap_fails() {
        let dir = temp_dir("enable-fail");
        let app = dir.join("PerchApp");
        executable(&app);
        let plist = dir.join("Library/LaunchAgents/com.resciencelab.perch.plist");

        let result = enable_login_at(&app, &plist, |args| {
            if args.first().is_some_and(|arg| arg == "bootstrap") {
                bail!("bootstrap failed");
            }
            Ok(())
        });

        assert!(result.is_err());
        assert!(!plist.exists());
    }

    #[test]
    fn disable_login_is_idempotent() {
        let dir = temp_dir("disable");
        let plist = dir.join("Library/LaunchAgents/com.resciencelab.perch.plist");
        fs::create_dir_all(plist.parent().unwrap()).unwrap();
        fs::write(&plist, "plist").unwrap();

        disable_login_at(&plist, |_| Ok(())).unwrap();
        disable_login_at(&plist, |_| Ok(())).unwrap();

        assert!(!plist.exists());
    }
}
