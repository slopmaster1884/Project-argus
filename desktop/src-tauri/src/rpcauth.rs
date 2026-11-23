//! Opt-in secured RPC («защищённый режим», docs/SECURITY.md).
//!
//! A secured node runs ggml rpc-server on 127.0.0.1:50072 and an auth gateway on 0.0.0.0:50052
//! (Argus Node app, scripts/argus-node-linux.sh with ARGUS_SECURE=1). Its beacon carries `"auth":1`.
//! llama-server knows nothing about this: for every secured node Argus runs a local forwarder on
//! 127.0.0.1:<ephemeral> that connects to the node, does the handshake with the stored token and then
//! pipes raw bytes. `--rpc` gets the forwarder address for secured nodes and the node itself for legacy ones.
//!
//! Wire protocol (all lines ASCII, `\n`-terminated, binary values lowercase hex):
//! ```text
//! S→C  ARGUS1 <nonce:16 bytes>                    sent by the gateway right after accept
//! auth:
//! C→S  AUTH <mac>        mac  = HMAC-SHA256(token, "argus-auth|" ‖ nonce)
//! S→C  OK <smac>         smac = HMAC-SHA256(token, "argus-srv|" ‖ nonce ‖ mac)   → raw rpc bytes both ways
//!      ERR auth          (connection closed)
//! pairing (SPAKE2 over the RFC 3526 2048-bit MODP group, w from the 6-digit PIN):
//! C→S  PAIR <X>          X = g^x · M^w            (256-byte big-endian)
//! S→C  PAIRB <Y>         Y = g^y · N^w
//! C→S  PAIRC <c>         k = SHA256("argus-spake2|" ‖ nonce ‖ X ‖ Y ‖ Z ‖ w(32 B)), c = HMAC(k, "c")
//! S→C  PAIROK <enc> <s>  enc = token ⊕ HMAC(k, "k"),  s = HMAC(k, "s" ‖ enc)
//!      ERR pin           (wrong PIN; the node makes a new PIN after 5 failures)
//! ```
//! Clients from 127.0.0.1 skip the handshake (adb forward of a USB-connected phone; the internal port is
//! on loopback anyway). Kept free of tauri so it can be unit-/end-to-end-tested anywhere.
use anyhow::{anyhow, bail, Context, Result};
use num_bigint::BigUint;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::time::timeout;

pub const MAGIC: &str = "ARGUS1";
pub const TOKEN_LEN: usize = 32;
pub type Token = [u8; TOKEN_LEN];
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(5);
const MAX_LINE: usize = 1200;

// ---------------------------------------------------------------- crypto (pure)

pub fn hmac(key: &[u8], parts: &[&[u8]]) -> [u8; 32] {
    let mut k = [0u8; 64];
    if key.len() > 64 { k[..32].copy_from_slice(&Sha256::digest(key)); } else { k[..key.len()].copy_from_slice(key); }
    let mut inner = Sha256::new();
    inner.update(k.iter().map(|b| b ^ 0x36).collect::<Vec<u8>>());
    for p in parts { inner.update(p); }
    let ih = inner.finalize();
    let mut outer = Sha256::new();
    outer.update(k.iter().map(|b| b ^ 0x5c).collect::<Vec<u8>>());
    outer.update(ih);
    outer.finalize().into()
}

fn ct_eq(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

pub fn hex(b: &[u8]) -> String { b.iter().map(|x| format!("{x:02x}")).collect() }
pub fn unhex(s: &str) -> Result<Vec<u8>> {
    let s = s.trim();
    if s.len() % 2 != 0 || !s.bytes().all(|c| c.is_ascii_hexdigit()) { bail!("bad hex"); }
    (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).map_err(|e| anyhow!(e))).collect()
}
pub fn token_from_hex(s: &str) -> Option<Token> { unhex(s).ok()?.try_into().ok() }

pub fn random_bytes<const N: usize>() -> [u8; N] {
    let mut b = [0u8; N];
    getrandom::getrandom(&mut b).expect("OS random generator");
    b
}

pub fn auth_mac(token: &Token, nonce: &[u8]) -> [u8; 32] { hmac(token, &[b"argus-auth|", nonce]) }
pub fn server_mac(token: &Token, nonce: &[u8], mac: &[u8]) -> [u8; 32] { hmac(token, &[b"argus-srv|", nonce, mac]) }

/// RFC 3526 group 14 (2048-bit MODP), g = 2. p is a safe prime: q = (p-1)/2.
const MODP_2048: &str = "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3BE39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497CEA956AE515D2261898FA051015728E5A8AACAA68FFFFFFFFFFFFFFFF";

struct Group { p: BigUint, q: BigUint, g: BigUint, m: BigUint, n: BigUint }
fn group() -> &'static Group {
    static G: OnceLock<Group> = OnceLock::new();
    G.get_or_init(|| {
        let p = BigUint::parse_bytes(MODP_2048.as_bytes(), 16).unwrap();
        let q = (&p - 1u32) >> 1;
        // M, N: squares of public hashes → in the order-q subgroup, discrete log unknown to everybody
        let sq = |label: &[u8]| { let h = BigUint::from_bytes_be(&Sha256::digest(label)); (&h * &h) % &p };
        Group { m: sq(b"argus-spake2-M"), n: sq(b"argus-spake2-N"), g: BigUint::from(2u32), q, p }
    })
}

/// 256-byte big-endian encoding of a group element.
pub fn elem_bytes(x: &BigUint) -> Vec<u8> {
    let b = x.to_bytes_be();
    let mut v = vec![0u8; 256usize.saturating_sub(b.len())];
    v.extend_from_slice(&b);
    v
}

fn pin_scalar(pin: &str) -> BigUint {
    BigUint::from_bytes_be(&hmac(b"argus-pin", &[pin.as_bytes()])) % &group().q
}

fn valid_elem(x: &BigUint) -> bool {
    let g = group();
    *x > BigUint::from(1u32) && *x < &g.p - 1u32 && x.modpow(&g.q, &g.p) == BigUint::from(1u32)
}

fn inv(x: &BigUint) -> BigUint { let g = group(); x.modpow(&(&g.p - 2u32), &g.p) }

fn session_key(nonce: &[u8], x: &BigUint, y: &BigUint, z: &BigUint, w: &BigUint) -> [u8; 32] {
    let mut wb = w.to_bytes_be();
    while wb.len() < 32 { wb.insert(0, 0); }
    let mut h = Sha256::new();
    h.update(b"argus-spake2|"); h.update(nonce);
    h.update(elem_bytes(x)); h.update(elem_bytes(y)); h.update(elem_bytes(z)); h.update(&wb);
    h.finalize().into()
}

/// Accepts exactly 6 ASCII digits (spaces and dashes ignored: "123 456", "123-456").
pub fn normalize_pin(pin: &str) -> Result<String> {
    let p: String = pin.chars().filter(|c| !c.is_whitespace() && *c != '-').collect();
    if p.len() != 6 || !p.bytes().all(|c| c.is_ascii_digit()) { bail!("PIN — это 6 цифр с экрана ноды"); }
    Ok(p)
}

/// One side of the SPAKE2 exchange. `client` = Argus host (uses M), server = node (uses N).
pub struct Pake { client: bool, w: BigUint, e: BigUint, pub public: BigUint }
impl Pake {
    pub fn new(pin: &str, client: bool) -> Self {
        let g = group();
        let w = pin_scalar(pin);
        let e = BigUint::from_bytes_be(&random_bytes::<32>()) % &g.q;
        let blind = if client { &g.m } else { &g.n };
        let public = (g.g.modpow(&e, &g.p) * blind.modpow(&w, &g.p)) % &g.p;
        Self { client, w, e, public }
    }
    /// Session key from the peer's public value (client: X = ours, Y = peer; server: the other way round).
    pub fn finish(&self, nonce: &[u8], peer: &BigUint) -> Result<[u8; 32]> {
        if !valid_elem(peer) { bail!("неверное значение от другой стороны"); }
        let g = group();
        let peer_blind = if self.client { &g.n } else { &g.m };
        let base = (peer * inv(&peer_blind.modpow(&self.w, &g.p))) % &g.p;
        let z = base.modpow(&self.e, &g.p);
        let (x, y) = if self.client { (&self.public, peer) } else { (peer, &self.public) };
        Ok(session_key(nonce, x, y, &z, &self.w))
    }
}

pub fn pair_confirm(k: &[u8; 32]) -> [u8; 32] { hmac(k, &[b"c"]) }
#[allow(dead_code)] // node side of the pairing: the nodes implement it (python/Kotlin); used by the tests
pub fn pair_seal(k: &[u8; 32], token: &Token) -> ([u8; 32], [u8; 32]) {
    let pad = hmac(k, &[b"k"]);
    let mut enc = [0u8; 32];
    for i in 0..32 { enc[i] = token[i] ^ pad[i]; }
    (enc, hmac(k, &[b"s", &enc]))
}
pub fn pair_open(k: &[u8; 32], enc: &[u8], tag: &[u8]) -> Result<Token> {
    if enc.len() != 32 || !ct_eq(&hmac(k, &[b"s", enc]), tag) { bail!("нода не подтвердила PIN (подмена?)"); }
    let pad = hmac(k, &[b"k"]);
    let mut t = [0u8; 32];
    for i in 0..32 { t[i] = enc[i] ^ pad[i]; }
    Ok(t)
}

// ---------------------------------------------------------------- client I/O

async fn read_line(s: &mut TcpStream) -> Result<String> {
    let mut v = Vec::with_capacity(80);
    let mut b = [0u8; 1];
    loop {
        if s.read(&mut b).await? == 0 { bail!("нода закрыла соединение"); }
        if b[0] == b'\n' { break; }
        v.push(b[0]);
        if v.len() > MAX_LINE { bail!("слишком длинная строка рукопожатия"); }
    }
    String::from_utf8(v).map_err(|_| anyhow!("не ASCII в рукопожатии")).map(|s| s.trim_end_matches('\r').to_string())
}

async fn greeting(s: &mut TcpStream) -> Result<Vec<u8>> {
    let line = timeout(Duration::from_millis(2000), read_line(s)).await
        .map_err(|_| anyhow!("нода не прислала приветствие защищённого режима (ARGUS1) — на ноде выключена защита? Удалите ноду и добавьте заново"))??;
    let nonce = line.strip_prefix(MAGIC).map(str::trim).ok_or_else(|| anyhow!("неожиданное приветствие ноды"))?;
    let n = unhex(nonce)?;
    if n.len() != 16 { bail!("неверный nonce"); }
    Ok(n)
}

/// After connect: the auth handshake; on Ok the stream carries raw rpc bytes.
pub async fn handshake(s: &mut TcpStream, token: &Token) -> Result<()> {
    timeout(HANDSHAKE_TIMEOUT, async {
        let nonce = greeting(s).await?;
        let mac = auth_mac(token, &nonce);
        s.write_all(format!("AUTH {}\n", hex(&mac)).as_bytes()).await?;
        let r = read_line(s).await?;
        let smac = r.strip_prefix("OK ").ok_or_else(|| anyhow!("нода отклонила ключ — сопрягите её заново (PIN)"))?;
        if !ct_eq(&unhex(smac)?, &server_mac(token, &nonce, &mac)) { bail!("нода не подтвердила ключ (подмена?)"); }
        Ok(())
    }).await.map_err(|_| anyhow!("таймаут рукопожатия"))?
}

pub async fn connect_authed(endpoint: &str, token: &Token) -> Result<TcpStream> {
    let mut s = timeout(Duration::from_millis(1500), TcpStream::connect(endpoint)).await
        .map_err(|_| anyhow!("таймаут подключения"))??;
    s.set_nodelay(true).ok();
    handshake(&mut s, token).await?;
    Ok(s)
}

/// Does this endpoint talk the secured protocol? (a plain rpc-server stays silent until the client speaks)
pub async fn is_secured(endpoint: &str) -> bool {
    let Ok(Ok(mut s)) = timeout(Duration::from_millis(1500), TcpStream::connect(endpoint)).await else { return false };
    let mut b = [0u8; 6];
    matches!(timeout(Duration::from_millis(800), s.read_exact(&mut b)).await, Ok(Ok(_))) && &b == MAGIC.as_bytes()
}

/// Pairing with the PIN shown on the node: returns the node's token.
pub async fn pair(endpoint: &str, pin: &str) -> Result<Token> {
    let pin = normalize_pin(pin)?;
    let mut s = timeout(Duration::from_millis(2000), TcpStream::connect(endpoint)).await
        .map_err(|_| anyhow!("таймаут подключения к {endpoint}"))?.with_context(|| format!("подключение к {endpoint}"))?;
    timeout(Duration::from_secs(15), async {
        let nonce = greeting(&mut s).await?;
        let me = tokio::task::spawn_blocking(move || Pake::new(&pin, true)).await?;
        s.write_all(format!("PAIR {}\n", hex(&elem_bytes(&me.public))).as_bytes()).await?;
        let r = read_line(&mut s).await?;
        if r.starts_with("ERR") { bail!("нода отказала в сопряжении: {r}"); }
        let y = BigUint::from_bytes_be(&unhex(r.strip_prefix("PAIRB ").ok_or_else(|| anyhow!("неожиданный ответ ноды"))?)?);
        let k = tokio::task::spawn_blocking(move || me.finish(&nonce, &y)).await??;
        s.write_all(format!("PAIRC {}\n", hex(&pair_confirm(&k))).as_bytes()).await?;
        let r = read_line(&mut s).await?;
        if r.starts_with("ERR") { bail!("неверный PIN"); }
        let mut it = r.strip_prefix("PAIROK ").ok_or_else(|| anyhow!("неожиданный ответ ноды"))?.split_whitespace();
        let (enc, tag) = (unhex(it.next().unwrap_or(""))?, unhex(it.next().unwrap_or(""))?);
        pair_open(&k, &enc, &tag)
    }).await.map_err(|_| anyhow!("таймаут сопряжения"))?
}

// ---------------------------------------------------------------- forwarders (host side)

struct Fwd { local: String, token: Arc<Mutex<Token>> }
fn forwarders() -> &'static Mutex<HashMap<String, Fwd>> {
    static F: OnceLock<Mutex<HashMap<String, Fwd>>> = OnceLock::new();
    F.get_or_init(Default::default)
}

/// 127.0.0.1:<port> that llama-server should use instead of `endpoint`. One listener per node for the app
/// lifetime (the address must not change while an engine uses it); every accepted connection gets its own
/// authenticated connection to the node.
pub async fn forwarder(endpoint: &str, token: &Token) -> Result<String> {
    if let Some(f) = forwarders().lock().unwrap_or_else(|e| e.into_inner()).get(endpoint) {
        *f.token.lock().unwrap_or_else(|e| e.into_inner()) = *token;
        return Ok(f.local.clone());
    }
    let l = TcpListener::bind(("127.0.0.1", 0)).await?;
    let local = l.local_addr()?.to_string();
    let tok = Arc::new(Mutex::new(*token));
    {
        let mut m = forwarders().lock().unwrap_or_else(|e| e.into_inner());
        if let Some(f) = m.get(endpoint) { return Ok(f.local.clone()); } // lost a race: drop ours
        m.insert(endpoint.to_string(), Fwd { local: local.clone(), token: tok.clone() });
    }
    let ep = endpoint.to_string();
    log::info!("rpcauth: forwarder {local} -> {ep}");
    tokio::spawn(async move {
        loop {
            let (mut inb, _) = match l.accept().await { Ok(x) => x, Err(e) => { log::warn!("rpcauth accept: {e}"); tokio::time::sleep(Duration::from_millis(200)).await; continue } };
            let (ep, t) = (ep.clone(), *tok.lock().unwrap_or_else(|e| e.into_inner()));
            tokio::spawn(async move {
                inb.set_nodelay(true).ok();
                match connect_authed(&ep, &t).await {
                    Ok(mut out) => { let _ = tokio::io::copy_bidirectional(&mut inb, &mut out).await; }
                    Err(e) => log::warn!("rpcauth {ep}: {e:#}"),
                }
            });
        }
    });
    Ok(local)
}

/// Node endpoint behind a forwarder address (adopting a running engine's `--rpc` list).
pub fn real_endpoint(local: &str) -> Option<String> {
    forwarders().lock().unwrap_or_else(|e| e.into_inner()).iter().find(|(_, f)| f.local == local).map(|(k, _)| k.clone())
}

pub fn any_forwarder() -> bool { !forwarders().lock().unwrap_or_else(|e| e.into_inner()).is_empty() }

// ---------------------------------------------------------------- tests

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hmac_rfc4231() {
        // RFC 4231 test case 2
        assert_eq!(hex(&hmac(b"Jefe", &[b"what do ya want ", b"for nothing?"])),
                   "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843");
    }

    #[test]
    fn pake_agrees_only_with_same_pin() {
        let nonce = [7u8; 16];
        let c = Pake::new("123456", true);
        let s = Pake::new("123456", false);
        let kc = c.finish(&nonce, &s.public).unwrap();
        let ks = s.finish(&nonce, &c.public).unwrap();
        assert_eq!(kc, ks);
        let token: Token = random_bytes();
        let (enc, tag) = pair_seal(&ks, &token);
        assert_eq!(pair_open(&kc, &enc, &tag).unwrap(), token);
        let bad = Pake::new("123457", false);
        let kb = bad.finish(&nonce, &c.public).unwrap();
        let kc2 = c.finish(&nonce, &bad.public).unwrap();
        assert_ne!(kb, kc2);
        assert!(!valid_elem(&BigUint::from(1u32)));
        assert!(c.finish(&nonce, &BigUint::from(1u32)).is_err());
    }

    #[test]
    fn pins_and_hex() {
        assert_eq!(normalize_pin(" 123-456 ").unwrap(), "123456");
        assert!(normalize_pin("12345").is_err());
        assert!(normalize_pin("12345a").is_err());
        let t: Token = random_bytes();
        assert_eq!(token_from_hex(&hex(&t)), Some(t));
        assert!(token_from_hex("zz").is_none());
    }
}
