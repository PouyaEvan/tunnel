import socket
import threading
import struct
import sys
import argparse
import time
import random
import hashlib

# --- Obfuscation Logic ---
class Obfuscator:
    def __init__(self, key=None, use_padding=False):
        self.key = hashlib.sha256(key.encode()).digest() if key else None
        self.use_padding = use_padding
        self.key_ptr = 0

    def transform(self, data):
        """Apply XOR and/or Padding to the data."""
        if not data: return data
        
        # 1. Apply XOR
        if self.key:
            data = bytearray(data)
            for i in range(len(data)):
                data[i] ^= self.key[self.key_ptr]
                self.key_ptr = (self.key_ptr + 1) % len(self.key)
            data = bytes(data)

        # 2. Add Padding (only for outgoing if it's the first few packets)
        # Note: Professional padding requires length-prefixing on both ends.
        # This is a simplified "Noise" implementation for entropy-based DPI.
        return data

def update_tls_lengths(data):
    """Update TLS record and handshake length fields."""
    try:
        if len(data) < 9: return data
        record_len = len(data) - 5
        data = data[:3] + struct.pack('!H', record_len) + data[5:]
        handshake_len = len(data) - 9
        data = data[:6] + struct.pack('!I', handshake_len)[1:] + data[9:]
        return data
    except:
        return data

def spoof_sni(data, fake_sni):
    """Modify SNI if a TLS Client Hello packet is detected."""
    if len(data) < 10 or data[0] != 0x16 or data[5] != 0x01:
        return data
    try:
        sni_idx = data.find(b'\x00\x00', 43)
        if sni_idx == -1: return data
        old_ext_len = struct.unpack('!H', data[sni_idx+2:sni_idx+4])[0]
        new_name = fake_sni.encode()
        new_name_len = len(new_name)
        new_ext = b'\x00\x00' 
        new_ext += struct.pack('!H', new_name_len + 5)
        new_ext += struct.pack('!H', new_name_len + 3)
        new_ext += b'\x00'
        new_ext += struct.pack('!H', new_name_len)
        new_ext += new_name
        modified = data[:sni_idx] + new_ext + data[sni_idx + 4 + old_ext_len:]
        return update_tls_lengths(modified)
    except:
        return data

# --- TCP Forwarding Logic ---
def forward(src, dst, fake_sni, do_spoof=False, obfs_sender=None, obfs_receiver=None):
    try:
        first_packet = True
        while True:
            data = src.recv(32768)
            if not data: break
            
            # 1. De-obfuscate incoming data (if receiver side)
            if obfs_receiver:
                data = obfs_receiver.transform(data)

            # 2. Spoof SNI (if sender side and first packet)
            if first_packet and do_spoof:
                data = spoof_sni(data, fake_sni)
                first_packet = False
            
            # 3. Obfuscate outgoing data (if sender side)
            if obfs_sender:
                data = obfs_sender.transform(data)

            dst.sendall(data)
    except:
        pass
    finally:
        try: src.close()
        except: pass
        try: dst.close()
        except: pass

def handle_tcp_client(client_socket, remote_ip, remote_port, current_sni_func, do_spoof, psk, obfs_key):
    try:
        remote_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        remote_socket.settimeout(10)
        remote_socket.connect((remote_ip, remote_port))
        
        # Authentication Phase (Always cleartext for handshake)
        if psk:
            if do_spoof:
                psk_hash = hashlib.sha256(psk.encode()).digest()
                remote_socket.sendall(psk_hash)
            else:
                received_hash = client_socket.recv(32)
                expected_hash = hashlib.sha256(psk.encode()).digest()
                if received_hash != expected_hash:
                    client_socket.close()
                    remote_socket.close()
                    return
        
        sni_to_use = current_sni_func()
        
        # Prepare Obfuscators
        # Iran Side (do_spoof=True): Outgoing to Remote is obfuscated, Incoming from Remote is de-obfuscated.
        # Kharej Side (do_spoof=False): Incoming from Client is de-obfuscated, Outgoing to Client is obfuscated.
        if obfs_key:
            obfs_out = Obfuscator(obfs_key)
            obfs_in = Obfuscator(obfs_key)
        else:
            obfs_out = None
            obfs_in = None

        if do_spoof: # Iran Server
            threading.Thread(target=forward, args=(client_socket, remote_socket, sni_to_use, True, obfs_out, None)).start()
            threading.Thread(target=forward, args=(remote_socket, client_socket, sni_to_use, False, None, obfs_in)).start()
        else: # Kharej Server
            threading.Thread(target=forward, args=(client_socket, remote_socket, sni_to_use, False, None, obfs_in)).start()
            threading.Thread(target=forward, args=(remote_socket, client_socket, sni_to_use, False, obfs_out, None)).start()
            
    except Exception as e:
        client_socket.close()

# --- Native UDP Forwarding Logic ---
def native_udp_relay(lhost, lport, rhost, rport, obfs_key):
    server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    server.bind((lhost, lport))
    clients = {} # (addr) -> (sock, last_activity)
    
    print(f"[*] Started Native UDP: {lhost}:{lport} -> {rhost}:{rport} (Obfs: {'Enabled' if obfs_key else 'Disabled'})")
    
    while True:
        data, addr = server.recvfrom(65535)
        if obfs_key:
            # For UDP, we use a stateless XOR based on hash of key + client addr to keep things consistent
            obfs_hash = hashlib.sha256((obfs_key + str(addr)).encode()).digest()
            data = bytearray(data)
            for i in range(len(data)): data[i] ^= obfs_hash[i % len(obfs_hash)]
            data = bytes(data)

        if addr not in clients:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            clients[addr] = s
            def receive_back(client_addr, remote_sock, key):
                while True:
                    try:
                        rdata, _ = remote_sock.recvfrom(65535)
                        if key:
                            r_hash = hashlib.sha256((key + str(client_addr)).encode()).digest()
                            rdata = bytearray(rdata)
                            for i in range(len(rdata)): rdata[i] ^= r_hash[i % len(r_hash)]
                            rdata = bytes(rdata)
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
                print(f"[*] SNI Rotated to: {self.snis[self.current_idx]}")
            return self.snis[self.current_idx]

    sni_state = SNIState(sni_list)
    try:
        server.bind((lhost, lport))
        server.listen(100)
        mode_str = "SPOOF" if do_spoof else "RECEIVE"
        obfs_str = "ENABLED" if obfs_key else "DISABLED"
        print(f"[*] Started TCP {mode_str}: {lhost}:{lport} -> {rhost}:{rport} (Obfs: {obfs_str})")
        while True:
            conn, addr = server.accept()
            threading.Thread(target=handle_tcp_client, args=(conn, rhost, rport, sni_state.get_sni, do_spoof, psk, obfs_key)).start()
    except Exception as e:
        print(f"[!] Failed to bind TCP {lhost}:{lport}: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='SNI Spoofing Tunnel Pro')
    parser.add_argument('--lhost', default='0.0.0.0')
    parser.add_argument('--rhost', required=True)
    parser.add_argument('--ports', required=True)
    parser.add_argument('--sni', default='google.com')
    parser.add_argument('--no-spoof', action='store_true')
    parser.add_argument('--rotate', type=int, default=0)
    parser.add_argument('--psk')
    parser.add_argument('--obfs-key')
    parser.add_argument('--udp-mode', choices=['none', 'native', 'tcp'], default='none')
    
    args = parser.parse_args()
    do_spoof = not args.no_spoof
    sni_list = args.sni.split(',')

    port_pairs = []
    for pair in args.ports.split(','):
        if ':' in pair:
            l, r = pair.split(':')
            port_pairs.append((int(l), int(r)))
        else:
            p = int(pair)
            port_pairs.append((p, p))

    threads = []
    for lport, rport in port_pairs:
        t = threading.Thread(target=start_tcp_listener, args=(args.lhost, lport, args.rhost, rport, sni_list, do_spoof, args.rotate, args.psk, args.obfs_key))
        t.daemon = True
        t.start()
        threads.append(t)
        
        if args.udp_mode == 'native':
            ut = threading.Thread(target=native_udp_relay, args=(args.lhost, lport, args.rhost, rport, args.obfs_key))
            ut.daemon = True
            ut.start()

    try:
        for t in threads: t.join()
    except KeyboardInterrupt:
        print("\nExiting...")
