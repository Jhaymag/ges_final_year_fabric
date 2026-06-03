#!/bin/bash

# ── WSL guard: abort if script has Windows CRLF line endings ──────────────
if file "${BASH_SOURCE[0]}" | grep -q CRLF; then
  echo "ERROR: This script has Windows (CRLF) line endings."
  echo "Fix with: sed -i 's/\r//' setenv.sh"
  return 1
fi

ORG=$1

# Resolve crypto-config relative to this script's location.
# Works regardless of which user or directory you run from — no hardcoded $HOME.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE=$SCRIPT_DIR/crypto-config

if [ "$ORG" == "ges" ]; then
  export CORE_PEER_LOCALMSPID="GESMSP"
  export CORE_PEER_ADDRESS=peer0.ges.ges.edu.gh:7051
  export CORE_PEER_MSPCONFIGPATH=$BASE/peerOrganizations/ges.ges.edu.gh/users/Admin@ges.ges.edu.gh/msp
  export CORE_PEER_TLS_ROOTCERT_FILE=$BASE/peerOrganizations/ges.ges.edu.gh/peers/peer0.ges.ges.edu.gh/tls/ca.crt

elif [ "$ORG" == "gtec" ]; then
  export CORE_PEER_LOCALMSPID="GTECMSP"
  export CORE_PEER_ADDRESS=peer0.gtec.ges.edu.gh:9051
  export CORE_PEER_MSPCONFIGPATH=$BASE/peerOrganizations/gtec.ges.edu.gh/users/Admin@gtec.ges.edu.gh/msp
  export CORE_PEER_TLS_ROOTCERT_FILE=$BASE/peerOrganizations/gtec.ges.edu.gh/peers/peer0.gtec.ges.edu.gh/tls/ca.crt

elif [ "$ORG" == "ntc" ]; then
  export CORE_PEER_LOCALMSPID="NTCMSP"
  export CORE_PEER_ADDRESS=peer0.ntc.ges.edu.gh:11051
  export CORE_PEER_MSPCONFIGPATH=$BASE/peerOrganizations/ntc.ges.edu.gh/users/Admin@ntc.ges.edu.gh/msp
  export CORE_PEER_TLS_ROOTCERT_FILE=$BASE/peerOrganizations/ntc.ges.edu.gh/peers/peer0.ntc.ges.edu.gh/tls/ca.crt

else
  echo "Usage: source setenv.sh [ges|gtec|ntc]"
  return 1
fi

export CORE_PEER_TLS_ENABLED=true
export ORDERER_CA=$BASE/ordererOrganizations/ges.edu.gh/orderers/orderer.ges.edu.gh/msp/tlscacerts/tlsca.ges.edu.gh-cert.pem

echo "Environment set for: $ORG"
