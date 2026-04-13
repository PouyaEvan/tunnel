# Python SNI Spoof Tunnel

A simple tunnel to understand the concept of **SNI Spoofing**. This tool receives traffic from a local port (Iran server) and replaces the SNI field with a fake domain when forwarding to the destination (Kharej/Foreign server) to bypass filtering.

## Features
- Automatic detection of TLS Client Hello packets.
- Real SNI replacement with a fake SNI (e.g., `google.com`).
- Automatic correction of TLS record lengths and handshake fields.
- Support for non-TLS traffic (like HTTP or SSH) via transparent forwarding.

## How to Set Up and Test (Iran - Kharej Scenario)

### 1. Configuration
You can pass your parameters via the `run.sh` menu or by calling `sni_tunnel/tunnel.py` directly with arguments:
- `REMOTE IP`: Your destination server address.
- `FAKE SNI`: A domain that is not filtered in your network.

### 2. Execution
Run the unified management script:
```bash
./run.sh
```
Follow the menu prompts to select your server mode (Iran or Kharej).

### 3. Verification

To ensure that the SNI has actually been changed, use one of the following methods:

#### Method A: Observe Bytes on Kharej Server (Recommended)
On the foreign (Kharej) server, run the following command to monitor incoming packets on port 443:
```bash
sudo tcpdump -i any -X -s0 tcp port 443
```
Now, from your client (or from within the Iran server), send a request:
```bash
curl -v -k --resolve example.com:8080:127.0.0.1 https://example.com:8080
```
In the `tcpdump` output on the foreign server, look for the string `google.com`. If you see it, the tunnel has successfully replaced the SNI.

#### Method B: Use TShark for Scientific Verification
If `tshark` is installed on the foreign server:
```bash
sudo tshark -i any -Y "ssl.handshake.extensions_server_name" -V tcp port 443
```
This command directly extracts and displays the SNI field of incoming packets.

### 4. Testing Non-TLS Traffic
You can also test the tunnel for regular traffic:
```bash
# Regular HTTP test (if the foreign server responds on port 80)
curl -H "Host: example.com" http://localhost:8080
```
In this case, the tunnel console will display the message `Non-TLS traffic detected` and pass the traffic through without modification.

## Important Notes
- **SSL Error:** Due to the SNI change, clients (like browsers) will show a `Certificate Mismatch` error because the server sends the certificate for the original domain while the client thinks it's connected to the fake domain. This is expected at this stage.
- **Bind Address:** For real use, ensure `LOCAL_ADDR` is set to `0.0.0.0` so the tunnel is accessible from the internet.
