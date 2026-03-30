# Kali Linux Desktop in Browser

Spin up a temporary Kali Linux desktop you can access from any browser. Runs on GitHub Actions, tunneled through ngrok. Use it, close it — nothing persists.

## What you get

- Full Kali Linux desktop with dark theme, accessible in your browser
- Pre-installed: `kali-tools-top10` (nmap, metasploit, burpsuite, sqlmap, wireshark, hydra, john, aircrack-ng, responder, netexec)
- Firefox, terminal, file manager, and standard CLI tools
- Auto-expires after your chosen duration (1-6 hours)

## Setup

1. **Fork/clone** this repo

2. **Get a free ngrok token** at [ngrok.com](https://ngrok.com) and add it as a GitHub Actions secret:
   - Repo → Settings → Secrets → Actions → `NGROK_AUTH_TOKEN`

3. **Build the image** (one-time):
   - Actions → "Build Kali Desktop Image" → Run workflow

4. **Start a session**:
   - Actions → "Kali Desktop Session" → Run workflow
   - Pick duration and password
   - Grab the ngrok URL from the workflow logs

## How it works

```
Browser → ngrok (HTTPS) → KasmVNC (:6901) → Kali Desktop
```

Single container on a GitHub Actions runner. KasmVNC handles the VNC server, web client, and WebSocket transport. Session auto-terminates after your chosen duration.

## Customizing tools

Edit `Dockerfile` layer 4:

```dockerfile
kali-tools-top10          # Default — top 10 tools
kali-linux-headless       # More tools (masscan, amass, etc.)
kali-tools-top10 kali-tools-web  # Web-focused
kali-linux-default        # Full Kali (large image)
```

Push and the image auto-rebuilds.
