#!/bin/bash

# ──────────────────────────────────────────────
# GES Verify Chaincode Deployment Script
# Fabric 2.5.x | Docker Compose | geschannel
# WSL2 (Ubuntu) compatible
# ──────────────────────────────────────────────

set -e

# ── WSL guard: abort if script has Windows CRLF line endings ──────────────
if file "$0" | grep -q CRLF; then
  echo "ERROR: This script has Windows (CRLF) line endings."
  echo "Fix with: sed -i 's/\r//' $(basename $0)"
  exit 1
fi

# ── Dependency checks ─────────────────────────────────────────────────────
for cmd in jq peer docker go; do
  if ! command -v $cmd &>/dev/null; then
    echo "ERROR: '$cmd' is not installed or not in PATH."
    echo "  jq  → sudo apt install jq"
    echo "  peer, docker, go → check your Fabric/Docker/Go installation"
    exit 1
  fi
done

# ── Paths ─────────────────────────────────────────────────────────────────
NETWORK_DIR=~/fabric/ges-network
CHAINCODE_DIR=~/fabric/ges-network/chaincode/ges-verify
CHANNEL_NAME=geschannel
CC_NAME=ges-verify
CC_VERSION=1.0          # bump on each redeploy
CC_SEQUENCE=1           # bump on each redeploy
CC_LABEL=${CC_NAME}_${CC_VERSION}
CRYPTO=$NETWORK_DIR/crypto-config

# ── Orderer ───────────────────────────────────────────────────────────────
ORDERER_ADDRESS=localhost:7050
ORDERER_HOST_ALIAS=orderer.ges.edu.gh
ORDERER_CA=$CRYPTO/ordererOrganizations/ges.edu.gh/orderers/orderer.ges.edu.gh/tls/ca.crt

# ── Peer TLS + MSP paths ──────────────────────────────────────────────────
GTEC_ADDRESS=peer0.gtec.ges.edu.gh:9051
GTEC_TLS=$CRYPTO/peerOrganizations/gtec.ges.edu.gh/peers/peer0.gtec.ges.edu.gh/tls/ca.crt
GTEC_MSP=$CRYPTO/peerOrganizations/gtec.ges.edu.gh/users/Admin@gtec.ges.edu.gh/msp

NTC_ADDRESS=peer0.ntc.ges.edu.gh:11051
NTC_TLS=$CRYPTO/peerOrganizations/ntc.ges.edu.gh/peers/peer0.ntc.ges.edu.gh/tls/ca.crt
NTC_MSP=$CRYPTO/peerOrganizations/ntc.ges.edu.gh/users/Admin@ntc.ges.edu.gh/msp

GES_ADDRESS=peer0.ges.ges.edu.gh:7051
GES_TLS=$CRYPTO/peerOrganizations/ges.ges.edu.gh/peers/peer0.ges.ges.edu.gh/tls/ca.crt
GES_MSP=$CRYPTO/peerOrganizations/ges.ges.edu.gh/users/Admin@ges.ges.edu.gh/msp

# ── Helper: safe package ID extraction via JSON ───────────────────────────
get_package_id() {
  peer lifecycle chaincode queryinstalled --output json \
    | jq -r ".installed_chaincodes[] | select(.label==\"${CC_LABEL}\") | .package_id"
}

# ── Helper: wait for CCaaS port using bash built-in /dev/tcp ─────────────
# Works on WSL Ubuntu without needing netcat installed.
wait_for_port() {
  local host=$1 port=$2
  echo "Waiting for $host:$port to be ready..."
  local attempts=0
  until (echo > /dev/tcp/$host/$port) 2>/dev/null; do
    sleep 1
    attempts=$((attempts + 1))
    if [ $attempts -ge 30 ]; then
      echo "ERROR: $host:$port did not become ready after 30 seconds."
      echo "Check: docker logs ges-verify-chaincode"
      exit 1
    fi
  done
  echo "✓ $host:$port is ready"
}

# ─────────────────────────────────────────────────────────────────────────
# Step 1: Build chaincode binary + Docker image
# ─────────────────────────────────────────────────────────────────────────
echo "===> Step 1: Build chaincode Docker image"
cd $CHAINCODE_DIR
go mod tidy
docker build --no-cache -t ges-verify:1.0 $CHAINCODE_DIR
echo "✓ Docker image built"

# ─────────────────────────────────────────────────────────────────────────
# Step 2: Package as CCaaS
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "===> Step 2: Package chaincode as CCaaS"
cd $NETWORK_DIR

cat > metadata.json <<EOF
{"type":"ccaas","label":"${CC_LABEL}"}
EOF

cat > connection.json <<EOF
{"address":"ges-verify-chaincode:9999","dial_timeout":"10s","tls_required":false}
EOF

tar cfz code.tar.gz connection.json
tar cfz ${CC_NAME}.tar.gz metadata.json code.tar.gz
rm -f metadata.json connection.json code.tar.gz
echo "✓ Package created: ${CC_NAME}.tar.gz"

# ─────────────────────────────────────────────────────────────────────────
# Step 3: Install on GTEC peer
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "===> Step 3: Install on GTEC peer"
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=GTECMSP
export CORE_PEER_TLS_ROOTCERT_FILE=$GTEC_TLS
export CORE_PEER_MSPCONFIGPATH=$GTEC_MSP
export CORE_PEER_ADDRESS=$GTEC_ADDRESS

peer lifecycle chaincode install ${CC_NAME}.tar.gz
echo "✓ Installed on GTEC peer"

# ─────────────────────────────────────────────────────────────────────────
# Step 4: Extract package ID, write chaincode.env, restart CCaaS
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "===> Step 4: Extract package ID and restart CCaaS container"
export CC_PACKAGE_ID=$(get_package_id)

if [ -z "$CC_PACKAGE_ID" ]; then
  echo "ERROR: Could not find package ID for label '${CC_LABEL}'."
  echo "Check: peer lifecycle chaincode queryinstalled --output json"
  exit 1
fi
echo "Package ID: $CC_PACKAGE_ID"

# Write chaincode.env — docker-compose reads this for the CCaaS service.
# Avoids mutating docker-compose.yaml and works on both Linux and WSL.
echo "CHAINCODE_ID=${CC_PACKAGE_ID}" > $NETWORK_DIR/chaincode.env
echo "✓ Wrote chaincode.env"

docker compose -f $NETWORK_DIR/docker-compose.yaml up -d --no-deps ges-verify-chaincode

# Use bash /dev/tcp instead of nc — no extra package needed on WSL Ubuntu.
wait_for_port localhost 9999

# ─────────────────────────────────────────────────────────────────────────
# Step 5: Approve for GTEC
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "===> Step 5: Approve for GTEC"
peer lifecycle chaincode approveformyorg \
  -o $ORDERER_ADDRESS \
  --ordererTLSHostnameOverride $ORDERER_HOST_ALIAS \
  --channelID $CHANNEL_NAME \
  --name $CC_NAME \
  --version $CC_VERSION \
  --package-id $CC_PACKAGE_ID \
  --sequence $CC_SEQUENCE \
  --tls \
  --cafile $ORDERER_CA
echo "✓ GTEC approved"

# ─────────────────────────────────────────────────────────────────────────
# Step 6: Install on NTC peer
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "===> Step 6: Install on NTC peer"
export CORE_PEER_LOCALMSPID=NTCMSP
export CORE_PEER_TLS_ROOTCERT_FILE=$NTC_TLS
export CORE_PEER_MSPCONFIGPATH=$NTC_MSP
export CORE_PEER_ADDRESS=$NTC_ADDRESS

peer lifecycle chaincode install ${CC_NAME}.tar.gz
echo "✓ Installed on NTC peer"

# ─────────────────────────────────────────────────────────────────────────
# Step 7: Approve for NTC
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "===> Step 7: Approve for NTC"
# CC_PACKAGE_ID is already set — same .tar.gz produces the same hash.
peer lifecycle chaincode approveformyorg \
  -o $ORDERER_ADDRESS \
  --ordererTLSHostnameOverride $ORDERER_HOST_ALIAS \
  --channelID $CHANNEL_NAME \
  --name $CC_NAME \
  --version $CC_VERSION \
  --package-id $CC_PACKAGE_ID \
  --sequence $CC_SEQUENCE \
  --tls \
  --cafile $ORDERER_CA
echo "✓ NTC approved"

# ─────────────────────────────────────────────────────────────────────────
# Step 8: Install on GES peer
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "===> Step 8: Install on GES peer"
export CORE_PEER_LOCALMSPID=GESMSP
export CORE_PEER_TLS_ROOTCERT_FILE=$GES_TLS
export CORE_PEER_MSPCONFIGPATH=$GES_MSP
export CORE_PEER_ADDRESS=$GES_ADDRESS

peer lifecycle chaincode install ${CC_NAME}.tar.gz
echo "✓ Installed on GES peer"

# ─────────────────────────────────────────────────────────────────────────
# Step 9: Approve for GES
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "===> Step 9: Approve for GES"
peer lifecycle chaincode approveformyorg \
  -o $ORDERER_ADDRESS \
  --ordererTLSHostnameOverride $ORDERER_HOST_ALIAS \
  --channelID $CHANNEL_NAME \
  --name $CC_NAME \
  --version $CC_VERSION \
  --package-id $CC_PACKAGE_ID \
  --sequence $CC_SEQUENCE \
  --tls \
  --cafile $ORDERER_CA
echo "✓ GES approved"

# ─────────────────────────────────────────────────────────────────────────
# Step 10: Check commit readiness
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "===> Step 10: Check commit readiness"
peer lifecycle chaincode checkcommitreadiness \
  --channelID $CHANNEL_NAME \
  --name $CC_NAME \
  --version $CC_VERSION \
  --sequence $CC_SEQUENCE \
  --tls \
  --cafile $ORDERER_CA \
  --output json
echo ""
echo "All three orgs must show true above before proceeding."
echo "Press Enter to continue or Ctrl+C to abort..."
read

# ─────────────────────────────────────────────────────────────────────────
# Step 11: Commit
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "===> Step 11: Commit to geschannel"
peer lifecycle chaincode commit \
  -o $ORDERER_ADDRESS \
  --ordererTLSHostnameOverride $ORDERER_HOST_ALIAS \
  --channelID $CHANNEL_NAME \
  --name $CC_NAME \
  --version $CC_VERSION \
  --sequence $CC_SEQUENCE \
  --tls \
  --cafile $ORDERER_CA \
  --peerAddresses $GTEC_ADDRESS \
  --tlsRootCertFiles $GTEC_TLS \
  --peerAddresses $NTC_ADDRESS \
  --tlsRootCertFiles $NTC_TLS \
  --peerAddresses $GES_ADDRESS \
  --tlsRootCertFiles $GES_TLS
echo "✓ Chaincode committed to geschannel"

# ─────────────────────────────────────────────────────────────────────────
# Step 12: Verify
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "===> Step 12: Verify deployment"
peer lifecycle chaincode querycommitted \
  --channelID $CHANNEL_NAME \
  --name $CC_NAME \
  --tls \
  --cafile $ORDERER_CA
echo ""
echo "✓ Deployment complete!"
