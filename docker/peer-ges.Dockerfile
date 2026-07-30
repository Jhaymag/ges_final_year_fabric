# Build context = repo root; Dockerfile path = docker/peer-ges.Dockerfile.
# Bakes in GES's own MSP/TLS material. Ledger data goes on a Railway Volume
# mounted at /var/hyperledger/production (runtime data, not in the image).
FROM hyperledger/fabric-peer:2.5

ENV CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/msp \
    FABRIC_LOGGING_SPEC=INFO \
    CORE_PEER_TLS_ENABLED=true \
    CORE_PEER_GOSSIP_USELEADERELECTION=true \
    CORE_PEER_GOSSIP_ORGLEADER=false \
    CORE_PEER_PROFILE_ENABLED=true \
    CORE_PEER_TLS_CERT_FILE=/etc/hyperledger/fabric/tls/server.crt \
    CORE_PEER_TLS_KEY_FILE=/etc/hyperledger/fabric/tls/server.key \
    CORE_PEER_TLS_ROOTCERT_FILE=/etc/hyperledger/fabric/tls/ca.crt \
    CORE_PEER_ID=peer0.ges.ges.edu.gh \
    CORE_PEER_ADDRESS=peer0.ges.ges.edu.gh:7051 \
    CORE_PEER_LISTENADDRESS=0.0.0.0:7051 \
    CORE_PEER_CHAINCODEADDRESS=peer0.ges.ges.edu.gh:7052 \
    CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:7052 \
    CORE_PEER_GOSSIP_BOOTSTRAP=peer0.ges.ges.edu.gh:7051 \
    CORE_PEER_GOSSIP_EXTERNALENDPOINT=peer0.ges.ges.edu.gh:7051 \
    CORE_PEER_LOCALMSPID=GESMSP

COPY crypto-config/peerOrganizations/ges.ges.edu.gh/peers/peer0.ges.ges.edu.gh/msp /etc/hyperledger/fabric/msp
COPY crypto-config/peerOrganizations/ges.ges.edu.gh/peers/peer0.ges.ges.edu.gh/tls /etc/hyperledger/fabric/tls

EXPOSE 7051
WORKDIR /opt/gopath/src/github.com/hyperledger/fabric/peer
CMD ["peer", "node", "start"]
