mod store;

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "perch", about = "Perch session manager")]
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
        /// Perch session ID prefix
        id: Option<String>,
        /// Look up by agent-native session ID (e.g. ${CLAUDE_SESSION_ID})
        #[arg(long)]
        session_id: Option<String>,
    },
    /// Reopen a done session (mark it as pending again)
    Reopen {
        /// Perch session ID prefix
        id: Option<String>,
        /// Look up by agent-native session ID
        #[arg(long)]
        session_id: Option<String>,
    },
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
        Commands::Done { id, session_id } => store::done(id, session_id),
        Commands::Reopen { id, session_id } => store::reopen(id, session_id),
    };

    if let Err(e) = result {
        eprintln!("Error: {e}");
        std::process::exit(1);
    }
}
