#!/bin/bash
set -e

CRYPTO=/network/crypto-config
ARTIFACTS=/network/channel-artifacts

echo "================================================"
echo " GES Fabric Network — Windows Setup via Docker"
echo "================================================"

# ── Step 1: Generate crypto material ──────────────────────────────────────
echo ""
echo "==> [1/5] Generating crypto materials..."
cryptogen generate --config=/network/crypto-config.yaml --output=$CRYPTO

# Fix MSP directories for each org
for org in ges.ges.edu.gh gtec.ges.edu.gh ntc.ges.edu.gh; do
  cp $CRYPTO/peerOrganizations/$org/msp/config.yaml \
     $CRYPTO/peerOrganizations/$org/peers/peer0.$org/msp/
  cp $CRYPTO/peerOrganizations/$org/users/Admin@$org/msp/signcerts/Admin@$org-cert.pem \
     $CRYPTO/peerOrganizations/$org/peers/peer0.$org/msp/admincerts/ 2>/dev/null || true
  cp $CRYPTO/peerOrganizations/$org/msp/config.yaml \
     $CRYPTO/peerOrganizations/$org/users/Admin@$org/msp/
done
echo "   Crypto materials generated."

# ── Step 2: Generate channel artifacts ────────────────────────────────────
echo ""
echo "==> [2/5] Generating channel artifacts..."
mkdir -p $ARTIFACTS

FABRIC_CFG_PATH=/network configtxgen \
  -profile GESOrdererGenesis \
  -channelID system-channel \
  -outputBlock $ARTIFACTS/genesis.block

FABRIC_CFG_PATH=/network configtxgen \
  -profile GESChannel \
  -outputCreateChannelTx $ARTIFACTS/geschannel.tx \
  -channelID geschannel

FABRIC_CFG_PATH=/network configtxgen \
  -profile GESChannel \
  -outputAnchorPeersUpdate $ARTIFACTS/GESMSPanchors.tx \
  -channelID geschannel -asOrg GESMSP

FABRIC_CFG_PATH=/network configtxgen \
  -profile GESChannel \
  -outputAnchorPeersUpdate $ARTIFACTS/GTECMSPanchors.tx \
  -channelID geschannel -asOrg GTECMSP

FABRIC_CFG_PATH=/network configtxgen \
  -profile GESChannel \
  -outputAnchorPeersUpdate $ARTIFACTS/NTCMSPanchors.tx \
  -channelID geschannel -asOrg NTCMSP

echo "   Channel artifacts generated."

# ── Step 3: Wait for orderer ───────────────────────────────────────────────
echo ""
echo "==> [3/5] Waiting for orderer to be ready..."
sleep 10

# ── Step 4: Create channel ─────────────────────────────────────────────────
echo ""
echo "==> [4/5] Creating geschannel..."

export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=GESMSP
export CORE_PEER_ADDRESS=peer0.ges.ges.edu.gh:7051
export CORE_PEER_TLS_ROOTCERT_FILE=$CRYPTO/peerOrganizations/ges.ges.edu.gh/peers/peer0.ges.ges.edu.gh/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=$CRYPTO/peerOrganizations/ges.ges.edu.gh/users/Admin@ges.ges.edu.gh/msp
export ORDERER_CA=$CRYPTO/ordererOrganizations/ges.edu.gh/orderers/orderer.ges.edu.gh/msp/tlscacerts/tlsca.ges.edu.gh-cert.pem

peer channel create \
  -o orderer.ges.edu.gh:7050 \
  -c geschannel \
  -f $ARTIFACTS/geschannel.tx \
  --tls --cafile $ORDERER_CA \
  --ordererTLSHostnameOverride orderer.ges.edu.gh \
  --outputBlock /network/geschannel.block

# ── Step 5: Join all peers ─────────────────────────────────────────────────
echo ""
echo "==> [5/5] Joining peers to channel..."

# GES peer
peer channel join -b /network/geschannel.block
echo "   GES peer joined."

# GTEC peer
export CORE_PEER_LOCALMSPID=GTECMSP
export CORE_PEER_ADDRESS=peer0.gtec.ges.edu.gh:9051
export CORE_PEER_TLS_ROOTCERT_FILE=$CRYPTO/peerOrganizations/gtec.ges.edu.gh/peers/peer0.gtec.ges.edu.gh/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=$CRYPTO/peerOrganizations/gtec.ges.edu.gh/users/Admin@gtec.ges.edu.gh/msp
peer channel join -b /network/geschannel.block
echo "   GTEC peer joined."

# NTC peer
export CORE_PEER_LOCALMSPID=NTCMSP
export CORE_PEER_ADDRESS=peer0.ntc.ges.edu.gh:11051
export CORE_PEER_TLS_ROOTCERT_FILE=$CRYPTO/peerOrganizations/ntc.ges.edu.gh/peers/peer0.ntc.ges.edu.gh/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=$CRYPTO/peerOrganizations/ntc.ges.edu.gh/users/Admin@ntc.ges.edu.gh/msp
peer channel join -b /network/geschannel.block
echo "   NTC peer joined."

echo ""
echo "================================================"
echo " Channel geschannel created and all peers joined"
echo "================================================"
