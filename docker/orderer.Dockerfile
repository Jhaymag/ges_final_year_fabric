# Built with build context = repo root (Railway "Root Directory" should be
# left as the repo root, with this Dockerfile path set to docker/orderer.Dockerfile).
# Bakes in the orderer's MSP/TLS material and the channel genesis block,
# since Railway services don't share a filesystem the way local Docker
# Compose's bind mounts do. Ledger data still goes on a Railway Volume
# mounted at /var/hyperledger/production/orderer — that's runtime data, not
# baked into the image.
FROM hyperledger/fabric-orderer:2.5

ENV FABRIC_LOGGING_SPEC=INFO \
    ORDERER_GENERAL_LISTENADDRESS=0.0.0.0 \
    ORDERER_GENERAL_LISTENPORT=7050 \
    ORDERER_GENERAL_GENESISMETHOD=file \
    ORDERER_GENERAL_GENESISFILE=/var/hyperledger/orderer/orderer.genesis.block \
    ORDERER_GENERAL_LOCALMSPID=OrdererMSP \
    ORDERER_GENERAL_LOCALMSPDIR=/var/hyperledger/orderer/msp \
    ORDERER_GENERAL_TLS_ENABLED=true \
    ORDERER_GENERAL_TLS_PRIVATEKEY=/var/hyperledger/orderer/tls/server.key \
    ORDERER_GENERAL_TLS_CERTIFICATE=/var/hyperledger/orderer/tls/server.crt \
    ORDERER_GENERAL_TLS_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]

COPY channel-artifacts/genesis.block /var/hyperledger/orderer/orderer.genesis.block
COPY crypto-config/ordererOrganizations/ges.edu.gh/orderers/orderer.ges.edu.gh/msp /var/hyperledger/orderer/msp
COPY crypto-config/ordererOrganizations/ges.edu.gh/orderers/orderer.ges.edu.gh/tls /var/hyperledger/orderer/tls

EXPOSE 7050
WORKDIR /opt/gopath/src/github.com/hyperledger/fabric
CMD ["orderer"]
