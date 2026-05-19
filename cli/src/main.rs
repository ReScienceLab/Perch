mod doctor;
mod menubar;
mod store;

use clap::{Parser, Subcommand};
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "perch", version, about = "Perch session manager")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Save a session to Perch
    Add {
        #[arg(long)]
        title: String,
        /// Agent name: claude, codex, or pi
        #[arg(long)]
        agent: String,
        /// Agent-native session ID
        #[arg(long)]
        session_id: String,
        /// Working directory (defaults to $PWD)
        #[arg(long)]
        working_dir: Option<String>,
        #[arg(long, default_value = "")]
        note: String,
    },
    /// List sessions
    List {
        /// Include done sessions
        #[arg(long)]
        all: bool,
        /// Output raw JSON
        #[arg(long)]
        json: bool,
    },
    /// Mark a session as done
    Done {
        /// Perch session ID or unique prefix
        id_or_prefix: Option<String>,
        /// Look up by agent-native session ID (e.g. ${CLAUDE_SESSION_ID})
        #[arg(long)]
        session_id: Option<String>,
    },
    /// Reopen a done session (mark it as pending again)
    Reopen {
        /// Perch session ID or unique prefix
        id_or_prefix: Option<String>,
        /// Look up by agent-native session ID
        #[arg(long)]
        session_id: Option<String>,
    },
    /// Diagnose Perch CLI, config, and agent command installation
    Doctor {
        /// Output machine-readable JSON
        #[arg(long)]
        json: bool,
    },
    /// Control the native macOS menu bar app
    Menubar {
        #[command(subcommand)]
        command: MenubarCommands,
    },
}

#[derive(Subcommand)]
enum MenubarCommands {
    /// Start the menu bar app
    Start {
        /// Explicit PerchApp executable or Perch.app bundle path
        #[arg(long)]
        app_path: Option<PathBuf>,
    },
    /// Stop the menu bar app
    Stop,
    /// Show whether the menu bar app is running
    Status,
    /// Manage launch-at-login for the menu bar app
    Login {
        #[command(subcommand)]
        command: MenubarLoginCommands,
    },
}

#[derive(Subcommand)]
enum MenubarLoginCommands {
    /// Enable launch-at-login
    Enable {
        /// Explicit PerchApp executable or Perch.app bundle path
        #[arg(long)]
        app_path: Option<PathBuf>,
    },
    /// Disable launch-at-login
    Disable,
    /// Show launch-at-login status
    Status,
}

fn main() {
    let cli = Cli::parse();

    let result = match cli.command {
        Commands::Add {
            title,
            agent,
            session_id,
            working_dir,
            note,
        } => store::add(title, agent, session_id, working_dir, note),
        Commands::List { all, json } => store::list(all, json),
        Commands::Done {
            id_or_prefix,
            session_id,
        } => store::done(id_or_prefix, session_id),
        Commands::Reopen {
            id_or_prefix,
            session_id,
        } => store::reopen(id_or_prefix, session_id),
        Commands::Doctor { json } => doctor::run(json),
        Commands::Menubar { command } => match command {
            MenubarCommands::Start { app_path } => menubar::start(app_path),
            MenubarCommands::Stop => menubar::stop(),
            MenubarCommands::Status => menubar::status(),
            MenubarCommands::Login { command } => match command {
                MenubarLoginCommands::Enable { app_path } => menubar::login_enable(app_path),
                MenubarLoginCommands::Disable => menubar::login_disable(),
                MenubarLoginCommands::Status => menubar::login_status(),
            },
        },
    };

    if let Err(e) = result {
        eprintln!("Error: {e}");
        std::process::exit(1);
    }
}
