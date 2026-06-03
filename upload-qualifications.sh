#!/bin/bash

# ──────────────────────────────────────────────
# Upload Qualifications CSV to GES Blockchain
# Calls AnchorQualification for each row
# Run as: GTEC peer (has write access to GTEC PDC)
# ──────────────────────────────────────────────

set -e

# ── Check jq is installed ──
if ! command -v jq &> /dev/null; then
    echo "❌ jq is required but not installed. Run: sudo apt install jq"
    exit 1
fi

# ── Paths ──
NETWORK_DIR=/home/jhay/fabric/ges-network
CRYPTO=$NETWORK_DIR/crypto-config
CHANNEL_NAME=geschannel
CC_NAME=ges-verify
CSV_FILE=$NETWORK_DIR/data/qualifications.csv

# ── Orderer ──
ORDERER_ADDRESS=localhost:7050
ORDERER_HOST_ALIAS=orderer.ges.edu.gh
ORDERER_CA=$CRYPTO/ordererOrganizations/ges.edu.gh/orderers/orderer.ges.edu.gh/tls/ca.crt

# ── Set GTEC peer environment ──
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=GTECMSP
export CORE_PEER_ADDRESS=peer0.gtec.ges.edu.gh:9051
export CORE_PEER_TLS_ROOTCERT_FILE=$CRYPTO/peerOrganizations/gtec.ges.edu.gh/peers/peer0.gtec.ges.edu.gh/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=$CRYPTO/peerOrganizations/gtec.ges.edu.gh/users/Admin@gtec.ges.edu.gh/msp

# ── Check CSV exists ──
if [ ! -f "$CSV_FILE" ]; then
    echo "❌ CSV file not found: $CSV_FILE"
    echo "   Copy qualifications.csv to $NETWORK_DIR and try again."
    exit 1
fi

TOTAL=$(tail -n +2 "$CSV_FILE" | wc -l)
echo "===> Uploading $TOTAL qualification records to geschannel..."
echo ""

SUCCESS=0
FAILED=0
SKIPPED=0

tail -n +2 "$CSV_FILE" | while IFS=, read -r cert_id staff_name institution degree field_of_study date_conferred; do

    # Trim whitespace/carriage returns
    cert_id=$(echo "$cert_id" | tr -d '\r' | xargs)
    staff_name=$(echo "$staff_name" | tr -d '\r' | xargs)
    institution=$(echo "$institution" | tr -d '\r' | xargs)
    degree=$(echo "$degree" | tr -d '\r' | xargs)
    field_of_study=$(echo "$field_of_study" | tr -d '\r' | xargs)
    date_conferred=$(echo "$date_conferred" | tr -d '\r' | xargs)

    echo -n "  [$cert_id] $staff_name ... "

    PAYLOAD=$(jq -n \
        --arg certId       "$cert_id" \
        --arg staffName    "$staff_name" \
        --arg institution  "$institution" \
        --arg degree       "$degree" \
        --arg fieldOfStudy "$field_of_study" \
        --arg dateConferred "$date_conferred" \
        '{"function":"AnchorQualification","Args":[$certId,$staffName,$institution,$degree,$fieldOfStudy,$dateConferred]}')

    OUTPUT=$(peer chaincode invoke \
        -o $ORDERER_ADDRESS \
        --ordererTLSHostnameOverride $ORDERER_HOST_ALIAS \
        --channelID $CHANNEL_NAME \
        --name $CC_NAME \
        -c "$PAYLOAD" \
        --tls \
        --cafile $ORDERER_CA \
        --peerAddresses peer0.gtec.ges.edu.gh:9051 \
        --tlsRootCertFiles $CORE_PEER_TLS_ROOTCERT_FILE \
        2>&1)

    if echo "$OUTPUT" | grep -q "already anchored"; then
        echo "⚠ skipped (already exists)"
        SKIPPED=$((SKIPPED + 1))
    elif echo "$OUTPUT" | grep -q "Chaincode invoke successful"; then
        echo "✓ anchored"
        SUCCESS=$((SUCCESS + 1))
    else
        echo "❌ failed"
        echo "     $OUTPUT"
        FAILED=$((FAILED + 1))
    fi

    sleep 0.5  # small delay to avoid flooding the orderer

done

echo ""
echo "──────────────────────────────────────"
echo "✅ Done!  Anchored: $SUCCESS  |  Skipped: $SKIPPED  |  Failed: $FAILED"
echo "──────────────────────────────────────"
