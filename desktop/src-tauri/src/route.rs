//! 0.4 «Роли»: pure routing decisions — task type → role → node, with fallback to the PC (main model / PC embeddings).
//! No I/O and no crate dependencies here, so the rules are unit-tested on their own (docs/ROLES.md «Очередь задач»).
//! Callers: queue.rs (Ночная очередь), helper.rs (`run_small_task`: agent subtasks), rag.rs (Поиск), helper.rs (RAM check),
//! settings.rs (helper out of the experiment).

/// What has to be done.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Task {
    /// chat title, «Сводка»
    Summary,
    Translate,
    /// user's own prompt over a file (Очередь «Своё задание»): may need the big model
    Custom,
    /// small piece of work handed out by the agent (summarize / translate / extract a chunk)
    AgentSubtask,
    /// embeddings for «Поиск по файлам»
    Embed,
    /// speech → text
    Transcribe,
}

/// Node roles that serve tasks.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RoleKind { Helper, Search, Voice }

impl Task {
    pub fn parse(s: &str) -> Option<Task> {
        Some(match s.trim().to_ascii_lowercase().as_str() {
            "summary" | "summarize" | "title" => Task::Summary,
            "translate" => Task::Translate,
            "custom" => Task::Custom,
            "subtask" | "extract" | "agent" => Task::AgentSubtask,
            "embed" | "embeddings" => Task::Embed,
            "transcribe" | "voice" => Task::Transcribe,
            _ => return None,
        })
    }
}

/// task type → role. `None` = only the main model (PC) does it.
pub fn role_for(t: Task) -> Option<RoleKind> {
    match t {
        Task::Summary | Task::Translate | Task::AgentSubtask => Some(RoleKind::Helper),
        Task::Embed => Some(RoleKind::Search),
        Task::Transcribe => Some(RoleKind::Voice),
        Task::Custom => None,
    }
}

/// One node offering a role right now.
#[derive(Debug, Clone, PartialEq)]
pub struct Cand {
    pub node: String,
    pub base: String,
    pub ready: bool,
    /// requests in flight
    pub busy: u32,
}

/// role → node: the least busy ready candidate that has not failed in this task (`exclude` = node ids).
/// Ties keep the caller's order (USB before Wi-Fi when the caller sorted so).
pub fn pick<'a>(cands: &'a [Cand], exclude: &[String]) -> Option<&'a Cand> {
    let mut best: Option<&Cand> = None;
    for c in cands.iter().filter(|c| c.ready && !c.base.is_empty() && !exclude.contains(&c.node)) {
        if best.map(|b| c.busy < b.busy).unwrap_or(true) { best = Some(c); }
    }
    best
}

/// Where an LLM task runs.
#[derive(Debug, Clone, PartialEq)]
pub enum Backend {
    /// a node with the role
    Node(Cand),
    /// the main model on the PC (llama-server :LLAMA_PORT)
    Main,
    /// nothing can run it now (no ready node, main model stopped): wait and retry
    Wait,
}

/// `route`: "main" = main model only (old jobs, «Своё задание»), anything else ("auto") = role node first.
/// Fallback when the node is gone / failed (`exclude`): the main model; when that is down too: wait.
pub fn backend(route: &str, task: Task, cands: &[Cand], exclude: &[String], main_up: bool) -> Backend {
    if route != "main" && role_for(task) == Some(RoleKind::Helper) {
        if let Some(c) = pick(cands, exclude) { return Backend::Node(c.clone()); }
    }
    if main_up { Backend::Main } else { Backend::Wait }
}

/// Chunk size (characters) for a queue file: a helper runs with a 4096-token context, so it gets halves.
pub fn chunk_chars(task: Task, on_helper: bool) -> usize {
    let base = if task == Task::Translate { 3000 } else { 6000 };
    if on_helper { base / 2 } else { base }
}

/// Output budget (tokens) for one chunk on a helper.
pub fn helper_max_tokens(task: Task) -> u32 {
    match task { Task::Translate => 2048, Task::Summary => 768, _ => 1024 }
}

/// Free RAM (MB) a node needs before it is given a helper model: weights + ~50 % (KV cache for -c 4096, buffers) + 512 MB
/// for Android itself. Conservative on purpose: an OOM-killed node also drops its rpc-server.
pub fn helper_need_mb(model_bytes: u64) -> u64 {
    let m = model_bytes >> 20;
    m + m / 2 + 512
}

/// Embedding model (~140 MB) + batch buffers + headroom.
pub fn search_need_mb(model_bytes: u64) -> u64 { (model_bytes >> 20) + 384 }

/// `avail_mb == 0` = the node did not report its RAM (old node / not measured yet): do not block on it.
pub fn fits_ram(avail_mb: u64, need_mb: u64) -> bool { avail_mb == 0 || avail_mb >= need_mb }

/// Whether the node may be given (or keep being given) a role model: a node that already runs this model has its RAM
/// in use, so only a NEW assignment is checked.
pub fn may_assign(already_running_this_model: bool, avail_mb: u64, need_mb: u64) -> bool {
    already_running_this_model || fits_ram(avail_mb, need_mb)
}

/// 0.4: «Помощник» left the experiment. Settings files written by 0.3.x always contain `rolesEnabled`, so «false» there
/// may be the old default or the user's choice. It counts as the user's choice only when some node still has the helper
/// role (the user assigned it and then switched the experiment off); otherwise roles are switched on.
/// New installs get `true` from Settings::default().
pub fn migrate_roles_enabled(saved: bool, any_helper_role: bool) -> bool { saved || !any_helper_role }

/// Embedding service order for «Поиск»: custom URL alone, else ready nodes (minus failed ones), the PC last (None).
pub fn embed_bases(custom: &str, nodes: &[String], failed: &[String]) -> Vec<String> {
    let c = custom.trim().trim_end_matches('/');
    if !c.is_empty() { return vec![c.to_string()]; }
    let mut out: Vec<String> = Vec::new();
    for b in nodes {
        let b = b.trim_end_matches('/').to_string();
        if !failed.contains(&b) && !out.contains(&b) { out.push(b); }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn c(node: &str, ready: bool, busy: u32) -> Cand {
        Cand { node: node.into(), base: format!("http://{node}"), ready, busy }
    }

    #[test]
    fn task_to_role() {
        assert_eq!(role_for(Task::parse("translate").unwrap()), Some(RoleKind::Helper));
        assert_eq!(role_for(Task::parse("summarize").unwrap()), Some(RoleKind::Helper));
        assert_eq!(role_for(Task::parse("subtask").unwrap()), Some(RoleKind::Helper));
        assert_eq!(role_for(Task::parse("custom").unwrap()), None);
        assert_eq!(role_for(Task::Embed), Some(RoleKind::Search));
        assert_eq!(role_for(Task::Transcribe), Some(RoleKind::Voice));
        assert!(Task::parse("dance").is_none());
    }

    #[test]
    fn pick_least_busy_ready() {
        let v = vec![c("a", true, 2), c("b", false, 0), c("c", true, 1), c("d", true, 1)];
        assert_eq!(pick(&v, &[]).unwrap().node, "c");                       // tie c/d → first
        assert_eq!(pick(&v, &["c".into()]).unwrap().node, "d");
        assert_eq!(pick(&v, &["c".into(), "d".into(), "a".into()]), None);   // b is not ready
        let mut no_url = c("e", true, 0); no_url.base.clear();
        assert_eq!(pick(&[no_url], &[]), None);
    }

    #[test]
    fn backend_and_fallback() {
        let v = vec![c("a", true, 0)];
        assert_eq!(backend("auto", Task::Translate, &v, &[], true), Backend::Node(v[0].clone()));
        // node failed during the task → main model
        assert_eq!(backend("auto", Task::Translate, &v, &["a".into()], true), Backend::Main);
        // node gone and main model stopped → wait
        assert_eq!(backend("auto", Task::Summary, &[], &[], false), Backend::Wait);
        // main model down but a helper is ready → helper
        assert_eq!(backend("auto", Task::Summary, &v, &[], false), Backend::Node(v[0].clone()));
        // «main» route / custom prompt never go to a helper
        assert_eq!(backend("main", Task::Translate, &v, &[], true), Backend::Main);
        assert_eq!(backend("auto", Task::Custom, &v, &[], true), Backend::Main);
        assert_eq!(backend("", Task::Translate, &v, &[], false), Backend::Node(v[0].clone()));
    }

    #[test]
    fn sizes() {
        assert_eq!(chunk_chars(Task::Translate, false), 3000);
        assert_eq!(chunk_chars(Task::Translate, true), 1500);
        assert_eq!(chunk_chars(Task::Summary, true), 3000);
        assert!(helper_max_tokens(Task::Translate) > helper_max_tokens(Task::Summary));
    }

    #[test]
    fn ram() {
        // Qwen3 0.6B Q4_0 (364 MB) → 364 + 182 + 512
        assert_eq!(helper_need_mb(382_156_480), 1058);
        assert!(fits_ram(0, 5000));            // unknown
        assert!(fits_ram(2000, 1059));
        assert!(!fits_ram(900, 1059));
        assert!(may_assign(true, 100, 1059));  // already running: its RAM is in use
        assert!(!may_assign(false, 100, 1059));
        assert!(search_need_mb(140 << 20) == 524);
    }

    #[test]
    fn migration() {
        assert!(migrate_roles_enabled(true, false));
        assert!(migrate_roles_enabled(false, false));   // old default, never used → on
        assert!(!migrate_roles_enabled(false, true));   // helper assigned, then switched off → keep off
        assert!(migrate_roles_enabled(true, true));
    }

    #[test]
    fn embed_order() {
        let n = vec!["http://127.0.0.1:50160/".to_string(), "http://10.0.0.5:50060".into(), "http://127.0.0.1:50160".into()];
        assert_eq!(embed_bases("", &n, &[]), vec!["http://127.0.0.1:50160".to_string(), "http://10.0.0.5:50060".into()]);
        assert_eq!(embed_bases("", &n, &["http://127.0.0.1:50160".into()]), vec!["http://10.0.0.5:50060".to_string()]);
        assert_eq!(embed_bases(" http://x:1/ ", &n, &[]), vec!["http://x:1".to_string()]);
    }
}
