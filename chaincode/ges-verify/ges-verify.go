package main

import (
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/hyperledger/fabric-chaincode-go/shim"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

const (
	pdcGTEC = "_implicit_org_GTECMSP"
	pdcNTC  = "_implicit_org_NTCMSP"
)

type SmartContract struct {
	contractapi.Contract
}

// QualificationRecord stored in GTEC private collection
type QualificationRecord struct {
	CertID        string `json:"certId"`
	StaffName     string `json:"staffName"`
	Institution   string `json:"institution"`
	Degree        string `json:"degree"`
	FieldOfStudy  string `json:"fieldOfStudy"`
	DateConferred string `json:"dateConferred"`
	Status        string `json:"status"` // 'active' | 'revoked'
	AnchoredBy    string `json:"anchoredBy"`
	Timestamp     string `json:"timestamp"`
}

// LicenseRecord stored in NTC private collection
type LicenseRecord struct {
	CertID             string `json:"certId"`
	StaffName          string `json:"staffName"`
	ProfessionalStatus string `json:"professionalStatus"` // 'PT' | 'NPT'
	SubjectSpecialism  string `json:"subjectSpecialism"`
	TeachingLevel      string `json:"teachingLevel"` // Early Grade | Primary | JHS | SHS
	IssueDate          string `json:"issueDate"`
	ExpiryDate         string `json:"expiryDate"`
	Status             string `json:"status"` // 'active' | 'revoked'
	AnchoredBy         string `json:"anchoredBy"`
	Timestamp          string `json:"timestamp"`
}

// QualVerificationResult returned by VerifyQualification
type QualVerificationResult struct {
	CertID   string `json:"certId"`
	Result   string `json:"result"` // 'match' | 'mismatch' | 'not_found' | 'revoked'
	CertType string `json:"certType"`
	Message  string `json:"message"`
}

// LicenseVerificationResult returned by VerifyLicense
type LicenseVerificationResult struct {
	CertID             string `json:"certId"`
	Result             string `json:"result"` // 'match' | 'mismatch' | 'not_found' | 'revoked' | 'expired'
	CertType           string `json:"certType"`
	ProfessionalStatus string `json:"professionalStatus"`
	ExpiryDate         string `json:"expiryDate"`
	Message            string `json:"message"`
}

// PromotionRecord on public ledger — written by GES
type PromotionRecord struct {
	PromotionID   string `json:"promotionId"`
	StaffID       string `json:"staffId"`
	OldRank       string `json:"oldRank"`
	NewRank       string `json:"newRank"`
	QualCertID    string `json:"qualCertId"`
	LicenseCertID string `json:"licenseCertId"`
	ApprovedBy    string `json:"approvedBy"`
	GazetteNumber string `json:"gazetteNumber"`
	Timestamp     string `json:"timestamp"`
}

// ──────────────────────────────────────────────
// GTEC functions
// ──────────────────────────────────────────────

// AnchorQualification stores a qualification cert in the GTEC private collection.
// Called by: GTEC peer
func (s *SmartContract) AnchorQualification(
	ctx contractapi.TransactionContextInterface,
	certId string,
	staffName string,
	institution string,
	degree string,
	fieldOfStudy string,
	dateConferred string,
) error {
	existing, err := ctx.GetStub().GetPrivateData(pdcGTEC, certId)
	if err != nil {
		return fmt.Errorf("failed to read private data: %v", err)
	}
	if existing != nil {
		return fmt.Errorf("qualification %s is already anchored", certId)
	}

	mspID, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return fmt.Errorf("failed to get MSP ID: %v", err)
	}

	record := QualificationRecord{
		CertID:        certId,
		StaffName:     staffName,
		Institution:   institution,
		Degree:        degree,
		FieldOfStudy:  fieldOfStudy,
		DateConferred: dateConferred,
		Status:        "active",
		AnchoredBy:    mspID,
		Timestamp:     time.Now().UTC().Format(time.RFC3339),
	}

	recordBytes, err := json.Marshal(record)
	if err != nil {
		return fmt.Errorf("failed to marshal record: %v", err)
	}

	return ctx.GetStub().PutPrivateData(pdcGTEC, certId, recordBytes)
}

// VerifyQualification is called by GES to verify a qualification certificate.
// GES supplies fields extracted via OCR from the uploaded certificate image.
func (s *SmartContract) VerifyQualification(
	ctx contractapi.TransactionContextInterface,
	certId string,
	staffName string,
	institution string,
	degree string,
	fieldOfStudy string,
) (*QualVerificationResult, error) {
	recordBytes, err := ctx.GetStub().GetPrivateData(pdcGTEC, certId)
	if err != nil {
		return nil, fmt.Errorf("failed to read private data: %v", err)
	}

	if recordBytes == nil {
		return &QualVerificationResult{
			CertID:   certId,
			Result:   "not_found",
			CertType: "qualification",
			Message:  fmt.Sprintf("Certificate %s not found in GTEC records", certId),
		}, nil
	}

	var record QualificationRecord
	if err := json.Unmarshal(recordBytes, &record); err != nil {
		return nil, fmt.Errorf("failed to unmarshal record: %v", err)
	}

	if record.Status == "revoked" {
		return &QualVerificationResult{
			CertID:   certId,
			Result:   "revoked",
			CertType: "qualification",
			Message:  "This qualification certificate has been revoked",
		}, nil
	}

	// Cross-check all fields
	mismatches := []string{}
	if record.StaffName != staffName {
		mismatches = append(mismatches, "name")
	}
	if record.Institution != institution {
		mismatches = append(mismatches, "institution")
	}
	if record.Degree != degree {
		mismatches = append(mismatches, "degree")
	}
	if record.FieldOfStudy != fieldOfStudy {
		mismatches = append(mismatches, "field of study")
	}

	if len(mismatches) > 0 {
		msg := "Certificate found but the following do not match: "
		for i, m := range mismatches {
			if i > 0 {
				msg += ", "
			}
			msg += m
		}
		return &QualVerificationResult{
			CertID:   certId,
			Result:   "mismatch",
			CertType: "qualification",
			Message:  msg,
		}, nil
	}

	return &QualVerificationResult{
		CertID:   certId,
		Result:   "match",
		CertType: "qualification",
		Message:  "Qualification certificate is authentic — all fields confirmed",
	}, nil
}

// GetQualification returns the full qualification record.
// Called by: GTEC or GES
func (s *SmartContract) GetQualification(
	ctx contractapi.TransactionContextInterface,
	certId string,
) (*QualificationRecord, error) {
	recordBytes, err := ctx.GetStub().GetPrivateData(pdcGTEC, certId)
	if err != nil {
		return nil, fmt.Errorf("failed to read private data: %v", err)
	}
	if recordBytes == nil {
		return nil, fmt.Errorf("qualification %s not found", certId)
	}

	var record QualificationRecord
	if err := json.Unmarshal(recordBytes, &record); err != nil {
		return nil, fmt.Errorf("failed to unmarshal record: %v", err)
	}

	return &record, nil
}

// RevokeQualification marks a qualification cert as revoked.
// Called by: GTEC only
func (s *SmartContract) RevokeQualification(
	ctx contractapi.TransactionContextInterface,
	certId string,
) error {
	recordBytes, err := ctx.GetStub().GetPrivateData(pdcGTEC, certId)
	if err != nil {
		return fmt.Errorf("failed to read private data: %v", err)
	}
	if recordBytes == nil {
		return fmt.Errorf("qualification %s not found", certId)
	}

	var record QualificationRecord
	if err := json.Unmarshal(recordBytes, &record); err != nil {
		return fmt.Errorf("failed to unmarshal record: %v", err)
	}

	if record.Status == "revoked" {
		return fmt.Errorf("qualification %s is already revoked", certId)
	}

	record.Status = "revoked"
	recordBytes, err = json.Marshal(record)
	if err != nil {
		return fmt.Errorf("failed to marshal record: %v", err)
	}

	return ctx.GetStub().PutPrivateData(pdcGTEC, certId, recordBytes)
}

// ──────────────────────────────────────────────
// NTC functions
// ──────────────────────────────────────────────

// AnchorLicense stores a teaching license in the NTC private collection.
// Called by: NTC peer
func (s *SmartContract) AnchorLicense(
	ctx contractapi.TransactionContextInterface,
	certId string,
	staffName string,
	professionalStatus string,
	subjectSpecialism string,
	teachingLevel string,
	issueDate string,
	expiryDate string,
) error {
	existing, err := ctx.GetStub().GetPrivateData(pdcNTC, certId)
	if err != nil {
		return fmt.Errorf("failed to read private data: %v", err)
	}
	if existing != nil {
		return fmt.Errorf("license %s is already anchored", certId)
	}

	mspID, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return fmt.Errorf("failed to get MSP ID: %v", err)
	}

	record := LicenseRecord{
		CertID:             certId,
		StaffName:          staffName,
		ProfessionalStatus: professionalStatus,
		SubjectSpecialism:  subjectSpecialism,
		TeachingLevel:      teachingLevel,
		IssueDate:          issueDate,
		ExpiryDate:         expiryDate,
		Status:             "active",
		AnchoredBy:         mspID,
		Timestamp:          time.Now().UTC().Format(time.RFC3339),
	}

	recordBytes, err := json.Marshal(record)
	if err != nil {
		return fmt.Errorf("failed to marshal record: %v", err)
	}

	return ctx.GetStub().PutPrivateData(pdcNTC, certId, recordBytes)
}

// VerifyLicense is called by GES to verify a teaching license.
// GES supplies fields extracted via OCR from the uploaded license image.
// Also checks expiry automatically.
func (s *SmartContract) VerifyLicense(
	ctx contractapi.TransactionContextInterface,
	certId string,
	staffName string,
	professionalStatus string,
	subjectSpecialism string,
	teachingLevel string,
	expiryDate string,
) (*LicenseVerificationResult, error) {
	recordBytes, err := ctx.GetStub().GetPrivateData(pdcNTC, certId)
	if err != nil {
		return nil, fmt.Errorf("failed to read private data: %v", err)
	}

	if recordBytes == nil {
		return &LicenseVerificationResult{
			CertID:   certId,
			Result:   "not_found",
			CertType: "license",
			Message:  fmt.Sprintf("License %s not found in NTC records", certId),
		}, nil
	}

	var record LicenseRecord
	if err := json.Unmarshal(recordBytes, &record); err != nil {
		return nil, fmt.Errorf("failed to unmarshal record: %v", err)
	}

	if record.Status == "revoked" {
		return &LicenseVerificationResult{
			CertID:             certId,
			Result:             "revoked",
			CertType:           "license",
			ProfessionalStatus: record.ProfessionalStatus,
			ExpiryDate:         record.ExpiryDate,
			Message:            "This teaching license has been revoked",
		}, nil
	}

	// Check expiry
	expiry, err := time.Parse("2006-01-02", record.ExpiryDate)
	if err == nil && time.Now().UTC().After(expiry) {
		return &LicenseVerificationResult{
			CertID:             certId,
			Result:             "expired",
			CertType:           "license",
			ProfessionalStatus: record.ProfessionalStatus,
			ExpiryDate:         record.ExpiryDate,
			Message:            fmt.Sprintf("License expired on %s — renewal required", record.ExpiryDate),
		}, nil
	}

	// Cross-check fields
	mismatches := []string{}
	if record.StaffName != staffName {
		mismatches = append(mismatches, "name")
	}
	if record.ProfessionalStatus != professionalStatus {
		mismatches = append(mismatches, "professional status")
	}
	if record.SubjectSpecialism != subjectSpecialism {
		mismatches = append(mismatches, "subject specialism")
	}
	if record.TeachingLevel != teachingLevel {
		mismatches = append(mismatches, "teaching level")
	}
	if record.ExpiryDate != expiryDate {
		mismatches = append(mismatches, "expiry date")
	}

	if len(mismatches) > 0 {
		msg := "License found but the following do not match: "
		for i, m := range mismatches {
			if i > 0 {
				msg += ", "
			}
			msg += m
		}
		return &LicenseVerificationResult{
			CertID:             certId,
			Result:             "mismatch",
			CertType:           "license",
			ProfessionalStatus: record.ProfessionalStatus,
			ExpiryDate:         record.ExpiryDate,
			Message:            msg,
		}, nil
	}

	return &LicenseVerificationResult{
		CertID:             certId,
		Result:             "match",
		CertType:           "license",
		ProfessionalStatus: record.ProfessionalStatus,
		ExpiryDate:         record.ExpiryDate,
		Message:            "Teaching license is authentic and valid — all fields confirmed",
	}, nil
}

// GetLicense returns the full license record.
// Called by: NTC or GES
func (s *SmartContract) GetLicense(
	ctx contractapi.TransactionContextInterface,
	certId string,
) (*LicenseRecord, error) {
	recordBytes, err := ctx.GetStub().GetPrivateData(pdcNTC, certId)
	if err != nil {
		return nil, fmt.Errorf("failed to read private data: %v", err)
	}
	if recordBytes == nil {
		return nil, fmt.Errorf("license %s not found", certId)
	}

	var record LicenseRecord
	if err := json.Unmarshal(recordBytes, &record); err != nil {
		return nil, fmt.Errorf("failed to unmarshal record: %v", err)
	}

	return &record, nil
}

// RevokeLicense marks a teaching license as revoked.
// Called by: NTC only
func (s *SmartContract) RevokeLicense(
	ctx contractapi.TransactionContextInterface,
	certId string,
) error {
	recordBytes, err := ctx.GetStub().GetPrivateData(pdcNTC, certId)
	if err != nil {
		return fmt.Errorf("failed to read private data: %v", err)
	}
	if recordBytes == nil {
		return fmt.Errorf("license %s not found", certId)
	}

	var record LicenseRecord
	if err := json.Unmarshal(recordBytes, &record); err != nil {
		return fmt.Errorf("failed to unmarshal record: %v", err)
	}

	if record.Status == "revoked" {
		return fmt.Errorf("license %s is already revoked", certId)
	}

	record.Status = "revoked"
	recordBytes, err = json.Marshal(record)
	if err != nil {
		return fmt.Errorf("failed to marshal record: %v", err)
	}

	return ctx.GetStub().PutPrivateData(pdcNTC, certId, recordBytes)
}

// ──────────────────────────────────────────────
// GES Promotion functions (public ledger)
// ──────────────────────────────────────────────

// RecordPromotionDecision writes a promotion decision to the public ledger.
// Called by: GES backend after verifying both qualification and license
func (s *SmartContract) RecordPromotionDecision(
	ctx contractapi.TransactionContextInterface,
	promotionId string,
	staffId string,
	oldRank string,
	newRank string,
	qualCertId string,
	licenseCertId string,
	approvedBy string,
	gazetteNumber string,
) error {
	key := "PROMOTION_" + promotionId

	existing, err := ctx.GetStub().GetState(key)
	if err != nil {
		return fmt.Errorf("failed to read from ledger: %v", err)
	}
	if existing != nil {
		return fmt.Errorf("promotion %s already recorded", promotionId)
	}

	record := PromotionRecord{
		PromotionID:   promotionId,
		StaffID:       staffId,
		OldRank:       oldRank,
		NewRank:       newRank,
		QualCertID:    qualCertId,
		LicenseCertID: licenseCertId,
		ApprovedBy:    approvedBy,
		GazetteNumber: gazetteNumber,
		Timestamp:     time.Now().UTC().Format(time.RFC3339),
	}

	recordBytes, err := json.Marshal(record)
	if err != nil {
		return fmt.Errorf("failed to marshal record: %v", err)
	}

	return ctx.GetStub().PutState(key, recordBytes)
}

// GetPromotionRecord returns a promotion record from the public ledger.
func (s *SmartContract) GetPromotionRecord(
	ctx contractapi.TransactionContextInterface,
	promotionId string,
) (*PromotionRecord, error) {
	key := "PROMOTION_" + promotionId

	recordBytes, err := ctx.GetStub().GetState(key)
	if err != nil {
		return nil, fmt.Errorf("failed to read from ledger: %v", err)
	}
	if recordBytes == nil {
		return nil, fmt.Errorf("promotion %s not found", promotionId)
	}

	var record PromotionRecord
	if err := json.Unmarshal(recordBytes, &record); err != nil {
		return nil, fmt.Errorf("failed to unmarshal record: %v", err)
	}

	return &record, nil
}

// ──────────────────────────────────────────────
// Health Check
// ──────────────────────────────────────────────

type HealthCheckResponse struct {
	Status    string `json:"status"`
	ChannelID string `json:"channelId"`
	TxID      string `json:"txId"`
	ClientMSP string `json:"clientMsp"`
	Chaincode string `json:"chaincode"`
	Timestamp string `json:"timestamp"`
}

func (s *SmartContract) HealthCheck(
	ctx contractapi.TransactionContextInterface,
) (*HealthCheckResponse, error) {
	mspID, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return nil, err
	}

	return &HealthCheckResponse{
		Status:    "UP",
		ChannelID: ctx.GetStub().GetChannelID(),
		TxID:      ctx.GetStub().GetTxID(),
		ClientMSP: mspID,
		Chaincode: "ges-verify",
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	}, nil
}

func main() {
	ccid := os.Getenv("CHAINCODE_ID")
	address := os.Getenv("CHAINCODE_ADDRESS")

	chaincode, err := contractapi.NewChaincode(&SmartContract{})
	if err != nil {
		fmt.Printf("Error creating chaincode: %v\n", err)
		return
	}

	server := &shim.ChaincodeServer{
		CCID:    ccid,
		Address: address,
		CC:      chaincode,
		TLSProps: shim.TLSProperties{
			Disabled: true,
		},
	}

	if err := server.Start(); err != nil {
		fmt.Printf("Error starting chaincode server: %v\n", err)
	}
}
