# Kali Desktop in Browser

Ephemeral Kali Linux desktop accessible from any browser. Runs on GitHub Actions, tunneled via ngrok. Spin up, hack, close — nothing persists.

**Stack:** Kali Rolling + XFCE + TigerVNC + noVNC + ngrok

**Tools included:** `kali-tools-top10` — nmap, metasploit, burpsuite, sqlmap, wireshark, hydra, john, aircrack-ng, responder, netexec

## Setup (5 minutes)

1. **Fork/clone** this repo

2. **Get a free ngrok auth token** at [ngrok.com](https://ngrok.com)

3. **Add the token** as a GitHub Actions secret:
   - Repo → Settings → Secrets and variables → Actions → New repository secret
   - Name: `NGROK_AUTH_TOKEN`
   - Value: your ngrok token

4. **Build the image** (one-time, ~15-20 min):
   - Actions → "Build Kali Desktop Image" → Run workflow

5. **Start a session**:
   - Actions → "Kali Desktop Session" → Run workflow
   - Pick duration and VNC password
   - Wait ~3 min for the container to pull and start
   - Find the ngrok URL in the workflow logs

## Customizing tools

Edit the `Dockerfile` layer 2 to change which tools are installed:

```dockerfile
# Minimal (just top 10)
kali-tools-top10

# More tools (includes top10 + masscan, amass, etc.)
kali-linux-headless

# Web-focused
kali-tools-top10 kali-tools-web

# Full default Kali install (large image)
kali-linux-default
```

Push the change — the image auto-rebuilds via GitHub Actions.

## Architecture

```
Browser → ngrok (HTTPS) → noVNC (:6080) → websockify → TigerVNC (:5901) → XFCE (X11 :1)
```

Everything runs in a single container on a GitHub Actions runner. The session auto-terminates after the chosen duration.
