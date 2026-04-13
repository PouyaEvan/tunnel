import socket
import threading
import struct
import sys
import argparse
import time
import random
import hashlib

# --- Stats Collection ---
class Stats:
    def __init__(self):
        self.bytes_sent = 0
        self.bytes_recv = 0
        self.active_conns = 0
        self.total_conns = 0
        self.start_time = time.time()
        self.lock = threading.Lock()

    def add_sent(self, n):
        with self.lock: self.bytes_sent += n
    def add_recv(self, n):
        with self.lock: self.bytes_recv += n
    def conn_up(self):
        with self.lock: 
            self.active_conns += 1
            self.total_conns += 1
    def conn_down(self):
        with self.lock: self.active_conns -= 1

    def display(self):
        while True:
            time.sleep(1)
            elapsed = time.time() - self.start_time
            with self.lock:
                sent_mb = self.bytes_sent / (1024 * 1024)
                recv_mb = self.bytes_recv / (1024 * 1024)
                print(f"\r[*] [STATS] Active: {self.active_conns} | Total: {self.total_conns} | Sent: {sent_mb:.2f} MB | Recv: {recv_mb:.2f} MB | Uptime: {int(elapsed)}s", end="")

stats = Stats()

# --- Obfuscation Logic ---
class Obfuscator:
    def __init__(self, key=None):
        self.key = hashlib.sha256(key.encode()).digest() if key else None
        self.key_ptr = 0

    def transform(self, data):
        if not data or not self.key: return data
        data = bytearray(data)
        for i in range(len(data)):
            data[i] ^= self.key[self.key_ptr]
            self.key_ptr = (self.key_ptr + 1) % len(self.key)
        return bytes(data)

def update_tls_lengths(data):
    try:
        if len(data) < 9: return data
        record_len = len(data) - 5
        data = data[:3] + struct.pack('!H', record_len) + data[5:]
        handshake_len = len(data) - 9
        data = data[:6] + struct.pack('!I', handshake_len)[1:] + data[9:]
        return data
    except: return data

def spoof_sni(data, fake_sni):
    if len(data) < 10 or data[0] != 0x16 or data[5] != 0x01: return data
    try:
        sni_idx = data.find(b'\x00\x00', 43)
        if sni_idx == -1: return data
        old_ext_len = struct.unpack('!H', data[sni_idx+2:sni_idx+4])[0]
        new_name = fake_sni.encode()
        new_name_len = len(new_name)
        new_ext = b'\x00\x00' + struct.pack('!H', new_name_len + 5) + struct.pack('!H', new_name_len + 3) + b'\x00' + struct.pack('!H', new_name_len) + new_name
        modified = data[:sni_idx] + new_ext + data[sni_idx + 4 + old_ext_len:]
        return update_tls_lengths(modified)
    except: return data

def forward(src, dst, fake_sni, do_spoof=False, obfs_sender=None, obfs_receiver=None):
    try:
        first_packet = True
        while True:
            data = src.recv(32768)
            if not data: break
            
            if obfs_receiver: data = obfs_receiver.transform(data)
            if first_packet and do_spoof:
                data = spoof_sni(data, fake_sni)
                first_packet = False
            if obfs_sender: data = obfs_sender.transform(data)

            dst.sendall(data)
            if do_spoof: stats.add_sent(len(data))
            else: stats.add_recv(len(data))
    except: pass
    finally:
        try: src.close()
        except: pass
        try: dst.close()
        except: pass

def handle_tcp_client(client_socket, remote_ip, remote_port, current_sni_func, do_spoof, psk, obfs_key):
    stats.conn_up()
    try:
        remote_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        remote_socket.settimeout(10)
        remote_socket.connect((remote_ip, remote_port))
        
        if psk:
            if do_spoof: remote_socket.sendall(hashlib.sha256(psk.encode()).digest())
            else:
                received_hash = client_socket.recv(32)
                if received_hash != hashlib.sha256(psk.encode()).digest():
                    client_socket.close(); remote_socket.close(); return
        
        sni_to_use = current_sni_func()
        obfs_out = Obfuscator(obfs_key) if obfs_key else None
        obfs_in = Obfuscator(obfs_key) if obfs_key else None

        if do_spoof:
            threading.Thread(target=forward, args=(client_socket, remote_socket, sni_to_use, True, obfs_out, None)).start()
            threading.Thread(target=forward, args=(remote_socket, client_socket, sni_to_use, False, None, obfs_in)).start()
        else:
            threading.Thread(target=forward, args=(client_socket, remote_socket, sni_to_use, False, None, obfs_in)).start()
            threading.Thread(target=forward, args=(remote_socket, client_socket, sni_to_use, False, obfs_out, None)).start()
            
    except: client_socket.close()
    finally: stats.conn_down()

def native_udp_relay(lhost, lport, rhost, rport, obfs_key):
    server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    server.bind((lhost, lport))
    clients = {}
    print(f"[*] Started Native UDP: {lhost}:{lport} -> {rhost}:{rport}")
    
    while True:
        data, addr = server.recvfrom(65535)
        stats.add_sent(len(data))
        if obfs_key:
            obfs_hash = hashlib.sha256((obfs_key + str(addr)).encode()).digest()
            data = bytes(d ^ obfs_hash[i % 32] for i, d in enumerate(data))

        if addr not in clients:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            clients[addr] = s
            def receive_back(client_addr, remote_sock, key):
                while True:
                    try:
                        rdata, _ = remote_sock.recvfrom(65535)
                        stats.add_recv(len(rdata))
                        if key:
                            r_hash = hashlib.sha256((key + str(client_addr)).encode()).digest()
                            rdata = bytes(d ^ r_hash[i % 32] for i, d in enumerate(rdata))
                        server.sendto(rdata, client_addr)
                    except: break
            threading.Thread(target=receive_back, args=(addr, s, obfs_key), daemon=True).start()
        clients[addr].sendto(data, (rhost, rport))

def start_tcp_listener(lhost, lport, rhost, rport, sni_list, do_spoof, rotation_interval, psk, obfs_key):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    
    class SNIState:
        def __init__(self, snis):
            self.snis = snis
            self.current_idx = 0
            self.last_rotate = time.time()
        def get_sni(self):
            if rotation_interval > 0 and (time.time() - self.last_rotate) > rotation_interval:
                self.current_idx = (self.current_idx + 1) % len(self.snis)
                self.last_rotate = time.time()
            return self.snis[self.current_idx]

    sni_state = SNIState(sni_list)
    try:
        server.bind((lhost, lport))
        server.listen(100)
        print(f"[*] Listening TCP: {lhost}:{lport} -> {rhost}:{rport}")
        while True:
            conn, addr = server.accept()
            threading.Thread(target=handle_tcp_client, args=(conn, rhost, rport, sni_state.get_sni, do_spoof, psk, obfs_key)).start()
    except Exception as e: print(f"[!] Bind Error: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--lhost', default='0.0.0.0')
    parser.add_argument('--rhost', required=True)
    parser.add_argument('--ports', required=True)
    parser.add_argument('--sni', default='google.com')
    parser.add_argument('--no-spoof', action='store_true')
    parser.add_argument('--rotate', type=int, default=0)
    parser.add_argument('--psk')
    parser.add_argument('--obfs-key')
    parser.add_argument('--udp-mode', choices=['none', 'native', 'tcp'], default='none')
    parser.add_argument('--show-stats', action='store_true')
    
    args = parser.parse_args()
    if args.show_stats: threading.Thread(target=stats.display, daemon=True).start()

    port_pairs = []
    for pair in args.ports.split(','):
        if ':' in pair: l, r = pair.split(':'); port_pairs.append((int(l), int(r)))
        else: p = int(pair); port_pairs.append((p, p))

    for lport, rport in port_pairs:
        t = threading.Thread(target=start_tcp_listener, args=(args.lhost, lport, args.rhost, rport, args.sni.split(','), not args.no_spoof, args.rotate, args.psk, args.obfs_key))
        t.daemon = True; t.start()
        if args.udp_mode == 'native':
            ut = threading.Thread(target=native_udp_relay, args=(args.lhost, lport, args.rhost, rport, args.obfs_key))
            ut.daemon = True; ut.start()

    try: 
        while True: time.sleep(1)
    except KeyboardInterrupt: pass
