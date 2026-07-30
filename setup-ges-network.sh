#!/bin/bash
set -e

CHAINCODE_DIR=~/fabric/ges-network/chaincode/ges-verify

# ── WSL guard: abort if script has Windows CRLF line endings ──────────────
if file "$0" | grep -q CRLF; then
  echo "ERROR: This script has Windows (CRLF) line endings."
  echo "Fix with: sed -i 's/\r//' $(basename $0)"
  exit 1
fi

echo "==> Stopping containers and cleaning up..."
docker compose down
rm -rf crypto-config channel-artifacts geschannel.block
sudo rm -rf ledger-data/

echo "==> Creating ledger data directories..."
mkdir -p ledger-data/{orderer,peer-ges,peer-gtec,peer-ntc}
touch chaincode.env
echo "CHAINCODE_ID=" >> chaincode.env

echo "==> Generating crypto materials..."
cryptogen generate --config=crypto-config.yaml --output=crypto-config

echo "==> Fixing MSP directories..."
for org in ges.ges.edu.gh gtec.ges.edu.gh ntc.ges.edu.gh; do
    cp crypto-config/peerOrganizations/$org/msp/config.yaml \
       crypto-config/peerOrganizations/$org/peers/peer0.$org/msp/
    cp crypto-config/peerOrganizations/$org/users/Admin@$org/msp/signcerts/Admin@$org-cert.pem \
       crypto-config/peerOrganizations/$org/peers/peer0.$org/msp/admincerts/
    cp crypto-config/peerOrganizations/$org/msp/config.yaml \
       crypto-config/peerOrganizations/$org/users/Admin@$org/msp/
done

echo "==> Generating channel artifacts..."
mkdir -p channel-artifacts
configtxgen -profile GESOrdererGenesis -channelID system-channel \
    -outputBlock ./channel-artifacts/genesis.block
configtxgen -profile GESChannel \
    -outputCreateChannelTx ./channel-artifacts/geschannel.tx \
    -channelID geschannel
configtxgen -profile GESChannel \
    -outputAnchorPeersUpdate ./channel-artifacts/GESMSPanchors.tx \
    -channelID geschannel -asOrg GESMSP
configtxgen -profile GESChannel \
    -outputAnchorPeersUpdate ./channel-artifacts/GTECMSPanchors.tx \
    -channelID geschannel -asOrg GTECMSP
configtxgen -profile GESChannel \
    -outputAnchorPeersUpdate ./channel-artifacts/NTCMSPanchors.tx \
    -channelID geschannel -asOrg NTCMSP

echo "Building CCaaS..."
cd $CHAINCODE_DIR
go mod tidy
DOCKER_BUILDKIT=1 docker build -t ges-verify:1.0 $CHAINCODE_DIR

echo "Adding address to /etc/hosts"
sudo tee -a /etc/hosts <<'EOF'
127.0.0.1 peer0.ges.ges.edu.gh
127.0.0.1 peer0.gtec.ges.edu.gh
127.0.0.1 peer0.ntc.ges.edu.gh
127.0.0.1 orderer.ges.edu.gh
EOF

echo "==> Starting Docker containers..."
docker compose up -d

echo "==> Waiting for containers to start..."
sleep 8

echo "==> Setting environment for GES admin..."
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID="GESMSP"
export CORE_PEER_ADDRESS=peer0.ges.ges.edu.gh:7051
export CORE_PEER_TLS_ROOTCERT_FILE=$HOME/fabric/ges-network/crypto-config/peerOrganizations/ges.ges.edu.gh/peers/peer0.ges.ges.edu.gh/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=$HOME/fabric/ges-network/crypto-config/peerOrganizations/ges.ges.edu.gh/users/Admin@ges.ges.edu.gh/msp
export ORDERER_CA=$HOME/fabric/ges-network/crypto-config/ordererOrganizations/ges.edu.gh/orderers/orderer.ges.edu.gh/msp/tlscacerts/tlsca.ges.edu.gh-cert.pem

echo "==> Creating channel..."
peer channel create -o orderer.ges.edu.gh:7050 -c geschannel \
    -f ./channel-artifacts/geschannel.tx \
    --tls --cafile $ORDERER_CA \
    --ordererTLSHostnameOverride orderer.ges.edu.gh

echo "==> Joining GES peer..."
peer channel join -b geschannel.block

echo "==> Joining GTEC peer..."
export CORE_PEER_LOCALMSPID="GTECMSP"
export CORE_PEER_ADDRESS=peer0.gtec.ges.edu.gh:9051
export CORE_PEER_TLS_ROOTCERT_FILE=$HOME/fabric/ges-network/crypto-config/peerOrganizations/gtec.ges.edu.gh/peers/peer0.gtec.ges.edu.gh/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=$HOME/fabric/ges-network/crypto-config/peerOrganizations/gtec.ges.edu.gh/users/Admin@gtec.ges.edu.gh/msp
peer channel join -b geschannel.block

echo "==> Joining NTC peer..."
export CORE_PEER_LOCALMSPID="NTCMSP"
export CORE_PEER_ADDRESS=peer0.ntc.ges.edu.gh:11051
export CORE_PEER_TLS_ROOTCERT_FILE=$HOME/fabric/ges-network/crypto-config/peerOrganizations/ntc.ges.edu.gh/peers/peer0.ntc.ges.edu.gh/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=$HOME/fabric/ges-network/crypto-config/peerOrganizations/ntc.ges.edu.gh/users/Admin@ntc.ges.edu.gh/msp
peer channel join -b geschannel.block

echo "==> Verifying channel..."
peer channel list

echo "==> Deploying chaincode..."
./deploy-chaincode.sh

echo "==> Uploading Mock data..."
./upload.sh

echo ""
echo "✅ GES Network is up and running!"
echo "   Orderer  : orderer.ges.edu.gh:7050"
echo "   GES Peer : peer0.ges.ges.edu.gh:7051"
echo "   GTEC Peer: peer0.gtec.ges.edu.gh:9051"
echo "   NTC Peer : peer0.ntc.ges.edu.gh:11051"
echo "   Channel  : geschannel"
echo ""
echo "⚠️  This script runs in a subshell — exported vars don't survive to your terminal."
echo "   Run this to set your environment:"
echo "   source setenv.sh ges"
