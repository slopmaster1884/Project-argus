//! «Проверить связь» / "Check connection": step-by-step diagnosis of why a LAN / Wi-Fi node is not reachable
//! (issue #3/#4: the beacon arrives on UDP 50053, but TCP to rpc-server :50052 fails → OFFLINE with no explanation).
//!
//! Steps (each one `DiagStep { id, ok, skipped, ms, code, arg, detail }`):
//!   1. `subnet` — the address is a home-network (private) IPv4 and sits in the same /24 as the PC interface the OS
//!      would use to reach it (UDP "connect" trick, no packets sent; the real netmask is not known, so a different /24
//!      inside the same private block is reported as "unknown" rather than "different");
//!   2. `beacon` — was a UDP beacon from that IP heard in the last 10 s (lan.rs beacon listener state);
//!   3. `tcp` — TCP connect to ip:port, refused / timeout / unreachable are told apart;
//!   4. `hello` — ggml-rpc HELLO (lan.rs `rpc_hello`): is it really rpc-server, and protocol v8 (llama.cpp b12008).
//! Then one `Verdict` + hint keys for i18n (`nd.fix.*` in i18n.ts). Total ≤ ~5.5 s.
//!
//! Everything above the "tauri command" marker is std + serde only, so it is unit-tested without the Tauri crate.
use serde::Serialize;
use std::{io, net::{IpAddr, Ipv4Addr}};

/// connect budget. Windows retries a refused SYN for ~1–2 s before it reports WSAECONNREFUSED,
/// so 2 s would turn "port closed" into a fake "timeout" there.
pub const TCP_TIMEOUT_MS: u64 = 3000;
pub const HELLO_TIMEOUT_MS: u64 = 2500;
/// beacons come every 2 s; same threshold as lan.rs BEACON_LOST
pub const BEACON_FRESH_SECS: u64 = 10;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DiagStep {
    /// "subnet" | "beacon" | "tcp" | "hello"
    pub id: &'static str,
    pub ok: bool,
    /// not run (or could not be judged) — shown as "–", not as ✗
    pub skipped: bool,
    pub ms: u32,
    /// i18n: `nd.code.<id>.<code>`
    pub code: &'static str,
    /// value substituted for `{x}` in the i18n string (seconds, IP, version …)
    pub arg: Option<String>,
    /// raw technical detail (OS error text, addresses) — shown small, not translated
    pub detail: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DiagReport {
    pub ip: String,
    pub port: u16,
    /// PC address on the route to the node (None = no route / unknown)
    pub local_ip: Option<String>,
    pub steps: Vec<DiagStep>,
    pub verdict: Verdict,
    /// i18n keys `nd.fix.<hint>`, most likely fix first
    pub hints: Vec<&'static str>,
    pub total_ms: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Verdict {
    Ok,
    FirewallLikely,
    RpcNotRunning,
    DifferentSubnet,
    ApIsolationLikely,
    VersionMismatch,
    /// rpc-server answers TCP but not HELLO: another PC / app is attached (it serves one client)
    RpcBusy,
    /// no route / host unreachable and no beacon: device off, asleep, or the IP changed
    Unreachable,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Subnet { Same, Different, Unknown }

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BeaconSeen { Fresh(u64), Stale(u64), NotSeen, ListenerDown }
impl BeaconSeen {
    pub fn fresh(self) -> bool { matches!(self, Self::Fresh(_)) }
    pub fn from_age(age: Option<u64>, listener_ok: bool) -> Self {
        match age {
            Some(a) if a <= BEACON_FRESH_SECS => Self::Fresh(a),
            Some(a) => Self::Stale(a),
            None if !listener_ok => Self::ListenerDown,
            None => Self::NotSeen,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tcp { Ok, Refused, Timeout, Unreachable, Other }

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Hello { Ok((u8, u8, u8)), Mismatch(Option<(u8, u8, u8)>), Busy, Garbled, Skipped, /** PIN-secured gateway (rpcauth) answered */ Secured }

/// home-network address: RFC 1918, link-local (169.254, no DHCP) or loopback (tests / a node on this PC)
pub fn is_lan(ip: Ipv4Addr) -> bool { ip.is_private() || ip.is_link_local() || ip.is_loopback() }

fn private_block(ip: Ipv4Addr) -> Option<u8> {
    let o = ip.octets();
    match o[0] {
        10 => Some(1),
        172 if (16..=31).contains(&o[1]) => Some(2),
        192 if o[1] == 168 => Some(3),
        169 if o[1] == 254 => Some(4),
        127 => Some(5),
        _ => None,
    }
}

/// `local` = PC address on the route to `target`. Same /24 → Same (typical home router); different private
/// blocks (192.168.x vs 10.x) or no route → Different; same block but another /24 → Unknown (mask may be wider).
pub fn subnet_of(local: Option<Ipv4Addr>, target: Ipv4Addr) -> Subnet {
    if target.is_loopback() { return Subnet::Same; }
    let Some(l) = local.filter(|l| !l.is_unspecified()) else { return Subnet::Different };
    if l.is_loopback() { return Subnet::Unknown; }
    let (a, b) = (l.octets(), target.octets());
    if a[..3] == b[..3] { return Subnet::Same; }
    match (private_block(l), private_block(target)) {
        (Some(x), Some(y)) if x != y => Subnet::Different,
        (Some(_), Some(_)) => Subnet::Unknown,
        _ => Subnet::Unknown,
    }
}

/// connect() error → what it means. Raw codes cover Linux / macOS / Windows (WSA*).
pub fn classify_connect_error(e: &io::Error) -> Tcp {
    match e.kind() {
        io::ErrorKind::ConnectionRefused => return Tcp::Refused,
        io::ErrorKind::TimedOut => return Tcp::Timeout,
        io::ErrorKind::HostUnreachable | io::ErrorKind::NetworkUnreachable => return Tcp::Unreachable,
        _ => {}
    }
    match e.raw_os_error() {
        // ECONNREFUSED: Linux 111, macOS 61, Windows 10061
        Some(111) | Some(61) | Some(10061) => Tcp::Refused,
        // ETIMEDOUT: Linux 110, macOS 60, Windows 10060
        Some(110) | Some(60) | Some(10060) => Tcp::Timeout,
        // EHOSTUNREACH / ENETUNREACH: Linux 113/101, macOS 65/51, Windows 10065/10051
        Some(113) | Some(101) | Some(65) | Some(51) | Some(10065) | Some(10051) => Tcp::Unreachable,
        _ => Tcp::Other,
    }
}

/// HELLO result → outcome. Error strings come from lan.rs `rpc_hello` / `recv`.
pub fn classify_hello(r: Result<(u8, u8, u8), String>, major: u8) -> Hello {
    match r {
        Ok(v) if v.0 == major => Hello::Ok(v),
        Ok(v) => Hello::Mismatch(Some(v)),
        Err(e) => {
            let l = e.to_lowercase();
            if l.contains("secured gateway") { Hello::Secured }
            else if l.contains("hello timeout") { Hello::Busy }
            // pre-v3 servers answer HELLO with 3 bytes, very old ones drop the connection on the unknown command
            else if l.contains("reply size") || l.contains("early eof") || l.contains("unexpected eof") || l.contains("reset") { Hello::Mismatch(None) }
            else { Hello::Garbled }
        }
    }
}

/// The verdict. Pure, so the whole decision table is unit-tested.
pub fn verdict(subnet: Subnet, beacon: BeaconSeen, tcp: Tcp, hello: Hello, major: u8) -> Verdict {
    match tcp {
        Tcp::Ok => match hello {
            Hello::Ok(v) if v.0 == major => Verdict::Ok,
            Hello::Ok(_) | Hello::Mismatch(_) => Verdict::VersionMismatch,
            Hello::Busy => Verdict::RpcBusy,
            Hello::Secured => Verdict::Ok, // secured node: reachable, auth is checked on add/pair
            Hello::Skipped => Verdict::Ok, // the running model holds the connection: TCP alive is all we can know
            Hello::Garbled => Verdict::Unknown,
        },
        // the machine answered with RST: it is reachable, nothing listens on the port
        Tcp::Refused => Verdict::RpcNotRunning,
        Tcp::Timeout => {
            if subnet == Subnet::Different { Verdict::DifferentSubnet }
            // beacons get through, TCP is silently dropped → firewall on the node (ufw default deny = DROP)
            else if beacon.fresh() { Verdict::FirewallLikely }
            else if subnet == Subnet::Same && matches!(beacon, BeaconSeen::NotSeen | BeaconSeen::Stale(_)) { Verdict::ApIsolationLikely }
            else { Verdict::Unknown }
        }
        Tcp::Unreachable => {
            if subnet == Subnet::Different { Verdict::DifferentSubnet }
            // firewalld default REJECTs with icmp-host-prohibited → "unreachable" while beacons arrive
            else if beacon.fresh() { Verdict::FirewallLikely }
            else { Verdict::Unreachable }
        }
        Tcp::Other => if subnet == Subnet::Different { Verdict::DifferentSubnet } else { Verdict::Unknown },
    }
}

/// i18n hint keys (`nd.fix.*`), most likely fix first. Commands (with the real port) are added by the UI.
pub fn hints(v: Verdict) -> Vec<&'static str> {
    match v {
        Verdict::Ok => vec![],
        Verdict::FirewallLikely => vec!["linuxScript", "linuxUfw", "linuxFirewalld", "windowsFirewall"],
        Verdict::RpcNotRunning => vec!["restartNode", "checkPort"],
        Verdict::DifferentSubnet => vec!["sameWifi", "guestNetwork", "checkIp"],
        Verdict::ApIsolationLikely => vec!["apIsolation", "guestNetwork", "deviceOn", "pcFirewall"],
        Verdict::VersionMismatch => vec!["updateNode"],
        Verdict::RpcBusy => vec!["busy"],
        Verdict::Unreachable => vec!["deviceOn", "checkIp", "sameWifi"],
        Verdict::Unknown => vec!["linuxScript", "windowsFirewall", "apIsolation", "restartNode"],
    }
}

pub fn subnet_step(ip: IpAddr, local: Option<IpAddr>) -> (DiagStep, Subnet) {
    let mut st = DiagStep { id: "subnet", ok: false, skipped: false, ms: 0, code: "unknown", arg: Some(ip.to_string()), detail: String::new() };
    let IpAddr::V4(t) = ip else {
        st.skipped = true; st.code = "ipv6";
        return (st, Subnet::Unknown);
    };
    let l4 = match local { Some(IpAddr::V4(l)) => Some(l), _ => None };
    let sn = subnet_of(l4, t);
    st.detail = match l4 { Some(l) => format!("PC {l} → node {t}"), None => format!("no route to {t}") };
    if !is_lan(t) {
        st.code = "public"; // still try: a VPN / Tailscale address can work, but it is not a home network
    } else {
        match sn {
            Subnet::Same => { st.ok = true; st.code = "same"; }
            Subnet::Different => { st.code = if l4.is_none() { "noRoute" } else { "different" }; }
            Subnet::Unknown => { st.ok = true; st.skipped = true; st.code = "unknownMask"; }
        }
    }
    if let Some(l) = l4 { st.arg = Some(l.to_string()); }
    (st, sn)
}

pub fn beacon_step(b: BeaconSeen) -> DiagStep {
    let (ok, skipped, code, arg) = match b {
        BeaconSeen::Fresh(a) => (true, false, "fresh", Some(a.to_string())),
        BeaconSeen::Stale(a) => (false, false, "stale", Some(a.to_string())),
        // nodes added by IP (Windows rpc-server by hand) never send beacons: not an error by itself
        BeaconSeen::NotSeen => (false, false, "notSeen", None),
        BeaconSeen::ListenerDown => (false, true, "listenerDown", None),
    };
    DiagStep { id: "beacon", ok, skipped, ms: 0, code, arg, detail: String::new() }
}

pub fn tcp_step(t: Tcp, ms: u32, detail: String) -> DiagStep {
    let code = match t { Tcp::Ok => "ok", Tcp::Refused => "refused", Tcp::Timeout => "timeout", Tcp::Unreachable => "unreachable", Tcp::Other => "other" };
    DiagStep { id: "tcp", ok: t == Tcp::Ok, skipped: false, ms, code, arg: None, detail }
}

pub fn hello_step(h: Hello, ms: u32, detail: String, tcp_ok: bool, attached: bool) -> DiagStep {
    let v = |x: (u8, u8, u8)| format!("v{}.{}.{}", x.0, x.1, x.2);
    let (ok, skipped, code, arg) = match h {
        Hello::Ok(x) => (true, false, "ok", Some(v(x))),
        Hello::Mismatch(x) => (false, false, "mismatch", x.map(v)),
        Hello::Busy => (false, false, "busy", None),
        Hello::Garbled => (false, false, "garbled", None),
        Hello::Secured => (true, false, "secured", None),
        Hello::Skipped if attached && tcp_ok => (true, true, "inModel", None),
        Hello::Skipped => (false, true, "skipped", None),
    };
    DiagStep { id: "hello", ok, skipped, ms, code, arg, detail }
}

#[cfg(test)]
mod tests {
    use super::*;
    const M: u8 = 8;
    fn ip(s: &str) -> Ipv4Addr { s.parse().unwrap() }

    #[test]
    fn subnets() {
        assert_eq!(subnet_of(Some(ip("192.168.1.10")), ip("192.168.1.42")), Subnet::Same);
        assert_eq!(subnet_of(Some(ip("192.168.1.10")), ip("192.168.0.42")), Subnet::Unknown);
        assert_eq!(subnet_of(Some(ip("192.168.1.10")), ip("10.0.0.5")), Subnet::Different);
        assert_eq!(subnet_of(None, ip("192.168.1.42")), Subnet::Different);
        assert_eq!(subnet_of(Some(ip("0.0.0.0")), ip("192.168.1.42")), Subnet::Different);
        assert_eq!(subnet_of(Some(ip("127.0.0.1")), ip("127.0.0.1")), Subnet::Same);
        assert!(is_lan(ip("172.20.1.1")) && is_lan(ip("169.254.3.3")) && !is_lan(ip("8.8.8.8")) && !is_lan(ip("100.64.1.1")));
    }

    #[test]
    fn subnet_steps() {
        let (s, sn) = subnet_step("192.168.1.42".parse().unwrap(), Some("192.168.1.10".parse().unwrap()));
        assert!(s.ok && !s.skipped && s.code == "same" && sn == Subnet::Same);
        let (s, _) = subnet_step("192.168.1.42".parse().unwrap(), None);
        assert!(!s.ok && s.code == "noRoute");
        let (s, _) = subnet_step("8.8.8.8".parse().unwrap(), Some("192.168.1.10".parse().unwrap()));
        assert_eq!(s.code, "public");
        let (s, _) = subnet_step("192.168.5.2".parse().unwrap(), Some("192.168.1.10".parse().unwrap()));
        assert!(s.skipped && s.code == "unknownMask");
    }

    #[test]
    fn beacon_age() {
        assert_eq!(BeaconSeen::from_age(Some(3), true), BeaconSeen::Fresh(3));
        assert_eq!(BeaconSeen::from_age(Some(30), true), BeaconSeen::Stale(30));
        assert_eq!(BeaconSeen::from_age(None, true), BeaconSeen::NotSeen);
        assert_eq!(BeaconSeen::from_age(None, false), BeaconSeen::ListenerDown);
        assert_eq!(beacon_step(BeaconSeen::Fresh(2)).arg.as_deref(), Some("2"));
    }

    #[test]
    fn connect_errors() {
        assert_eq!(classify_connect_error(&io::Error::from(io::ErrorKind::ConnectionRefused)), Tcp::Refused);
        assert_eq!(classify_connect_error(&io::Error::from(io::ErrorKind::TimedOut)), Tcp::Timeout);
        assert_eq!(classify_connect_error(&io::Error::from_raw_os_error(113)), Tcp::Unreachable);
        assert_eq!(classify_connect_error(&io::Error::from_raw_os_error(10061)), Tcp::Refused);
        assert_eq!(classify_connect_error(&io::Error::from_raw_os_error(10065)), Tcp::Unreachable);
        assert_eq!(classify_connect_error(&io::Error::other("x")), Tcp::Other);
    }

    /// a real closed port on loopback must read as "refused" (rpc-server not running)
    #[test]
    fn real_refused() {
        let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = l.local_addr().unwrap();
        drop(l);
        let e = std::net::TcpStream::connect_timeout(&addr, std::time::Duration::from_secs(2)).unwrap_err();
        assert_eq!(classify_connect_error(&e), Tcp::Refused);
    }

    #[test]
    fn hello_results() {
        assert_eq!(classify_hello(Ok((8, 0, 0)), M), Hello::Ok((8, 0, 0)));
        assert_eq!(classify_hello(Ok((3, 0, 0)), M), Hello::Mismatch(Some((3, 0, 0))));
        assert_eq!(classify_hello(Err("HELLO timeout".into()), M), Hello::Busy);
        assert_eq!(classify_hello(Err("unexpected RPC reply size 3 (expected 28)".into()), M), Hello::Mismatch(None));
        assert_eq!(classify_hello(Err("early eof".into()), M), Hello::Mismatch(None));
        assert_eq!(classify_hello(Err("weird".into()), M), Hello::Garbled);
    }

    #[test]
    fn verdicts() {
        use BeaconSeen::*;
        let v = |s, b, t, h| verdict(s, b, t, h, M);
        // healthy
        assert_eq!(v(Subnet::Same, Fresh(1), Tcp::Ok, Hello::Ok((8, 0, 0))), Verdict::Ok);
        assert_eq!(v(Subnet::Same, NotSeen, Tcp::Ok, Hello::Skipped), Verdict::Ok);
        // issue #3: beacon arrives, TCP silently dropped by ufw
        assert_eq!(v(Subnet::Same, Fresh(2), Tcp::Timeout, Hello::Skipped), Verdict::FirewallLikely);
        assert_eq!(v(Subnet::Unknown, Fresh(2), Tcp::Timeout, Hello::Skipped), Verdict::FirewallLikely);
        // firewalld REJECT (icmp-host-prohibited) while beacons arrive
        assert_eq!(v(Subnet::Same, Fresh(2), Tcp::Unreachable, Hello::Skipped), Verdict::FirewallLikely);
        // rpc-server crashed / not started
        assert_eq!(v(Subnet::Same, Fresh(2), Tcp::Refused, Hello::Skipped), Verdict::RpcNotRunning);
        assert_eq!(v(Subnet::Same, NotSeen, Tcp::Refused, Hello::Skipped), Verdict::RpcNotRunning);
        // nothing heard, same /24, TCP times out → client isolation on the router
        assert_eq!(v(Subnet::Same, NotSeen, Tcp::Timeout, Hello::Skipped), Verdict::ApIsolationLikely);
        assert_eq!(v(Subnet::Same, Stale(40), Tcp::Timeout, Hello::Skipped), Verdict::ApIsolationLikely);
        // listener down: cannot tell isolation from firewall
        assert_eq!(v(Subnet::Same, ListenerDown, Tcp::Timeout, Hello::Skipped), Verdict::Unknown);
        assert_eq!(v(Subnet::Unknown, NotSeen, Tcp::Timeout, Hello::Skipped), Verdict::Unknown);
        // wrong network
        assert_eq!(v(Subnet::Different, NotSeen, Tcp::Timeout, Hello::Skipped), Verdict::DifferentSubnet);
        assert_eq!(v(Subnet::Different, NotSeen, Tcp::Unreachable, Hello::Skipped), Verdict::DifferentSubnet);
        assert_eq!(v(Subnet::Different, NotSeen, Tcp::Other, Hello::Skipped), Verdict::DifferentSubnet);
        // device off / IP changed
        assert_eq!(v(Subnet::Same, NotSeen, Tcp::Unreachable, Hello::Skipped), Verdict::Unreachable);
        // version / busy / not rpc
        assert_eq!(v(Subnet::Same, Fresh(1), Tcp::Ok, Hello::Mismatch(Some((3, 0, 0)))), Verdict::VersionMismatch);
        assert_eq!(v(Subnet::Same, Fresh(1), Tcp::Ok, Hello::Mismatch(None)), Verdict::VersionMismatch);
        assert_eq!(v(Subnet::Same, Fresh(1), Tcp::Ok, Hello::Ok((7, 1, 0))), Verdict::VersionMismatch);
        assert_eq!(v(Subnet::Same, Fresh(1), Tcp::Ok, Hello::Busy), Verdict::RpcBusy);
        assert_eq!(v(Subnet::Same, Fresh(1), Tcp::Ok, Hello::Secured), Verdict::Ok);
        assert_eq!(classify_hello(Err("secured gateway (PIN mode)".into()), 8), Hello::Secured);
        assert_eq!(v(Subnet::Same, Fresh(1), Tcp::Ok, Hello::Garbled), Verdict::Unknown);
        assert_eq!(v(Subnet::Same, NotSeen, Tcp::Other, Hello::Skipped), Verdict::Unknown);
    }

    #[test]
    fn every_problem_has_hints() {
        for v in [Verdict::FirewallLikely, Verdict::RpcNotRunning, Verdict::DifferentSubnet, Verdict::ApIsolationLikely,
                  Verdict::VersionMismatch, Verdict::RpcBusy, Verdict::Unreachable, Verdict::Unknown] {
            assert!(!hints(v).is_empty(), "{v:?}");
        }
        assert!(hints(Verdict::Ok).is_empty());
        assert_eq!(hints(Verdict::FirewallLikely)[0], "linuxScript");
    }

    #[test]
    fn steps_serialize_flags() {
        let s = hello_step(Hello::Skipped, 0, String::new(), true, true);
        assert!(s.ok && s.skipped && s.code == "inModel");
        let s = hello_step(Hello::Skipped, 0, String::new(), false, false);
        assert!(!s.ok && s.skipped && s.code == "skipped");
        assert_eq!(hello_step(Hello::Mismatch(Some((3, 1, 2))), 5, String::new(), true, false).arg.as_deref(), Some("v3.1.2"));
        assert_eq!(tcp_step(Tcp::Refused, 3, String::new()).code, "refused");
    }
}

// ==== tauri command (everything below needs the app crate) ====

use crate::state::AppState;
use std::{sync::Arc, time::{Duration, Instant}};
use tauri::State;

fn ms(t: Instant) -> u32 { t.elapsed().as_millis().min(u32::MAX as u128) as u32 }

/// «Проверить связь»: why can't the PC reach `ip:port`? Never fails for a reachable/unreachable node —
/// only for an address that is not an IP at all.
#[tauri::command]
pub async fn diagnose_node(state: State<'_, Arc<AppState>>, ip: String, port: u16) -> Result<DiagReport, String> {
    let st = state.inner().clone();
    let t_all = Instant::now();
    let raw = ip.trim().trim_start_matches('[').trim_end_matches(']').to_string();
    let addr: IpAddr = raw.parse().map_err(|_| format!("«{raw}» — не IP-адрес"))?;
    let addr = match addr { IpAddr::V6(v6) => v6.to_ipv4_mapped().map(IpAddr::V4).unwrap_or(addr), x => x };
    let port = if port == 0 { crate::beacon::DEFAULT_PORT } else { port };
    let ep = std::net::SocketAddr::new(addr, port);
    let ep_s = match addr { IpAddr::V6(_) => format!("[{addr}]:{port}"), _ => format!("{addr}:{port}") };
    let mut steps = vec![];

    // 1. subnet: which PC interface the OS would use (UDP connect sends nothing)
    let t = Instant::now();
    let local = std::net::UdpSocket::bind(if addr.is_ipv4() { "0.0.0.0:0" } else { "[::]:0" }).ok()
        .and_then(|s| s.connect(ep).ok().and_then(|_| s.local_addr().ok())).map(|a| a.ip());
    let (mut s1, subnet) = subnet_step(addr, local);
    s1.ms = ms(t);
    steps.push(s1);

    // 2. beacon from that IP (any port) in the lan.rs listener state
    let age = st.discovered.lock().await.values().filter(|d| d.host == addr.to_string())
        .map(|d| d.last_seen.elapsed().as_secs()).min();
    let listener_ok = st.beacon_error.lock().await.is_empty();
    let beacon = BeaconSeen::from_age(age, listener_ok);
    steps.push(beacon_step(beacon));

    // 3. TCP connect
    let t = Instant::now();
    let tcp = match tokio::time::timeout(Duration::from_millis(TCP_TIMEOUT_MS), tokio::net::TcpStream::connect(ep)).await {
        Ok(Ok(s)) => { drop(s); (Tcp::Ok, String::new()) }
        Ok(Err(e)) => (classify_connect_error(&e), e.to_string()),
        Err(_) => (Tcp::Timeout, format!("no answer in {} s", TCP_TIMEOUT_MS / 1000)),
    };
    steps.push(tcp_step(tcp.0, ms(t), tcp.1));

    // 4. HELLO — skipped when the running model holds the node (rpc-server serves one client)
    let attached = crate::llama::engine_endpoints(&st).await.contains(&ep_s);
    let t = Instant::now();
    let (hello, hdetail) = if tcp.0 != Tcp::Ok || attached {
        (Hello::Skipped, String::new())
    } else {
        // let rpc-server notice our probe connection closed before it accepts the next one
        tokio::time::sleep(Duration::from_millis(100)).await;
        let r = crate::lan::rpc_hello(&ep_s, Duration::from_millis(HELLO_TIMEOUT_MS)).await.map_err(|e| format!("{e:#}"));
        let d = r.as_ref().err().cloned().unwrap_or_default();
        (classify_hello(r, crate::lan::RPC_PROTO_MAJOR), d)
    };
    steps.push(hello_step(hello, if hello == Hello::Skipped { 0 } else { ms(t) }, hdetail, tcp.0 == Tcp::Ok, attached));

    let v = verdict(subnet, beacon, tcp.0, hello, crate::lan::RPC_PROTO_MAJOR);
    log::info!("netdiag {ep_s}: {v:?} (subnet {subnet:?}, beacon {beacon:?}, tcp {:?}, hello {hello:?})", tcp.0);
    Ok(DiagReport {
        ip: addr.to_string(), port, local_ip: local.map(|l| l.to_string()), steps, verdict: v, hints: hints(v), total_ms: ms(t_all),
    })
}
