#!/usr/bin/env node

/**
 * seed-blockchain.js
 * Run from ~/fabric/ges-network:
 *   node seed-blockchain.js
 */

const grpc = require('@grpc/grpc-js');
const { connect, hash, signers } = require('@hyperledger/fabric-gateway');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const CRYPTO_ROOT  = path.resolve(__dirname, 'crypto-config');
const CHANNEL      = 'geschannel';
const CHAINCODE    = 'ges-verify';

// ── Fabric connection helpers ─────────────────────────────────────────────────

function makeCreds(org) {
  const orgs = {
    ges:  { msp: 'GESMSP',  peer: 'localhost:7051',  host: 'peer0.ges.ges.edu.gh',  domain: 'ges.ges.edu.gh' },
    gtec: { msp: 'GTECMSP', peer: 'localhost:9051',  host: 'peer0.gtec.ges.edu.gh', domain: 'gtec.ges.edu.gh' },
    ntc:  { msp: 'NTCMSP',  peer: 'localhost:11051', host: 'peer0.ntc.ges.edu.gh',  domain: 'ntc.ges.edu.gh' },
  };
  const o = orgs[org];

  const tlsCert = fs.readFileSync(
    path.join(CRYPTO_ROOT, `peerOrganizations/${o.domain}/peers/peer0.${o.domain}/tls/ca.crt`)
  );
  const certDir = path.join(CRYPTO_ROOT, `peerOrganizations/${o.domain}/users/Admin@${o.domain}/msp/signcerts`);
  const cert = fs.readFileSync(path.join(certDir, fs.readdirSync(certDir)[0])).toString();
  const keyDir = path.join(CRYPTO_ROOT, `peerOrganizations/${o.domain}/users/Admin@${o.domain}/msp/keystore`);
  const key = fs.readFileSync(path.join(keyDir, fs.readdirSync(keyDir)[0])).toString();

  const client = new grpc.Client(o.peer, grpc.credentials.createSsl(tlsCert), {
    'grpc.ssl_target_name_override': o.host,
  });
  const gateway = connect({
    client,
    identity: { mspId: o.msp, credentials: Buffer.from(cert) },
    signer: signers.newPrivateKeySigner(crypto.createPrivateKey(key)),
    hash: hash.sha256,
  });
  return { client, gateway };
}

async function invoke(contract, fnName, args) {
  const resultBytes = await contract.submitTransaction(fnName, ...args.map(String));
  if (!resultBytes || resultBytes.length === 0) return null;
  return JSON.parse(Buffer.from(resultBytes).toString());
}

async function evaluate(contract, fnName, args) {
  const resultBytes = await contract.evaluateTransaction(fnName, ...args.map(String));
  if (!resultBytes || resultBytes.length === 0) return null;
  return JSON.parse(Buffer.from(resultBytes).toString());
}

// ── Mock data ─────────────────────────────────────────────────────────────────

const QUALIFICATIONS = [
  { certId: 'GTEC-2024-001', staffName: 'KWAME MENSAH',        institution: 'University of Ghana',                                      degree: 'Bachelor of Education',          fieldOfStudy: 'Mathematics',           dateConferred: '2020-11-14' },
  { certId: 'GTEC-2024-002', staffName: 'ABENA ASANTE',        institution: 'Kwame Nkrumah University of Science and Technology',       degree: 'Bachelor of Science',            fieldOfStudy: 'Computer Science',      dateConferred: '2019-07-20' },
  { certId: 'GTEC-2024-003', staffName: 'KOFI BOATENG',        institution: 'University of Cape Coast',                                 degree: 'Bachelor of Arts',               fieldOfStudy: 'English',               dateConferred: '2021-03-05' },
  { certId: 'GTEC-2024-004', staffName: 'AKOSUA OFORI',        institution: 'University of Education Winneba',                          degree: 'Bachelor of Education',          fieldOfStudy: 'Early Childhood Education', dateConferred: '2018-11-10' },
  { certId: 'GTEC-2024-005', staffName: 'YAW DARKO',           institution: 'Ghana Institute of Management and Public Administration',  degree: 'Master of Business Administration', fieldOfStudy: 'Educational Management', dateConferred: '2022-06-18' },
  { certId: 'GTEC-2024-006', staffName: 'EFUA MENSAH',         institution: 'University of Ghana',                                      degree: 'Bachelor of Education',          fieldOfStudy: 'Science',               dateConferred: '2017-11-20' },
  { certId: 'GTEC-2024-007', staffName: 'KWABENA AGYEI',       institution: 'Kwame Nkrumah University of Science and Technology',       degree: 'Bachelor of Science',            fieldOfStudy: 'Physics',               dateConferred: '2020-08-15' },
  { certId: 'GTEC-2024-008', staffName: 'ADWOA AMPONSAH',      institution: 'University of Cape Coast',                                 degree: 'Bachelor of Education',          fieldOfStudy: 'Social Studies',        dateConferred: '2019-11-22' },
  { certId: 'GTEC-2024-009', staffName: 'FIIFI ANDOH',         institution: 'University of Education Winneba',                          degree: 'Bachelor of Arts',               fieldOfStudy: 'French',                dateConferred: '2021-07-30' },
  { certId: 'GTEC-2024-010', staffName: 'AKUA FRIMPONG',       institution: 'University of Ghana',                                      degree: 'Bachelor of Education',          fieldOfStudy: 'Religious Studies',     dateConferred: '2018-11-16' },
  { certId: 'GTEC-2024-011', staffName: 'KOJO ASARE',          institution: 'University of Cape Coast',                                 degree: 'Master of Education',            fieldOfStudy: 'Curriculum Studies',    dateConferred: '2022-11-18' },
  { certId: 'GTEC-2024-012', staffName: 'AMA OWUSU',           institution: 'University of Education Winneba',                          degree: 'Bachelor of Education',          fieldOfStudy: 'Physical Education',    dateConferred: '2020-11-13' },
  { certId: 'GTEC-2024-013', staffName: 'YOOFI BREW',          institution: 'Kwame Nkrumah University of Science and Technology',       degree: 'Bachelor of Science',            fieldOfStudy: 'Mathematics',           dateConferred: '2021-11-19' },
  { certId: 'GTEC-2024-014', staffName: 'ABENA NYARKO',        institution: 'University of Ghana',                                      degree: 'Bachelor of Arts',               fieldOfStudy: 'History',               dateConferred: '2017-07-25' },
  { certId: 'GTEC-2024-015', staffName: 'KWEKU TAWIAH',        institution: 'University of Cape Coast',                                 degree: 'Bachelor of Education',          fieldOfStudy: 'Geography',             dateConferred: '2019-11-14' },
  { certId: 'GTEC-2024-016', staffName: 'AFIA BONSU',          institution: 'University of Education Winneba',                          degree: 'Bachelor of Education',          fieldOfStudy: 'Music',                 dateConferred: '2022-11-11' },
  { certId: 'GTEC-2024-017', staffName: 'KOFI ANTWI',          institution: 'University of Ghana',                                      degree: 'Bachelor of Science',            fieldOfStudy: 'Biology',               dateConferred: '2018-07-21' },
  { certId: 'GTEC-2024-018', staffName: 'AKOSUA ACHEAMPONG',   institution: 'Kwame Nkrumah University of Science and Technology',       degree: 'Bachelor of Education',          fieldOfStudy: 'Technical Drawing',     dateConferred: '2020-11-17' },
  { certId: 'GTEC-2024-019', staffName: 'KWAME BOADU',         institution: 'University of Cape Coast',                                 degree: 'Bachelor of Arts',               fieldOfStudy: 'Economics',             dateConferred: '2021-11-12' },
  { certId: 'GTEC-2024-020', staffName: 'ADWOA SARPONG',       institution: 'Ghana Institute of Management and Public Administration',  degree: 'Master of Education',            fieldOfStudy: 'Educational Leadership', dateConferred: '2023-06-22' },
];

const LICENSES = [
  { certId: 'NTC-2024-001', staffName: 'KWAME MENSAH',       professionalStatus: 'PT',  subjectSpecialism: 'Mathematics',          teachingLevel: 'JHS',        issueDate: '2021-01-10', expiryDate: '2026-01-10' },
  { certId: 'NTC-2024-002', staffName: 'ABENA ASANTE',       professionalStatus: 'PT',  subjectSpecialism: 'ICT',                  teachingLevel: 'SHS',        issueDate: '2020-03-15', expiryDate: '2025-03-15' },
  { certId: 'NTC-2024-003', staffName: 'KOFI BOATENG',       professionalStatus: 'PT',  subjectSpecialism: 'English Language',     teachingLevel: 'Primary',    issueDate: '2022-05-20', expiryDate: '2027-05-20' },
  { certId: 'NTC-2024-004', staffName: 'AKOSUA OFORI',       professionalStatus: 'NPT', subjectSpecialism: 'Early Grade',          teachingLevel: 'Early Grade',issueDate: '2019-08-01', expiryDate: '2024-08-01' },
  { certId: 'NTC-2024-005', staffName: 'YAW DARKO',          professionalStatus: 'PT',  subjectSpecialism: 'Management',           teachingLevel: 'SHS',        issueDate: '2023-02-28', expiryDate: '2028-02-28' },
  { certId: 'NTC-2024-006', staffName: 'EFUA MENSAH',        professionalStatus: 'PT',  subjectSpecialism: 'Integrated Science',   teachingLevel: 'Primary',    issueDate: '2018-03-10', expiryDate: '2023-03-10' },
  { certId: 'NTC-2024-007', staffName: 'KWABENA AGYEI',      professionalStatus: 'PT',  subjectSpecialism: 'Physics',              teachingLevel: 'SHS',        issueDate: '2021-06-15', expiryDate: '2026-06-15' },
  { certId: 'NTC-2024-008', staffName: 'ADWOA AMPONSAH',     professionalStatus: 'PT',  subjectSpecialism: 'Social Studies',       teachingLevel: 'JHS',        issueDate: '2020-09-01', expiryDate: '2025-09-01' },
  { certId: 'NTC-2024-009', staffName: 'FIIFI ANDOH',        professionalStatus: 'NPT', subjectSpecialism: 'French',               teachingLevel: 'SHS',        issueDate: '2022-01-20', expiryDate: '2027-01-20' },
  { certId: 'NTC-2024-010', staffName: 'AKUA FRIMPONG',      professionalStatus: 'PT',  subjectSpecialism: 'Religious Studies',    teachingLevel: 'Primary',    issueDate: '2019-04-11', expiryDate: '2024-04-11' },
  { certId: 'NTC-2024-011', staffName: 'KOJO ASARE',         professionalStatus: 'PT',  subjectSpecialism: 'Curriculum Studies',   teachingLevel: 'SHS',        issueDate: '2023-03-05', expiryDate: '2028-03-05' },
  { certId: 'NTC-2024-012', staffName: 'AMA OWUSU',          professionalStatus: 'PT',  subjectSpecialism: 'Physical Education',   teachingLevel: 'JHS',        issueDate: '2021-07-18', expiryDate: '2026-07-18' },
  { certId: 'NTC-2024-013', staffName: 'YOOFI BREW',         professionalStatus: 'PT',  subjectSpecialism: 'Mathematics',          teachingLevel: 'SHS',        issueDate: '2022-02-14', expiryDate: '2027-02-14' },
  { certId: 'NTC-2024-014', staffName: 'ABENA NYARKO',       professionalStatus: 'NPT', subjectSpecialism: 'History',              teachingLevel: 'JHS',        issueDate: '2018-08-30', expiryDate: '2023-08-30' },
  { certId: 'NTC-2024-015', staffName: 'KWEKU TAWIAH',       professionalStatus: 'PT',  subjectSpecialism: 'Geography',            teachingLevel: 'JHS',        issueDate: '2020-10-05', expiryDate: '2025-10-05' },
  { certId: 'NTC-2024-016', staffName: 'AFIA BONSU',         professionalStatus: 'NPT', subjectSpecialism: 'Music',                teachingLevel: 'Primary',    issueDate: '2023-01-09', expiryDate: '2028-01-09' },
  { certId: 'NTC-2024-017', staffName: 'KOFI ANTWI',         professionalStatus: 'PT',  subjectSpecialism: 'Biology',              teachingLevel: 'SHS',        issueDate: '2019-05-22', expiryDate: '2024-05-22' },
  { certId: 'NTC-2024-018', staffName: 'AKOSUA ACHEAMPONG',  professionalStatus: 'PT',  subjectSpecialism: 'Technical Drawing',    teachingLevel: 'SHS',        issueDate: '2021-11-03', expiryDate: '2026-11-03' },
  { certId: 'NTC-2024-019', staffName: 'KWAME BOADU',        professionalStatus: 'PT',  subjectSpecialism: 'Economics',            teachingLevel: 'SHS',        issueDate: '2022-08-17', expiryDate: '2027-08-17' },
  { certId: 'NTC-2024-020', staffName: 'ADWOA SARPONG',      professionalStatus: 'PT',  subjectSpecialism: 'Educational Leadership', teachingLevel: 'SHS',      issueDate: '2024-01-15', expiryDate: '2029-01-15' },
];

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  console.log('\n╔════════════════════════════════════════════════════════════════╗');
  console.log('║          GES BLOCKCHAIN MOCK DATA SEEDER                       ║');
  console.log('╚════════════════════════════════════════════════════════════════╝\n');

  // ── Seed GTEC qualifications ──────────────────────────────────────────
  // Must submit through GTEC peer — only GTEC can endorse writes to _implicit_org_GTECMSP
  console.log('📤 Seeding GTEC qualifications...');
  const gtec = makeCreds('gtec');
  try {
    const contract = gtec.gateway.getNetwork(CHANNEL).getContract(CHAINCODE);
    await invoke(contract, 'BulkSeedGTEC', [JSON.stringify(QUALIFICATIONS)]);
    console.log('   ✅ BulkSeedGTEC committed\n');
    const quals = await evaluate(contract, 'ListQualifications', []);
    console.log(`   ✓ ${(quals || []).length} qualification records on ledger:`);
    for (const r of quals || []) {
      console.log(`     [${r.certId}] ${r.staffName} — ${r.degree} (${r.dateConferred})`);
    }
  } finally {
    gtec.gateway.close(); gtec.client.close();
  }

  // ── Seed NTC licenses ─────────────────────────────────────────────────
  // Must submit through NTC peer — only NTC can endorse writes to _implicit_org_NTCMSP
  console.log('\n📤 Seeding NTC licenses...');
  const ntc = makeCreds('ntc');
  try {
    const contract = ntc.gateway.getNetwork(CHANNEL).getContract(CHAINCODE);
    await invoke(contract, 'BulkSeedNTC', [JSON.stringify(LICENSES)]);
    console.log('   ✅ BulkSeedNTC committed\n');
    const licenses = await evaluate(contract, 'ListLicenses', []);
    console.log(`   ✓ ${(licenses || []).length} license records on ledger:`);
    for (const r of licenses || []) {
      console.log(`     [${r.certId}] ${r.staffName} — ${r.professionalStatus} | ${r.subjectSpecialism} | expires ${r.expiryDate}`);
    }
  } finally {
    ntc.gateway.close(); ntc.client.close();
  }

  console.log('\n╔════════════════════════════════════════════════════════════════╗');
  console.log('║                    SEEDING COMPLETE ✅                         ║');
  console.log('╚════════════════════════════════════════════════════════════════╝\n');
}

main().catch(err => {
  console.error('\n❌ Seeding failed:', err.message || err);
  process.exit(1);
});
