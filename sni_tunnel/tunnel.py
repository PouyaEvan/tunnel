import socket
import threading
import struct
import sys
import argparse

def update_tls_lengths(data):
    """Update TLS record and handshake length fields to prevent rejection by destination."""
    try:
        if len(data) < 9: return data
        # Record Length (bytes 3-4)
        record_len = len(data) - 5
        data = data[:3] + struct.pack('!H', record_len) + data[5:]
        # Handshake Length (bytes 6-8)
        handshake_len = len(data) - 9
        data = data[:6] + struct.pack('!I', handshake_len)[1:] + data[9:]
        return data
    except:
        return data

def spoof_sni(data, fake_sni):
    """Modify SNI if a TLS Client Hello packet is detected."""
    # 0x16 = Handshake, 0x01 = Client Hello
    if len(data) < 10 or data[0] != 0x16 or data[5] != 0x01:
        return data
    
    try:
        sni_idx = data.find(b'\x00\x00', 43)
        if sni_idx == -1: return data

        # Verify if it's actually an SNI tag (Type 00 00)
        old_ext_len = struct.unpack('!H', data[sni_idx+2:sni_idx+4])[0]
        
        new_name = fake_sni.encode()
        new_name_len = len(new_name)
        
        # Reconstruct SNI section
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

def forward(src, dst, fake_sni, do_spoof=False):
    try:
        first_packet = True
        while True:
            data = src.recv(16384)
            if not data: break
            
            if first_packet and do_spoof:
                original_len = len(data)
                data = spoof_sni(data, fake_sni)
                if len(data) != original_len:
                    print(f"[!] SNI Spoofed: {fake_sni}")
                else:
                    print("[.] Non-TLS or No SNI traffic detected. Passing through...")
                first_packet = False
                
            dst.sendall(data)
    except:
        pass
    finally:
        try: src.close()
        except: pass
        try: dst.close()
        except: pass

def handle_client(client_socket, remote_ip, remote_port, fake_sni, do_spoof):
    try:
        remote_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        remote_socket.settimeout(10)
        remote_socket.connect((remote_ip, remote_port))

        # Only spoof if do_spoof is True (typically on Iran server)
        threading.Thread(target=forward, args=(client_socket, remote_socket, fake_sni, do_spoof)).start()
        threading.Thread(target=forward, args=(remote_socket, client_socket, fake_sni, False)).start()
    except Exception as e:
        print(f"[-] Connection error: {e}")
        client_socket.close()

def start(local_host, local_port, remote_host, remote_port, fake_sni, do_spoof):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((local_host, local_port))
    server.listen(100)

    mode = "SPOOF" if do_spoof else "TRANSPARENT"
    print(f"[*] Mode: {mode}")
    print(f"[*] Tunnel: {local_host}:{local_port} -> {remote_host}:{remote_port}")
    if do_spoof:
        print(f"[*] Spoofing SNI to: {fake_sni}")

    while True:
        conn, addr = server.accept()
        threading.Thread(target=handle_client, args=(conn, remote_host, remote_port, fake_sni, do_spoof)).start()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='SNI Spoofing Tunnel')
    parser.add_argument('--lhost', default='0.0.0.0', help='Local bind address')
    parser.add_argument('--lport', type=int, default=8080, help='Local bind port')
    parser.add_argument('--rhost', required=True, help='Remote server address')
    parser.add_argument('--rport', type=int, default=443, help='Remote server port')
    parser.add_argument('--sni', default='google.com', help='Fake SNI to use')
    parser.add_argument('--no-spoof', action='store_true', help='Disable SNI spoofing (for Kharej server)')

    args = parser.parse_args()

    start(args.lhost, args.lport, args.rhost, args.rport, args.sni, not args.no_spoof)

