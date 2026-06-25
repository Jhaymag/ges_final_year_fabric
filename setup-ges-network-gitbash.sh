#!/bin/bash
# GES Hyperledger Fabric Network — Git Bash (Windows, Docker Desktop) setup.
#
# Use this instead of setup.bat if setup.bat fails under cmd.exe with errors
# like "Environment variable -e not defined" (a known cmd.exe caret/quoting
# bug with the multi-line `docker run ... bash -c "..."` blocks). This script
# runs the exact same steps inside Docker containers via Git Bash, so it
# needs only Docker Desktop — no WSL2, no local Fabric binaries.
#
# Run from Git Bash:  ./setup-ges-network-gitbash.sh

set -e
cd "$(dirname "$0")"

# Pin the Compose project name so the generated Docker network is always
# "ges-network_ges-network" regardless of what this folder is named/cloned as.
export COMPOSE_PROJECT_NAME=ges-network
NETWORK_DIR="$(pwd)"

echo "================================================"
echo " GES Hyperledger Fabric Network — Git Bash Setup"
echo "================================================"

echo ""
echo "[1/6] Cleaning up previous network state..."
docker compose -f docker-compose.yaml down -v 2>/dev/null || true
rm -rf crypto-config channel-artifacts geschannel.block chaincode.env ledger-data
echo "   Done."

echo ""
echo "[2/6] Creating ledger directories..."
mkdir -p ledger-data/orderer ledger-data/peer-ges ledger-data/peer-gtec ledger-data/peer-ntc
echo "   Done."

echo ""
echo "[3/6] Building fabric-tools image and generating crypto + channel artifacts..."
docker build -f Dockerfile.tools -t ges-fabric-tools:latest .

MSYS_NO_PATHCONV=1 docker run --rm \
  -v "$NETWORK_DIR:/network" \
  -e FABRIC_CFG_PATH=/network \
  --entrypoint bash \
  ges-fabric-tools:latest \
  -c '
    set -e
    CRYPTO=/network/crypto-config
    echo "--- Generating crypto materials ---"
    cryptogen generate --config=/network/crypto-config.yaml --output=$CRYPTO

    echo "--- Fixing MSP directories ---"
    for org in ges.ges.edu.gh gtec.ges.edu.gh ntc.ges.edu.gh; do
      cp $CRYPTO/peerOrganizations/$org/msp/config.yaml \
         $CRYPTO/peerOrganizations/$org/peers/peer0.$org/msp/
      cp $CRYPTO/peerOrganizations/$org/users/Admin@$org/msp/signcerts/Admin@$org-cert.pem \
         $CRYPTO/peerOrganizations/$org/peers/peer0.$org/msp/admincerts/ 2>/dev/null || true
      cp $CRYPTO/peerOrganizations/$org/msp/config.yaml \
         $CRYPTO/peerOrganizations/$org/users/Admin@$org/msp/
    done

    echo "--- Generating channel artifacts ---"
    mkdir -p /network/channel-artifacts
    FABRIC_CFG_PATH=/network configtxgen -profile GESOrdererGenesis -channelID system-channel \
      -outputBlock /network/channel-artifacts/genesis.block
    FABRIC_CFG_PATH=/network configtxgen -profile GESChannel \
      -outputCreateChannelTx /network/channel-artifacts/geschannel.tx -channelID geschannel
    FABRIC_CFG_PATH=/network configtxgen -profile GESChannel \
      -outputAnchorPeersUpdate /network/channel-artifacts/GESMSPanchors.tx \
      -channelID geschannel -asOrg GESMSP
    FABRIC_CFG_PATH=/network configtxgen -profile GESChannel \
      -outputAnchorPeersUpdate /network/channel-artifacts/GTECMSPanchors.tx \
      -channelID geschannel -asOrg GTECMSP
    FABRIC_CFG_PATH=/network configtxgen -profile GESChannel \
      -outputAnchorPeersUpdate /network/channel-artifacts/NTCMSPanchors.tx \
      -channelID geschannel -asOrg NTCMSP
    echo "Artifacts generated."
  '
echo "   Crypto materials and channel artifacts ready."

echo ""
echo "[4/6] Starting orderer and peer containers..."
docker compose -f docker-compose.yaml up -d \
  orderer.ges.edu.gh \
  peer0.ges.ges.edu.gh \
  peer0.gtec.ges.edu.gh \
  peer0.ntc.ges.edu.gh
sleep 8

echo ""
echo "[5/6] Creating channel, joining peers, and updating anchor peers..."
MSYS_NO_PATHCONV=1 docker run --rm \
  --network ges-network_ges-network \
  -v "$NETWORK_DIR:/network" \
  -e FABRIC_CFG_PATH=/network \
  hyperledger/fabric-tools:2.5 \
  bash -c '
    set -e
    CRYPTO=/network/crypto-config
    ORDERER_CA=$CRYPTO/ordererOrganizations/ges.edu.gh/orderers/orderer.ges.edu.gh/msp/tlscacerts/tlsca.ges.edu.gh-cert.pem

    join_and_anchor() {
      local MSPID=$1 PEER_ADDR=$2 TLS_CERT=$3 MSP_PATH=$4 ANCHOR_TX=$5
      export CORE_PEER_TLS_ENABLED=true
      export CORE_PEER_LOCALMSPID=$MSPID
      export CORE_PEER_ADDRESS=$PEER_ADDR
      export CORE_PEER_TLS_ROOTCERT_FILE=$TLS_CERT
      export CORE_PEER_MSPCONFIGPATH=$MSP_PATH
      echo "--- Joining $MSPID peer ---"
      peer channel join -b /network/geschannel.block
      echo "--- Updating anchor peer for $MSPID ---"
      peer channel update -o orderer.ges.edu.gh:7050 -c geschannel \
        -f $ANCHOR_TX --tls --cafile $ORDERER_CA \
        --ordererTLSHostnameOverride orderer.ges.edu.gh
    }

    export CORE_PEER_TLS_ENABLED=true
    export CORE_PEER_LOCALMSPID=GESMSP
    export CORE_PEER_ADDRESS=peer0.ges.ges.edu.gh:7051
    export CORE_PEER_TLS_ROOTCERT_FILE=$CRYPTO/peerOrganizations/ges.ges.edu.gh/peers/peer0.ges.ges.edu.gh/tls/ca.crt
    export CORE_PEER_MSPCONFIGPATH=$CRYPTO/peerOrganizations/ges.ges.edu.gh/users/Admin@ges.ges.edu.gh/msp

    echo "--- Creating geschannel ---"
    peer channel create -o orderer.ges.edu.gh:7050 -c geschannel \
      -f /network/channel-artifacts/geschannel.tx \
      --tls --cafile $ORDERER_CA \
      --ordererTLSHostnameOverride orderer.ges.edu.gh \
      --outputBlock /network/geschannel.block

    join_and_anchor GESMSP peer0.ges.ges.edu.gh:7051 \
      $CRYPTO/peerOrganizations/ges.ges.edu.gh/peers/peer0.ges.ges.edu.gh/tls/ca.crt \
      $CRYPTO/peerOrganizations/ges.ges.edu.gh/users/Admin@ges.ges.edu.gh/msp \
      /network/channel-artifacts/GESMSPanchors.tx

    join_and_anchor GTECMSP peer0.gtec.ges.edu.gh:9051 \
      $CRYPTO/peerOrganizations/gtec.ges.edu.gh/peers/peer0.gtec.ges.edu.gh/tls/ca.crt \
      $CRYPTO/peerOrganizations/gtec.ges.edu.gh/users/Admin@gtec.ges.edu.gh/msp \
      /network/channel-artifacts/GTECMSPanchors.tx

    join_and_anchor NTCMSP peer0.ntc.ges.edu.gh:11051 \
      $CRYPTO/peerOrganizations/ntc.ges.edu.gh/peers/peer0.ntc.ges.edu.gh/tls/ca.crt \
      $CRYPTO/peerOrganizations/ntc.ges.edu.gh/users/Admin@ntc.ges.edu.gh/msp \
      /network/channel-artifacts/NTCMSPanchors.tx

    echo "All peers joined geschannel and anchor peers updated."
  '

echo ""
echo "[6/6] Deploying ges-verify chaincode..."
echo "CHAINCODE_ID=placeholder" > chaincode.env
docker build --no-cache -t ges-verify:1.0 chaincode/ges-verify
docker compose -f docker-compose.yaml up -d ges-verify-chaincode
sleep 3

MSYS_NO_PATHCONV=1 docker run --rm \
  --network ges-network_ges-network \
  -v "$NETWORK_DIR:/network" \
  -e FABRIC_CFG_PATH=/network \
  hyperledger/fabric-tools:2.5 \
  bash -c '
    set -e
    CRYPTO=/network/crypto-config
    CC_NAME=ges-verify
    CC_VERSION=1.0
    CC_SEQUENCE=1
    CC_LABEL=${CC_NAME}_${CC_VERSION}
    CHANNEL=geschannel
    ORDERER_CA=$CRYPTO/ordererOrganizations/ges.edu.gh/orderers/orderer.ges.edu.gh/msp/tlscacerts/tlsca.ges.edu.gh-cert.pem

    cd /network
    echo "--- Packaging chaincode ---"
    cat > metadata.json <<EOF
{"type":"ccaas","label":"${CC_LABEL}"}
EOF
    cat > connection.json <<EOF
{"address":"ges-verify-chaincode:9999","dial_timeout":"10s","tls_required":false}
EOF
    tar cfz code.tar.gz connection.json
    tar cfz ${CC_NAME}.tar.gz metadata.json code.tar.gz
    rm -f metadata.json connection.json code.tar.gz

    install_and_approve() {
      local MSPID=$1 PEER_ADDR=$2 TLS_CERT=$3 MSP_PATH=$4
      export CORE_PEER_TLS_ENABLED=true
      export CORE_PEER_LOCALMSPID=$MSPID
      export CORE_PEER_ADDRESS=$PEER_ADDR
      export CORE_PEER_TLS_ROOTCERT_FILE=$TLS_CERT
      export CORE_PEER_MSPCONFIGPATH=$MSP_PATH

      echo "--- Installing on $MSPID ---"
      peer lifecycle chaincode install ${CC_NAME}.tar.gz || true

      CC_PACKAGE_ID=$(peer lifecycle chaincode queryinstalled | sed -n "s/^Package ID: \(.*\), Label: ${CC_LABEL}\$/\1/p" | head -1)
      echo "Package ID: $CC_PACKAGE_ID"

      echo "--- Approving for $MSPID ---"
      peer lifecycle chaincode approveformyorg \
        -o orderer.ges.edu.gh:7050 \
        --ordererTLSHostnameOverride orderer.ges.edu.gh \
        --channelID $CHANNEL --name $CC_NAME \
        --version $CC_VERSION --package-id $CC_PACKAGE_ID \
        --sequence $CC_SEQUENCE --tls --cafile $ORDERER_CA

      echo $CC_PACKAGE_ID
    }

    GTEC_TLS=$CRYPTO/peerOrganizations/gtec.ges.edu.gh/peers/peer0.gtec.ges.edu.gh/tls/ca.crt
    GTEC_MSP=$CRYPTO/peerOrganizations/gtec.ges.edu.gh/users/Admin@gtec.ges.edu.gh/msp
    PKG_ID=$(install_and_approve GTECMSP peer0.gtec.ges.edu.gh:9051 $GTEC_TLS $GTEC_MSP | tail -1)

    NTC_TLS=$CRYPTO/peerOrganizations/ntc.ges.edu.gh/peers/peer0.ntc.ges.edu.gh/tls/ca.crt
    NTC_MSP=$CRYPTO/peerOrganizations/ntc.ges.edu.gh/users/Admin@ntc.ges.edu.gh/msp
    install_and_approve NTCMSP peer0.ntc.ges.edu.gh:11051 $NTC_TLS $NTC_MSP > /dev/null

    GES_TLS=$CRYPTO/peerOrganizations/ges.ges.edu.gh/peers/peer0.ges.ges.edu.gh/tls/ca.crt
    GES_MSP=$CRYPTO/peerOrganizations/ges.ges.edu.gh/users/Admin@ges.ges.edu.gh/msp
    install_and_approve GESMSP peer0.ges.ges.edu.gh:7051 $GES_TLS $GES_MSP > /dev/null

    echo "CHAINCODE_ID=${PKG_ID}" > /network/chaincode.env
    echo "Wrote chaincode.env: CHAINCODE_ID=${PKG_ID}"

    echo "--- Committing chaincode ---"
    export CORE_PEER_TLS_ENABLED=true
    export CORE_PEER_LOCALMSPID=GESMSP
    export CORE_PEER_ADDRESS=peer0.ges.ges.edu.gh:7051
    export CORE_PEER_TLS_ROOTCERT_FILE=$GES_TLS
    export CORE_PEER_MSPCONFIGPATH=$GES_MSP

    peer lifecycle chaincode commit \
      -o orderer.ges.edu.gh:7050 \
      --ordererTLSHostnameOverride orderer.ges.edu.gh \
      --channelID $CHANNEL --name $CC_NAME \
      --version $CC_VERSION --sequence $CC_SEQUENCE \
      --tls --cafile $ORDERER_CA \
      --peerAddresses peer0.gtec.ges.edu.gh:9051 --tlsRootCertFiles $GTEC_TLS \
      --peerAddresses peer0.ntc.ges.edu.gh:11051  --tlsRootCertFiles $NTC_TLS \
      --peerAddresses peer0.ges.ges.edu.gh:7051   --tlsRootCertFiles $GES_TLS

    echo "Chaincode committed."
    peer lifecycle chaincode querycommitted --channelID $CHANNEL --name $CC_NAME --tls --cafile $ORDERER_CA
  '

docker compose -f docker-compose.yaml up -d --no-deps ges-verify-chaincode
sleep 5

echo ""
echo "================================================"
echo " GES Fabric Network is UP"
echo ""
echo " Orderer  : orderer.ges.edu.gh:7050"
echo " GES      : peer0.ges.ges.edu.gh:7051"
echo " GTEC     : peer0.gtec.ges.edu.gh:9051"
echo " NTC      : peer0.ntc.ges.edu.gh:11051"
echo " Channel  : geschannel"
echo " Chaincode: ges-verify"
echo ""
echo " Now set FABRIC_CRYPTO_PATH in ges/.env to:"
echo " $NETWORK_DIR/crypto-config"
echo "================================================"
