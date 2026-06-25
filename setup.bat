@echo off
setlocal EnableDelayedExpansion

echo ================================================
echo  GES Hyperledger Fabric Network — Windows Setup
echo ================================================
echo.

set NETWORK_DIR=%~dp0
REM Pin the Compose project name so the generated Docker network is always
REM "ges-network_ges-network" regardless of what this folder is named/cloned as.
set COMPOSE_PROJECT_NAME=ges-network

REM ── Check Docker is running ───────────────────────────────────────────────
docker info >nul 2>&1
if %errorlevel% neq 0 (
  echo ERROR: Docker Desktop is not running. Please start it and try again.
  exit /b 1
)
echo [OK] Docker Desktop is running.

REM ── Step 1: Clean previous state ──────────────────────────────────────────
echo.
echo [1/5] Cleaning up previous network state...
docker compose -f "%NETWORK_DIR%docker-compose.yaml" down -v 2>nul
if exist "%NETWORK_DIR%crypto-config"      rmdir /s /q "%NETWORK_DIR%crypto-config"
if exist "%NETWORK_DIR%channel-artifacts"  rmdir /s /q "%NETWORK_DIR%channel-artifacts"
if exist "%NETWORK_DIR%geschannel.block"   del /f /q   "%NETWORK_DIR%geschannel.block"
if exist "%NETWORK_DIR%chaincode.env"      del /f /q   "%NETWORK_DIR%chaincode.env"
if exist "%NETWORK_DIR%ledger-data"        rmdir /s /q "%NETWORK_DIR%ledger-data"
echo    Done.

REM ── Step 2: Create ledger data directories ─────────────────────────────────
echo.
echo [2/5] Creating ledger directories...
mkdir "%NETWORK_DIR%ledger-data\orderer"
mkdir "%NETWORK_DIR%ledger-data\peer-ges"
mkdir "%NETWORK_DIR%ledger-data\peer-gtec"
mkdir "%NETWORK_DIR%ledger-data\peer-ntc"
echo    Done.

REM ── Step 3: Build fabric-tools image and generate crypto + channel artifacts
echo.
echo [3/5] Building setup image and generating crypto materials...
docker build -f "%NETWORK_DIR%Dockerfile.tools" -t ges-fabric-tools:latest "%NETWORK_DIR%."
if %errorlevel% neq 0 ( echo ERROR: Failed to build tools image & exit /b 1 )
echo    Tools image built.

REM Run crypto generation only (no peers running yet)
docker run --rm ^
  -v "%NETWORK_DIR%:/network" ^
  -e FABRIC_CFG_PATH=/network ^
  --entrypoint bash ^
  ges-fabric-tools:latest ^
  -c "
    set -e
    CRYPTO=/network/crypto-config
    echo '--- Generating crypto materials ---'
    cryptogen generate --config=/network/crypto-config.yaml --output=$CRYPTO

    echo '--- Fixing MSP directories ---'
    for org in ges.ges.edu.gh gtec.ges.edu.gh ntc.ges.edu.gh; do
      cp $CRYPTO/peerOrganizations/$org/msp/config.yaml \
         $CRYPTO/peerOrganizations/$org/peers/peer0.$org/msp/
      cp $CRYPTO/peerOrganizations/$org/users/Admin@$org/msp/signcerts/Admin@$org-cert.pem \
         $CRYPTO/peerOrganizations/$org/peers/peer0.$org/msp/admincerts/ 2>/dev/null || true
      cp $CRYPTO/peerOrganizations/$org/msp/config.yaml \
         $CRYPTO/peerOrganizations/$org/users/Admin@$org/msp/
    done

    echo '--- Generating channel artifacts ---'
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
    echo 'Artifacts generated.'
  "
if %errorlevel% neq 0 ( echo ERROR: Crypto/artifact generation failed & exit /b 1 )
echo    Crypto materials and channel artifacts ready.

REM ── Step 4: Start orderer + peers (without CCaaS) ─────────────────────────
echo.
echo [4/5] Starting orderer and peer containers...
docker compose -f "%NETWORK_DIR%docker-compose.yaml" up -d ^
  orderer.ges.edu.gh ^
  peer0.ges.ges.edu.gh ^
  peer0.gtec.ges.edu.gh ^
  peer0.ntc.ges.edu.gh
if %errorlevel% neq 0 ( echo ERROR: Failed to start containers & exit /b 1 )

echo    Waiting 10 seconds for containers to be ready...
timeout /t 10 /nobreak >nul

REM Create channel and join all peers
docker run --rm ^
  --network ges-network_ges-network ^
  -v "%NETWORK_DIR%:/network" ^
  -e FABRIC_CFG_PATH=/network ^
  hyperledger/fabric-tools:2.5 ^
  bash -c "
    set -e
    CRYPTO=/network/crypto-config
    ORDERER_CA=$CRYPTO/ordererOrganizations/ges.edu.gh/orderers/orderer.ges.edu.gh/msp/tlscacerts/tlsca.ges.edu.gh-cert.pem

    export CORE_PEER_TLS_ENABLED=true
    export CORE_PEER_LOCALMSPID=GESMSP
    export CORE_PEER_ADDRESS=peer0.ges.ges.edu.gh:7051
    export CORE_PEER_TLS_ROOTCERT_FILE=$CRYPTO/peerOrganizations/ges.ges.edu.gh/peers/peer0.ges.ges.edu.gh/tls/ca.crt
    export CORE_PEER_MSPCONFIGPATH=$CRYPTO/peerOrganizations/ges.ges.edu.gh/users/Admin@ges.ges.edu.gh/msp

    echo '--- Creating geschannel ---'
    peer channel create -o orderer.ges.edu.gh:7050 -c geschannel \
      -f /network/channel-artifacts/geschannel.tx \
      --tls --cafile $ORDERER_CA \
      --ordererTLSHostnameOverride orderer.ges.edu.gh \
      --outputBlock /network/geschannel.block

    echo '--- Joining GES peer ---'
    peer channel join -b /network/geschannel.block

    echo '--- Joining GTEC peer ---'
    export CORE_PEER_LOCALMSPID=GTECMSP
    export CORE_PEER_ADDRESS=peer0.gtec.ges.edu.gh:9051
    export CORE_PEER_TLS_ROOTCERT_FILE=$CRYPTO/peerOrganizations/gtec.ges.edu.gh/peers/peer0.gtec.ges.edu.gh/tls/ca.crt
    export CORE_PEER_MSPCONFIGPATH=$CRYPTO/peerOrganizations/gtec.ges.edu.gh/users/Admin@gtec.ges.edu.gh/msp
    peer channel join -b /network/geschannel.block

    echo '--- Joining NTC peer ---'
    export CORE_PEER_LOCALMSPID=NTCMSP
    export CORE_PEER_ADDRESS=peer0.ntc.ges.edu.gh:11051
    export CORE_PEER_TLS_ROOTCERT_FILE=$CRYPTO/peerOrganizations/ntc.ges.edu.gh/peers/peer0.ntc.ges.edu.gh/tls/ca.crt
    export CORE_PEER_MSPCONFIGPATH=$CRYPTO/peerOrganizations/ntc.ges.edu.gh/users/Admin@ntc.ges.edu.gh/msp
    peer channel join -b /network/geschannel.block

    echo 'All peers joined geschannel.'

    echo '--- Updating anchor peers (required for cross-org service discovery) ---'
    export CORE_PEER_LOCALMSPID=GESMSP
    export CORE_PEER_ADDRESS=peer0.ges.ges.edu.gh:7051
    export CORE_PEER_TLS_ROOTCERT_FILE=$CRYPTO/peerOrganizations/ges.ges.edu.gh/peers/peer0.ges.ges.edu.gh/tls/ca.crt
    export CORE_PEER_MSPCONFIGPATH=$CRYPTO/peerOrganizations/ges.ges.edu.gh/users/Admin@ges.ges.edu.gh/msp
    peer channel update -o orderer.ges.edu.gh:7050 -c geschannel \
      -f /network/channel-artifacts/GESMSPanchors.tx --tls --cafile $ORDERER_CA \
      --ordererTLSHostnameOverride orderer.ges.edu.gh

    export CORE_PEER_LOCALMSPID=GTECMSP
    export CORE_PEER_ADDRESS=peer0.gtec.ges.edu.gh:9051
    export CORE_PEER_TLS_ROOTCERT_FILE=$CRYPTO/peerOrganizations/gtec.ges.edu.gh/peers/peer0.gtec.ges.edu.gh/tls/ca.crt
    export CORE_PEER_MSPCONFIGPATH=$CRYPTO/peerOrganizations/gtec.ges.edu.gh/users/Admin@gtec.ges.edu.gh/msp
    peer channel update -o orderer.ges.edu.gh:7050 -c geschannel \
      -f /network/channel-artifacts/GTECMSPanchors.tx --tls --cafile $ORDERER_CA \
      --ordererTLSHostnameOverride orderer.ges.edu.gh

    export CORE_PEER_LOCALMSPID=NTCMSP
    export CORE_PEER_ADDRESS=peer0.ntc.ges.edu.gh:11051
    export CORE_PEER_TLS_ROOTCERT_FILE=$CRYPTO/peerOrganizations/ntc.ges.edu.gh/peers/peer0.ntc.ges.edu.gh/tls/ca.crt
    export CORE_PEER_MSPCONFIGPATH=$CRYPTO/peerOrganizations/ntc.ges.edu.gh/users/Admin@ntc.ges.edu.gh/msp
    peer channel update -o orderer.ges.edu.gh:7050 -c geschannel \
      -f /network/channel-artifacts/NTCMSPanchors.tx --tls --cafile $ORDERER_CA \
      --ordererTLSHostnameOverride orderer.ges.edu.gh

    echo 'Anchor peers updated.'
  "
if %errorlevel% neq 0 ( echo ERROR: Channel creation/join failed & exit /b 1 )
echo    All peers joined geschannel and anchor peers updated.

REM ── Step 5: Deploy chaincode ───────────────────────────────────────────────
echo.
echo [5/5] Deploying ges-verify chaincode...
call "%NETWORK_DIR%deploy-chaincode.bat"
if %errorlevel% neq 0 ( echo ERROR: Chaincode deployment failed & exit /b 1 )

REM ── Done ──────────────────────────────────────────────────────────────────
echo.
echo ================================================
echo  GES Fabric Network is UP
echo.
echo  Orderer : orderer.ges.edu.gh:7050
echo  GES     : peer0.ges.ges.edu.gh:7051
echo  GTEC    : peer0.gtec.ges.edu.gh:9051
echo  NTC     : peer0.ntc.ges.edu.gh:11051
echo  Channel : geschannel
echo  Chaincode: ges-verify
echo.
echo  Now set FABRIC_CRYPTO_PATH in ges\.env
echo  to: %NETWORK_DIR%crypto-config
echo ================================================
endlocal
