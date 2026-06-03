# GES Network — Hyperledger Fabric

A permissioned blockchain network for the Ghana Education Service (GES), built on Hyperledger Fabric 2.5.

**Organisations:** GES · GTEC · NTC  
**Channel:** `geschannel`  
**Chaincode:** `ges-verify` (CCaaS, Go)

---

## Prerequisites

- Ubuntu / WSL2 (Ubuntu)
- Docker + Docker Compose → [Install Docker](https://docs.docker.com/engine/install/ubuntu/)

Everything else (Go, jq, Fabric binaries) is installed by `install-fabric.sh`.

---

## Setup

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
- Build and deploy the `ges-verify` chaincode

### 3. Set your CLI environment

After setup, target a specific org's peer for CLI commands:

```bash
source setenv.sh ges    # or: gtec / ntc
```

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
├── install-fabric.sh       # Installs Go, jq, and Fabric binaries
├── setup-ges-network.sh    # Full network bootstrap script
├── deploy-chaincode.sh     # Chaincode install/approve/commit
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
