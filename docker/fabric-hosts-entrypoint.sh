#!/bin/bash
# Railway gives every service its own internal hostname (e.g.
# ges-peer.railway.internal), but the TLS certs baked into these images (and
# every connection profile/chaincode config) were generated for the original
# local hostnames (peer0.ges.ges.edu.gh, orderer.ges.edu.gh, etc.) — those
# never match automatically across separate Railway services the way they
# did with local Docker Compose's shared network.
#
# FABRIC_HOST_MAP is a space-separated list of fabric-hostname=railway-host
# pairs, e.g.:
#   "peer0.ges.ges.edu.gh=ges-peer.railway.internal orderer.ges.edu.gh=ges-orderer.railway.internal"
# Each Railway hostname gets resolved at container startup, and a matching
# /etc/hosts entry is added for the Fabric hostname, so the rest of the
# network (and TLS verification) keeps working exactly as it did locally.
set -e

if [ -n "$FABRIC_HOST_MAP" ]; then
  for pair in $FABRIC_HOST_MAP; do
    fabric_host="${pair%%=*}"
    railway_host="${pair#*=}"
    ip=$(getent hosts "$railway_host" | awk '{print $1}' | head -1)
    if [ -n "$ip" ]; then
      echo "$ip $fabric_host" >> /etc/hosts
      echo "[fabric-hosts] mapped $fabric_host -> $railway_host ($ip)"
    else
      echo "[fabric-hosts] WARNING: could not resolve $railway_host (for $fabric_host) yet — it may not have started"
    fi
  done
fi

exec "$@"
