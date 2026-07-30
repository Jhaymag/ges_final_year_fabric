#!/bin/bash
#
# seed-blockchain.sh
# Seeds the GTEC qualification records and NTC license records onto the
# `geschannel` ledger via the peer CLI — no Node.js / fabric-gateway needed.
#
# Requirements:
#   - Run from inside the fabric-tools container (or anywhere the `peer`
#     binary and `jq` are on PATH) with crypto-config alongside setenv.sh.
#   - setenv.sh must be in the SAME directory as this script.
#
# Usage:
#   ./seed-blockchain.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHANNEL="geschannel"
CHAINCODE="ges-verify"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required (used to safely embed JSON args). Install it and re-run."
  exit 1
fi

if [ ! -f "$SCRIPT_DIR/setenv.sh" ]; then
  echo "ERROR: setenv.sh not found next to this script ($SCRIPT_DIR)."
  exit 1
fi

# ── Mock data ──────────────────────────────────────────────────────────────
# Same records as seed-blockchain.js, reshaped for peer chaincode invoke.

QUALIFICATIONS_JSON=$(cat <<'EOF'
[
  {"certId":"GTEC-2024-001","staffName":"KWAME MENSAH","institution":"University of Ghana","degree":"Bachelor of Education","fieldOfStudy":"Mathematics","dateConferred":"2020-11-14"},
  {"certId":"GTEC-2024-002","staffName":"ABENA ASANTE","institution":"Kwame Nkrumah University of Science and Technology","degree":"Bachelor of Science","fieldOfStudy":"Computer Science","dateConferred":"2019-07-20"},
  {"certId":"GTEC-2024-003","staffName":"KOFI BOATENG","institution":"University of Cape Coast","degree":"Bachelor of Arts","fieldOfStudy":"English","dateConferred":"2021-03-05"},
  {"certId":"GTEC-2024-004","staffName":"AKOSUA OFORI","institution":"University of Education Winneba","degree":"Bachelor of Education","fieldOfStudy":"Early Childhood Education","dateConferred":"2018-11-10"},
  {"certId":"GTEC-2024-005","staffName":"YAW DARKO","institution":"Ghana Institute of Management and Public Administration","degree":"Master of Business Administration","fieldOfStudy":"Educational Management","dateConferred":"2022-06-18"},
  {"certId":"GTEC-2024-006","staffName":"EFUA MENSAH","institution":"University of Ghana","degree":"Bachelor of Education","fieldOfStudy":"Science","dateConferred":"2017-11-20"},
  {"certId":"GTEC-2024-007","staffName":"KWABENA AGYEI","institution":"Kwame Nkrumah University of Science and Technology","degree":"Bachelor of Science","fieldOfStudy":"Physics","dateConferred":"2020-08-15"},
  {"certId":"GTEC-2024-008","staffName":"ADWOA AMPONSAH","institution":"University of Cape Coast","degree":"Bachelor of Education","fieldOfStudy":"Social Studies","dateConferred":"2019-11-22"},
  {"certId":"GTEC-2024-009","staffName":"FIIFI ANDOH","institution":"University of Education Winneba","degree":"Bachelor of Arts","fieldOfStudy":"French","dateConferred":"2021-07-30"},
  {"certId":"GTEC-2024-010","staffName":"AKUA FRIMPONG","institution":"University of Ghana","degree":"Bachelor of Education","fieldOfStudy":"Religious Studies","dateConferred":"2018-11-16"},
  {"certId":"GTEC-2024-011","staffName":"KOJO ASARE","institution":"University of Cape Coast","degree":"Master of Education","fieldOfStudy":"Curriculum Studies","dateConferred":"2022-11-18"},
  {"certId":"GTEC-2024-012","staffName":"AMA OWUSU","institution":"University of Education Winneba","degree":"Bachelor of Education","fieldOfStudy":"Physical Education","dateConferred":"2020-11-13"},
  {"certId":"GTEC-2024-013","staffName":"YOOFI BREW","institution":"Kwame Nkrumah University of Science and Technology","degree":"Bachelor of Science","fieldOfStudy":"Mathematics","dateConferred":"2021-11-19"},
  {"certId":"GTEC-2024-014","staffName":"ABENA NYARKO","institution":"University of Ghana","degree":"Bachelor of Arts","fieldOfStudy":"History","dateConferred":"2017-07-25"},
  {"certId":"GTEC-2024-015","staffName":"KWEKU TAWIAH","institution":"University of Cape Coast","degree":"Bachelor of Education","fieldOfStudy":"Geography","dateConferred":"2019-11-14"},
  {"certId":"GTEC-2024-016","staffName":"AFIA BONSU","institution":"University of Education Winneba","degree":"Bachelor of Education","fieldOfStudy":"Music","dateConferred":"2022-11-11"},
  {"certId":"GTEC-2024-017","staffName":"KOFI ANTWI","institution":"University of Ghana","degree":"Bachelor of Science","fieldOfStudy":"Biology","dateConferred":"2018-07-21"},
  {"certId":"GTEC-2024-018","staffName":"AKOSUA ACHEAMPONG","institution":"Kwame Nkrumah University of Science and Technology","degree":"Bachelor of Education","fieldOfStudy":"Technical Drawing","dateConferred":"2020-11-17"},
  {"certId":"GTEC-2024-019","staffName":"KWAME BOADU","institution":"University of Cape Coast","degree":"Bachelor of Arts","fieldOfStudy":"Economics","dateConferred":"2021-11-12"},
  {"certId":"GTEC-2024-020","staffName":"ADWOA SARPONG","institution":"Ghana Institute of Management and Public Administration","degree":"Master of Education","fieldOfStudy":"Educational Leadership","dateConferred":"2023-06-22"}
]
EOF
)

LICENSES_JSON=$(cat <<'EOF'
[
  {"certId":"NTC-2024-001","staffName":"KWAME MENSAH","professionalStatus":"PT","subjectSpecialism":"Mathematics","teachingLevel":"JHS","issueDate":"2021-01-10","expiryDate":"2026-01-10"},
  {"certId":"NTC-2024-002","staffName":"ABENA ASANTE","professionalStatus":"PT","subjectSpecialism":"ICT","teachingLevel":"SHS","issueDate":"2020-03-15","expiryDate":"2025-03-15"},
  {"certId":"NTC-2024-003","staffName":"KOFI BOATENG","professionalStatus":"PT","subjectSpecialism":"English Language","teachingLevel":"Primary","issueDate":"2022-05-20","expiryDate":"2027-05-20"},
  {"certId":"NTC-2024-004","staffName":"AKOSUA OFORI","professionalStatus":"NPT","subjectSpecialism":"Early Grade","teachingLevel":"Early Grade","issueDate":"2019-08-01","expiryDate":"2024-08-01"},
  {"certId":"NTC-2024-005","staffName":"YAW DARKO","professionalStatus":"PT","subjectSpecialism":"Management","teachingLevel":"SHS","issueDate":"2023-02-28","expiryDate":"2028-02-28"},
  {"certId":"NTC-2024-006","staffName":"EFUA MENSAH","professionalStatus":"PT","subjectSpecialism":"Integrated Science","teachingLevel":"Primary","issueDate":"2018-03-10","expiryDate":"2023-03-10"},
  {"certId":"NTC-2024-007","staffName":"KWABENA AGYEI","professionalStatus":"PT","subjectSpecialism":"Physics","teachingLevel":"SHS","issueDate":"2021-06-15","expiryDate":"2026-06-15"},
  {"certId":"NTC-2024-008","staffName":"ADWOA AMPONSAH","professionalStatus":"PT","subjectSpecialism":"Social Studies","teachingLevel":"JHS","issueDate":"2020-09-01","expiryDate":"2025-09-01"},
  {"certId":"NTC-2024-009","staffName":"FIIFI ANDOH","professionalStatus":"NPT","subjectSpecialism":"French","teachingLevel":"SHS","issueDate":"2022-01-20","expiryDate":"2027-01-20"},
  {"certId":"NTC-2024-010","staffName":"AKUA FRIMPONG","professionalStatus":"PT","subjectSpecialism":"Religious Studies","teachingLevel":"Primary","issueDate":"2019-04-11","expiryDate":"2024-04-11"},
  {"certId":"NTC-2024-011","staffName":"KOJO ASARE","professionalStatus":"PT","subjectSpecialism":"Curriculum Studies","teachingLevel":"SHS","issueDate":"2023-03-05","expiryDate":"2028-03-05"},
  {"certId":"NTC-2024-012","staffName":"AMA OWUSU","professionalStatus":"PT","subjectSpecialism":"Physical Education","teachingLevel":"JHS","issueDate":"2021-07-18","expiryDate":"2026-07-18"},
  {"certId":"NTC-2024-013","staffName":"YOOFI BREW","professionalStatus":"PT","subjectSpecialism":"Mathematics","teachingLevel":"SHS","issueDate":"2022-02-14","expiryDate":"2027-02-14"},
  {"certId":"NTC-2024-014","staffName":"ABENA NYARKO","professionalStatus":"NPT","subjectSpecialism":"History","teachingLevel":"JHS","issueDate":"2018-08-30","expiryDate":"2023-08-30"},
  {"certId":"NTC-2024-015","staffName":"KWEKU TAWIAH","professionalStatus":"PT","subjectSpecialism":"Geography","teachingLevel":"JHS","issueDate":"2020-10-05","expiryDate":"2025-10-05"},
  {"certId":"NTC-2024-016","staffName":"AFIA BONSU","professionalStatus":"NPT","subjectSpecialism":"Music","teachingLevel":"Primary","issueDate":"2023-01-09","expiryDate":"2028-01-09"},
  {"certId":"NTC-2024-017","staffName":"KOFI ANTWI","professionalStatus":"PT","subjectSpecialism":"Biology","teachingLevel":"SHS","issueDate":"2019-05-22","expiryDate":"2024-05-22"},
  {"certId":"NTC-2024-018","staffName":"AKOSUA ACHEAMPONG","professionalStatus":"PT","subjectSpecialism":"Technical Drawing","teachingLevel":"SHS","issueDate":"2021-11-03","expiryDate":"2026-11-03"},
  {"certId":"NTC-2024-019","staffName":"KWAME BOADU","professionalStatus":"PT","subjectSpecialism":"Economics","teachingLevel":"SHS","issueDate":"2022-08-17","expiryDate":"2027-08-17"},
  {"certId":"NTC-2024-020","staffName":"ADWOA SARPONG","professionalStatus":"PT","subjectSpecialism":"Educational Leadership","teachingLevel":"SHS","issueDate":"2024-01-15","expiryDate":"2029-01-15"}
]
EOF
)

# ── Helper: run `peer chaincode invoke` for one org/function/payload ───────
# The payload (a JSON array string) is embedded as a single string element
# of the invoke's Args array. jq -Rs turns it into a properly escaped JSON
# string literal so quoting never breaks, no matter what's inside it.
invoke_seed() {
  local org="$1"
  local fn="$2"
  local records_json="$3"

  echo ""
  echo "── Seeding via ${org^^} peer: ${fn} ──"

  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/setenv.sh" "$org"

  local escaped_payload
  escaped_payload=$(printf '%s' "$records_json" | jq -Rs .)

  local ctor_json
  ctor_json=$(jq -n --arg fn "$fn" --argjson payload "$escaped_payload" \
    '{"function":$fn,"Args":[$payload]}')

  peer chaincode invoke \
    -o localhost:7050 \
    --ordererTLSHostnameOverride orderer.ges.edu.gh \
    --tls \
    --cafile "$ORDERER_CA" \
    -C "$CHANNEL" \
    -n "$CHAINCODE" \
    --peerAddresses "$CORE_PEER_ADDRESS" \
    --tlsRootCertFiles "$CORE_PEER_TLS_ROOTCERT_FILE" \
    -c "$ctor_json"

  echo "   ✅ ${fn} committed"
}

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║          GES BLOCKCHAIN MOCK DATA SEEDER (peer CLI)             ║"
echo "╚════════════════════════════════════════════════════════════════╝"

invoke_seed "gtec" "BulkSeedGTEC" "$QUALIFICATIONS_JSON"
invoke_seed "ntc"  "BulkSeedNTC"  "$LICENSES_JSON"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    SEEDING COMPLETE ✅                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"