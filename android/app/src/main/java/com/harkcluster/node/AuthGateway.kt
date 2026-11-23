package com.harkcluster.node

import android.content.Context
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.math.BigInteger
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlin.concurrent.thread

/**
 * Secured RPC gateway («Защищённый режим», docs/SECURITY.md). Same protocol as desktop/src-tauri/src/rpcauth.rs
 * and the python gateway in scripts/argus-node-linux.sh:
 *
 *   S→C  ARGUS1 <nonce 16 B hex>
 *   C→S  AUTH <HMAC(token, "argus-auth|"‖nonce)>          → S→C OK <HMAC(token, "argus-srv|"‖nonce‖mac)>, then raw bytes
 *   C→S  PAIR <X> / S→C PAIRB <Y> / C→S PAIRC <c> / S→C PAIROK <enc> <s>   (SPAKE2, RFC 3526 2048-bit MODP, PIN)
 *
 * rpc-server listens on 127.0.0.1:[RpcService.INTERNAL_PORT]; this gateway owns 0.0.0.0:50052. Loopback clients
 * (the PC's adb forward when the phone is also on USB) are piped without a handshake: the internal port is
 * reachable from the phone itself anyway.
 *
 * NOTE: written to mirror the tested python/Rust implementations; not yet run on a device (no Android toolchain
 * in the dev sandbox) — see docs/SECURITY.md «Что не проверено».
 */
object AuthGateway {
    private const val MAX_FAILS = 5
    private val P = BigInteger(
        "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3BE39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497CEA956AE515D2261898FA051015728E5A8AACAA68FFFFFFFFFFFFFFFF", 16)
    private val Q = P.subtract(BigInteger.ONE).shiftRight(1)
    private val G = BigInteger.valueOf(2)
    private val M = square(sha256("argus-spake2-M".toByteArray()))
    private val N = square(sha256("argus-spake2-N".toByteArray()))
    private val rnd = SecureRandom()

    @Volatile var pin: String? = null; private set     // shown in MainActivity while the gateway runs
    @Volatile var running = false; private set
    @Volatile var paired = 0; private set              // successful pairings since start
    @Volatile var rejected = 0; private set            // connections refused (bad key / bad PIN)
    private var fails = 0
    @Volatile private var gen = 0                      // start/stop generation: a stale accept loop exits
    private var server: ServerSocket? = null
    private var token: ByteArray = ByteArray(0)

    private fun square(h: ByteArray): BigInteger { val x = BigInteger(1, h); return x.multiply(x).mod(P) }
    private fun sha256(vararg parts: ByteArray): ByteArray =
        MessageDigest.getInstance("SHA-256").apply { parts.forEach { update(it) } }.digest()
    private fun hmac(key: ByteArray, vararg parts: ByteArray): ByteArray =
        Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(key, "HmacSHA256")); parts.forEach { update(it) } }.doFinal()
    private fun hex(b: ByteArray) = b.joinToString("") { "%02x".format(it.toInt() and 0xff) }
    private fun unhex(s: String): ByteArray? {
        val t = s.trim(); if (t.length % 2 != 0 || t.any { Character.digit(it, 16) < 0 }) return null
        return ByteArray(t.length / 2) { ((Character.digit(t[2 * it], 16) shl 4) or Character.digit(t[2 * it + 1], 16)).toByte() }
    }
    /** 256-byte big-endian */
    private fun eb(x: BigInteger): ByteArray {
        val b = x.toByteArray().let { if (it.size > 256) it.copyOfRange(it.size - 256, it.size) else it }
        return ByteArray(256 - b.size) + b
    }
    private fun be32(x: BigInteger): ByteArray {
        val b = x.toByteArray().let { if (it.size > 32) it.copyOfRange(it.size - 32, it.size) else it }
        return ByteArray(32 - b.size) + b
    }

    fun tokenFile(ctx: Context) = File(ctx.filesDir, "rpc_token")

    /** Node token (32 random bytes, hex in filesDir/rpc_token), created on first use. */
    fun loadToken(ctx: Context): ByteArray {
        val f = tokenFile(ctx)
        runCatching { unhex(f.readText())?.takeIf { it.size == 32 } }.getOrNull()?.let { return it }
        val t = ByteArray(32).also { rnd.nextBytes(it) }
        f.writeText(hex(t) + "\n")
        RpcService.addLog("secure: new node token")
        return t
    }

    /** «Сбросить ключ»: every PC has to pair again with a new PIN. */
    fun resetToken(ctx: Context) { tokenFile(ctx).delete(); token = loadToken(ctx); synchronized(this) { newPin() } }

    private fun newPin() {
        pin = "%06d".format(rnd.nextInt(1_000_000)); fails = 0
        RpcService.addLog("secure: PIN for pairing ${pin!!.substring(0, 3)} ${pin!!.substring(3)}")
    }

    @Synchronized fun start(ctx: Context, port: Int, upstreamPort: Int) {
        if (running) return
        token = loadToken(ctx)
        running = true; newPin()
        val my = ++gen
        fun live() = running && gen == my
        thread(name = "argus-auth-gw", isDaemon = true) {
            // on a switch from plain Wi-Fi mode the old rpc-server still holds :port for a moment → retry
            var ss: ServerSocket? = null
            for (i in 0 until 40) {
                if (!live()) return@thread
                ss = runCatching { ServerSocket().apply { reuseAddress = true; bind(InetSocketAddress("0.0.0.0", port)) } }
                    .onFailure { if (i == 39) RpcService.addLog("secure: cannot bind :$port — ${it.message}") }.getOrNull()
                if (ss != null) break
                Thread.sleep(500)
            }
            if (ss == null) { synchronized(this) { if (gen == my) { running = false; pin = null } }; return@thread }
            synchronized(this) { if (!live()) { runCatching { ss.close() }; return@thread }; server = ss }
            RpcService.addLog("secure: gateway 0.0.0.0:$port → rpc-server 127.0.0.1:$upstreamPort")
            while (live()) {
                val c = try { ss.accept() } catch (_: Exception) { if (live()) { Thread.sleep(200); continue } else break }
                thread(name = "argus-auth-conn", isDaemon = true) { handle(c, upstreamPort) }
            }
        }
    }

    @Synchronized fun stop() {
        running = false; pin = null; gen++
        runCatching { server?.close() }; server = null
    }

    private fun readLine(inp: InputStream): String {
        val sb = StringBuilder()
        while (true) {
            val b = inp.read(); if (b < 0) throw java.io.EOFException()
            if (b == '\n'.code) break
            if (sb.isEmpty() && b != 'A'.code && b != 'P'.code) throw IllegalStateException("not an Argus client")
            sb.append(b.toChar()); if (sb.length > 1200) throw IllegalStateException("line too long")
        }
        return sb.toString().trim()
    }

    private fun handle(c: Socket, upstreamPort: Int) {
        try {
            c.tcpNoDelay = true
            val inp = c.getInputStream(); val out = c.getOutputStream()
            if (c.inetAddress.isLoopbackAddress) { bridge(c, upstreamPort); return }
            c.soTimeout = 10_000
            val nonce = ByteArray(16).also { rnd.nextBytes(it) }
            out.write("ARGUS1 ${hex(nonce)}\n".toByteArray()); out.flush()
            val line = readLine(inp)
            when {
                line.startsWith("AUTH ") -> {
                    val got = unhex(line.substring(5)) ?: ByteArray(0)
                    if (!MessageDigest.isEqual(got, hmac(token, "argus-auth|".toByteArray(), nonce))) {
                        rejected++; RpcService.addLog("secure: rejected ${c.inetAddress.hostAddress} (wrong key)")
                        Thread.sleep(500); out.write("ERR auth\n".toByteArray()); out.flush(); return
                    }
                    out.write("OK ${hex(hmac(token, "argus-srv|".toByteArray(), nonce, got))}\n".toByteArray()); out.flush()
                    c.soTimeout = 0
                    bridge(c, upstreamPort)
                }
                line.startsWith("PAIR ") -> pair(c, inp, out, nonce, line.substring(5))
                else -> { out.write("ERR proto\n".toByteArray()); out.flush() }
            }
        } catch (_: Exception) {
        } finally { runCatching { c.close() } }
    }

    private fun pair(c: Socket, inp: InputStream, out: OutputStream, nonce: ByteArray, xHex: String) {
        val x = unhex(xHex)?.let { BigInteger(1, it) }
        if (x == null || x <= BigInteger.ONE || x >= P.subtract(BigInteger.ONE) || x.modPow(Q, P) != BigInteger.ONE) {
            out.write("ERR bad\n".toByteArray()); out.flush(); return
        }
        val pinNow = synchronized(this) { pin ?: run { newPin(); pin!! } }
        val w = BigInteger(1, hmac("argus-pin".toByteArray(), pinNow.toByteArray())).mod(Q)
        val y = BigInteger(Q.bitLength() + 64, rnd).mod(Q)
        val bigY = G.modPow(y, P).multiply(N.modPow(w, P)).mod(P)
        out.write("PAIRB ${hex(eb(bigY))}\n".toByteArray()); out.flush()
        val line = readLine(inp)
        val z = x.multiply(M.modPow(w, P).modInverse(P)).mod(P).modPow(y, P)
        val k = sha256("argus-spake2|".toByteArray(), nonce, eb(x), eb(bigY), eb(z), be32(w))
        val got = if (line.startsWith("PAIRC ")) unhex(line.substring(6)) else null
        if (got == null || !MessageDigest.isEqual(got, hmac(k, "c".toByteArray()))) {
            rejected++
            synchronized(this) {
                fails++; RpcService.addLog("secure: wrong PIN ($fails/$MAX_FAILS)")
                if (fails >= MAX_FAILS) { RpcService.addLog("secure: too many attempts — new PIN"); newPin() }
            }
            Thread.sleep(1000); out.write("ERR pin\n".toByteArray()); out.flush(); return
        }
        val pad = hmac(k, "k".toByteArray())
        val enc = ByteArray(32) { (token[it].toInt() xor pad[it].toInt()).toByte() }
        out.write("PAIROK ${hex(enc)} ${hex(hmac(k, "s".toByteArray(), enc))}\n".toByteArray()); out.flush()
        synchronized(this) { fails = 0 }
        paired++; RpcService.addLog("secure: paired with ${c.inetAddress.hostAddress}")
    }

    private fun pump(src: Socket, dst: Socket) {
        val buf = ByteArray(65536)
        try {
            val i = src.getInputStream(); val o = dst.getOutputStream()
            while (true) { val n = i.read(buf); if (n < 0) break; o.write(buf, 0, n) }
        } catch (_: Exception) {}
        runCatching { dst.shutdownOutput() }
    }

    private fun bridge(c: Socket, upstreamPort: Int) {
        val up = Socket()
        try {
            up.connect(InetSocketAddress(InetAddress.getLoopbackAddress(), upstreamPort), 5000)
            up.tcpNoDelay = true
            val t = thread(name = "argus-auth-pump", isDaemon = true) { pump(up, c) }
            pump(c, up); t.join()
        } finally { runCatching { up.close() } }
    }
}
