# Build context = repo root; Dockerfile path = docker/peer-gtec.Dockerfile.
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
    CORE_PEER_ID=peer0.gtec.ges.edu.gh \
    CORE_PEER_ADDRESS=peer0.gtec.ges.edu.gh:9051 \
    CORE_PEER_LISTENADDRESS=0.0.0.0:9051 \
    CORE_PEER_CHAINCODEADDRESS=peer0.gtec.ges.edu.gh:9052 \
    CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:9052 \
    CORE_PEER_GOSSIP_BOOTSTRAP=peer0.gtec.ges.edu.gh:9051 \
    CORE_PEER_GOSSIP_EXTERNALENDPOINT=peer0.gtec.ges.edu.gh:9051 \
    CORE_PEER_LOCALMSPID=GTECMSP

COPY crypto-config/peerOrganizations/gtec.ges.edu.gh/peers/peer0.gtec.ges.edu.gh/msp /etc/hyperledger/fabric/msp
COPY crypto-config/peerOrganizations/gtec.ges.edu.gh/peers/peer0.gtec.ges.edu.gh/tls /etc/hyperledger/fabric/tls

EXPOSE 9051
WORKDIR /opt/gopath/src/github.com/hyperledger/fabric/peer
CMD ["peer", "node", "start"]
