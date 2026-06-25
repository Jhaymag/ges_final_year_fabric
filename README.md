# GES Network — Hyperledger Fabric

A permissioned blockchain network for the Ghana Education Service (GES), built on Hyperledger Fabric 2.5.

**Organisations:** GES · GTEC · NTC  
**Channel:** `geschannel`  
**Chaincode:** `ges-verify` (CCaaS, Go)

---

## Prerequisites

Pick **one** of three setup paths depending on your OS:

| Path | OS | Needs |
|------|----|-------|
| A. WSL2 / Ubuntu | Windows (via WSL2) or native Ubuntu | `install-fabric.sh` installs Go, jq, Fabric binaries |
| B. Windows native | Windows, no WSL2 | Docker Desktop only — `setup.bat` |
| C. Git Bash (Windows, no WSL2) | Windows | Docker Desktop + Git Bash — `setup-ges-network-gitbash.sh` |

All three paths drive the same Docker images and produce the same network. Path C is recommended on Windows if `setup.bat` fails with a cmd.exe parsing error (see Troubleshooting).

---

## Setup — Path A: WSL2 / Ubuntu

### 1. Install all prerequisites + Fabric binaries (once)

```bash
chmod +x install-fabric.sh
./install-fabric.sh
```

This installs: **Go 1.21**, **jq**, **Fabric 2.5.15 binaries** (`cryptogen`, `configtxgen`, `peer`), and pulls the Fabric Docker images.

After it finishes, reload your PATH:

```bash
source ~/.bashrc
```

### 2. Start the network

```bash
chmod +x setup-ges-network.sh deploy-chaincode.sh setenv.sh
./setup-ges-network.sh
```

This will:
- Generate crypto material (`crypto-config/`)
- Generate channel artifacts (`channel-artifacts/`)
- Start all Docker containers
- Create and join the `geschannel` channel
- Update anchor peers for all three orgs (required for cross-org service discovery)
- Build and deploy the `ges-verify` chaincode

### 3. Set your CLI environment

After setup, target a specific org's peer for CLI commands:

```bash
source setenv.sh ges    # or: gtec / ntc
```

---

## Setup — Path B: Windows native (Docker Desktop only)

```bat
setup.bat
```

Requires only Docker Desktop running. Performs the same steps as Path A above, driven entirely through `docker build`/`docker run`/`docker compose` calls (no local Fabric binaries needed).

> **Known issue:** on some Windows/cmd.exe configurations, `setup.bat` fails partway through Step 3 with an error like `Environment variable -e not defined` — a cmd.exe quoting quirk with multi-line `docker run ... bash -c "..."` blocks. If you hit this, use Path C instead; it runs the identical steps from Git Bash, which doesn't have this quoting problem.

---

## Setup — Path C: Git Bash (Windows, no WSL2)

```bash
./setup-ges-network-gitbash.sh
```

Requires Docker Desktop + Git Bash (ships with Git for Windows). Drives the same Docker images as Path A/B but from a POSIX shell, avoiding the cmd.exe quoting issue in Path B. This is the path that was actually validated end-to-end (network up, channel joined, anchor peers updated, chaincode committed, `HealthCheck` returning `UP`) during development on a Windows machine without WSL2.

---

## Redeploy Chaincode

If you update the chaincode, bump `CC_VERSION` and `CC_SEQUENCE` in `deploy-chaincode.sh`, then:

```bash
./deploy-chaincode.sh
```

---

## Project Structure

```
ges-network/
├── chaincode/
│   └── ges-verify/         # Go chaincode source
│       ├── ges-verify.go
│       ├── Dockerfile
│       ├── go.mod
│       └── go.sum
├── data/                   # Seed data CSV files
├── configtx.yaml           # Channel & org configuration
├── crypto-config.yaml      # Crypto material template
├── docker-compose.yaml     # All peer/orderer/chaincode services
├── install-fabric.sh       # Installs Go, jq, and Fabric binaries (Path A)
├── setup-ges-network.sh    # Full network bootstrap script (Path A, WSL2/Ubuntu)
├── setup.bat                # Full network bootstrap script (Path B, Windows native)
├── setup-ges-network-gitbash.sh # Full network bootstrap script (Path C, Git Bash)
├── deploy-chaincode.sh / .bat   # Chaincode install/approve/commit (re-run after bumping CC_VERSION/CC_SEQUENCE)
├── setenv.sh               # Sets peer CLI environment per org
├── upload-licenses.sh      # Seed license data to ledger
└── upload-qualifications.sh
```

> `crypto-config/`, `channel-artifacts/`, `chaincode.env`, and private keys
> are excluded from git — regenerated locally by the setup script.

---

## Network Endpoints

| Service     | Address                        |
|-------------|-------------------------------|
| Orderer     | `orderer.ges.edu.gh:7050`     |
| GES Peer    | `peer0.ges.ges.edu.gh:7051`   |
| GTEC Peer   | `peer0.gtec.ges.edu.gh:9051`  |
| NTC Peer    | `peer0.ntc.ges.edu.gh:11051`  |
| Chaincode   | `ges-verify-chaincode:9999`   |

---

## Troubleshooting

**`docker run --network ges-network_ges-network ...` fails with "network not found".**
The Docker network name is `<compose-project-name>_ges-network`. All setup/deploy scripts now pin `COMPOSE_PROJECT_NAME=ges-network` so the network is always named `ges-network_ges-network`, regardless of what this folder is actually named on disk (it doesn't have to be called `ges-network`). If you're running `docker compose` manually outside these scripts, set that env var first, or pass `-p ges-network`.

**Write transactions fail with `no peer combination can satisfy the endorsement policy` / `no combination of peers can be derived`.**
This means anchor peers haven't been configured, so Fabric Gateway's service discovery can't see the other orgs' peers. All three setup scripts now submit the `*MSPanchors.tx` channel updates automatically — if you bootstrapped the network before this fix, re-run the setup script (it cleans up and recreates from scratch), or manually run the `peer channel update -f channel-artifacts/<ORG>MSPanchors.tx ...` commands for GESMSP, GTECMSP, and NTCMSP.

**Chaincode calls from the Node.js backend fail with `access denied: channel [geschannel] creator org [...]` even though the same identity works fine via the `peer` CLI.**
This is almost always a missing low-S ECDSA signature canonicalization in the client's signer, not an actual access-control problem. Use `@hyperledger/fabric-gateway`'s `signers.newPrivateKeySigner(privateKey)` rather than hand-rolling `crypto.sign()` — see `ges/src/services/fabricClient.js`.

**`setup.bat` fails at Step 3 with `Environment variable -e not defined` / `'CRYPTO' is not recognized` / `'cryptogen' is not recognized`.**
Known cmd.exe quoting bug with multi-line `docker run ... bash -c "<heredoc>"` blocks. Use `setup-ges-network-gitbash.sh` from Git Bash instead (Path C above) — it's functionally identical but avoids cmd.exe entirely.
