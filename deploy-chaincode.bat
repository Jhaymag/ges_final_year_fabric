@echo off
setlocal EnableDelayedExpansion

echo ================================================
echo  GES Chaincode Deploy — Windows (Docker-based)
echo ================================================

set NETWORK_DIR=%~dp0
REM Pin the Compose project name so the generated Docker network is always
REM "ges-network_ges-network" regardless of what this folder is named/cloned as.
set COMPOSE_PROJECT_NAME=ges-network
set CC_NAME=ges-verify
set CC_VERSION=1.1
set CC_SEQUENCE=2
set CC_LABEL=%CC_NAME%_%CC_VERSION%
set CHANNEL=geschannel

REM Convert Windows path to Docker-compatible path
REM Docker Desktop on Windows maps C:\ as /host_mnt/c/ or //c/
set DOCKER_NETWORK_DIR=/network

echo.
echo [1/6] Building chaincode Docker image...
docker build --no-cache -t ges-verify:1.0 "%NETWORK_DIR%chaincode\ges-verify"
if %errorlevel% neq 0 ( echo ERROR: Docker build failed & exit /b 1 )
echo    Done.

echo.
echo [2/6] Starting CCaaS container (without CHAINCODE_ID yet)...
REM CCaaS container needs to be running so peers can connect to it during commit
REM chaincode.env will be written after package ID is known
echo CHAINCODE_ID=placeholder> "%NETWORK_DIR%chaincode.env"
docker compose -f "%NETWORK_DIR%docker-compose.yaml" up -d ges-verify-chaincode
timeout /t 3 /nobreak >nul

echo.
echo [3/6] Installing chaincode on all peers and getting package ID...

REM Run install + approval + commit inside fabric-tools container
docker run --rm ^
  --network ges-network_ges-network ^
  -v "%NETWORK_DIR%:/network" ^
  -e FABRIC_CFG_PATH=/network ^
  hyperledger/fabric-tools:2.5 ^
  bash -c "
    set -e
    CRYPTO=/network/crypto-config
    CC_NAME=%CC_NAME%
    CC_VERSION=%CC_VERSION%
    CC_SEQUENCE=%CC_SEQUENCE%
    CC_LABEL=%CC_LABEL%
    CHANNEL=%CHANNEL%
    ORDERER_CA=$CRYPTO/ordererOrganizations/ges.edu.gh/orderers/orderer.ges.edu.gh/msp/tlscacerts/tlsca.ges.edu.gh-cert.pem

    cd /network

    echo '--- Packaging chaincode ---'
    cat > metadata.json <<EOF
{\"type\":\"ccaas\",\"label\":\"${CC_LABEL}\"}
EOF
    cat > connection.json <<EOF
{\"address\":\"ges-verify-chaincode:9999\",\"dial_timeout\":\"10s\",\"tls_required\":false}
EOF
    tar cfz code.tar.gz connection.json
    tar cfz ${CC_NAME}.tar.gz metadata.json code.tar.gz
    rm -f metadata.json connection.json code.tar.gz
    echo 'Package created.'

    install_and_approve() {
      local MSPID=$1 PEER_ADDR=$2 TLS_CERT=$3 MSP_PATH=$4
      export CORE_PEER_TLS_ENABLED=true
      export CORE_PEER_LOCALMSPID=$MSPID
      export CORE_PEER_ADDRESS=$PEER_ADDR
      export CORE_PEER_TLS_ROOTCERT_FILE=$TLS_CERT
      export CORE_PEER_MSPCONFIGPATH=$MSP_PATH

      echo \"--- Installing on $MSPID ---\"
      peer lifecycle chaincode install ${CC_NAME}.tar.gz

      CC_PACKAGE_ID=$(peer lifecycle chaincode queryinstalled --output json \
        | python3 -c \"import sys,json; ccs=json.load(sys.stdin).get('installed_chaincodes',[]); [print(c['package_id']) for c in ccs if c.get('label')=='${CC_LABEL}']\" | head -1)

      echo \"Package ID: $CC_PACKAGE_ID\"

      echo \"--- Approving for $MSPID ---\"
      peer lifecycle chaincode approveformyorg \
        -o orderer.ges.edu.gh:7050 \
        --ordererTLSHostnameOverride orderer.ges.edu.gh \
        --channelID $CHANNEL --name $CC_NAME \
        --version $CC_VERSION --package-id $CC_PACKAGE_ID \
        --sequence $CC_SEQUENCE --tls --cafile $ORDERER_CA

      echo $CC_PACKAGE_ID
    }

    # Install + approve GTEC
    GTEC_TLS=$CRYPTO/peerOrganizations/gtec.ges.edu.gh/peers/peer0.gtec.ges.edu.gh/tls/ca.crt
    GTEC_MSP=$CRYPTO/peerOrganizations/gtec.ges.edu.gh/users/Admin@gtec.ges.edu.gh/msp
    PKG_ID=$(install_and_approve GTECMSP peer0.gtec.ges.edu.gh:9051 $GTEC_TLS $GTEC_MSP | tail -1)

    # Install + approve NTC
    NTC_TLS=$CRYPTO/peerOrganizations/ntc.ges.edu.gh/peers/peer0.ntc.ges.edu.gh/tls/ca.crt
    NTC_MSP=$CRYPTO/peerOrganizations/ntc.ges.edu.gh/users/Admin@ntc.ges.edu.gh/msp
    install_and_approve NTCMSP peer0.ntc.ges.edu.gh:11051 $NTC_TLS $NTC_MSP > /dev/null

    # Install + approve GES
    GES_TLS=$CRYPTO/peerOrganizations/ges.ges.edu.gh/peers/peer0.ges.ges.edu.gh/tls/ca.crt
    GES_MSP=$CRYPTO/peerOrganizations/ges.ges.edu.gh/users/Admin@ges.ges.edu.gh/msp
    install_and_approve GESMSP peer0.ges.ges.edu.gh:7051 $GES_TLS $GES_MSP > /dev/null

    # Write chaincode.env with real package ID
    echo \"CHAINCODE_ID=${PKG_ID}\" > /network/chaincode.env
    echo \"Wrote chaincode.env: CHAINCODE_ID=${PKG_ID}\"

    echo '--- Committing chaincode ---'
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

    echo 'Chaincode committed.'

    echo '--- Verifying ---'
    peer lifecycle chaincode querycommitted --channelID $CHANNEL --name $CC_NAME --tls --cafile $ORDERER_CA
  "

if %errorlevel% neq 0 ( echo ERROR: Chaincode deployment failed & exit /b 1 )

echo.
echo [4/6] Restarting CCaaS container with real CHAINCODE_ID...
docker compose -f "%NETWORK_DIR%docker-compose.yaml" up -d --no-deps ges-verify-chaincode
timeout /t 5 /nobreak >nul

echo.
echo [5/6] Verifying CCaaS is listening on port 9999...
docker exec ges-verify-chaincode sh -c "echo > /dev/tcp/localhost/9999" 2>nul
if %errorlevel% neq 0 (
  echo    Waiting a few more seconds...
  timeout /t 8 /nobreak >nul
)

echo.
echo [6/6] Running HealthCheck...
docker run --rm ^
  --network ges-network_ges-network ^
  -v "%NETWORK_DIR%:/network" ^
  -e FABRIC_CFG_PATH=/network ^
  hyperledger/fabric-tools:2.5 ^
  bash -c "
    CRYPTO=/network/crypto-config
    export CORE_PEER_TLS_ENABLED=true
    export CORE_PEER_LOCALMSPID=GESMSP
    export CORE_PEER_ADDRESS=peer0.ges.ges.edu.gh:7051
    export CORE_PEER_TLS_ROOTCERT_FILE=$CRYPTO/peerOrganizations/ges.ges.edu.gh/peers/peer0.ges.ges.edu.gh/tls/ca.crt
    export CORE_PEER_MSPCONFIGPATH=$CRYPTO/peerOrganizations/ges.ges.edu.gh/users/Admin@ges.ges.edu.gh/msp
    ORDERER_CA=$CRYPTO/ordererOrganizations/ges.edu.gh/orderers/orderer.ges.edu.gh/msp/tlscacerts/tlsca.ges.edu.gh-cert.pem
    peer chaincode query -C geschannel -n ges-verify -c '{\"function\":\"HealthCheck\",\"Args\":[]}' --tls --cafile $ORDERER_CA
  "

echo.
echo ================================================
echo  Chaincode deployed successfully!
echo  Channel  : geschannel
echo  Chaincode: ges-verify
echo  CCaaS    : ges-verify-chaincode:9999
echo ================================================
endlocal
