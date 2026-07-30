package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/hyperledger/fabric-chaincode-go/shim"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

const (
	pdcGTEC = "_implicit_org_GTECMSP"
	pdcNTC  = "_implicit_org_NTCMSP"

	// Composite key object types for range queries
	docIndexKey   = "STAFF_DOC"
	promoIndexKey = "STAFF_PROMO"
)

// ─── Structs ──────────────────────────────────────────────────────────────────

type SmartContract struct {
	contractapi.Contract
}

// QualificationRecord stored in GTEC implicit private data collection.
type QualificationRecord struct {
	CertID        string `json:"certId"`
	StaffName     string `json:"staffName"`
	Institution   string `json:"institution"`
	Degree        string `json:"degree"`
	FieldOfStudy  string `json:"fieldOfStudy"`
	DateConferred string `json:"dateConferred"`
	Status        string `json:"status"` // active | revoked
	AnchoredBy    string `json:"anchoredBy"`
	UpdatedBy     string `json:"updatedBy,omitempty" metadata:",optional"`
	Timestamp     string `json:"timestamp"`
	UpdatedAt     string `json:"updatedAt,omitempty" metadata:",optional"`
}

// LicenseRecord stored in NTC implicit private data collection.
type LicenseRecord struct {
	CertID             string `json:"certId"`
	StaffName          string `json:"staffName"`
	ProfessionalStatus string `json:"professionalStatus"` // PT | NPT
	SubjectSpecialism  string `json:"subjectSpecialism"`
	TeachingLevel      string `json:"teachingLevel"` // Early Grade | Primary | JHS | SHS
	IssueDate          string `json:"issueDate"`
	ExpiryDate         string `json:"expiryDate"`
	Status             string `json:"status"` // active | revoked
	AnchoredBy         string `json:"anchoredBy"`
	UpdatedBy          string `json:"updatedBy,omitempty" metadata:",optional"`
	Timestamp          string `json:"timestamp"`
	UpdatedAt          string `json:"updatedAt,omitempty" metadata:",optional"`
}

// DocumentRecord on the public ledger — the tamper-evident anchor for a teacher's
// uploaded document hash. Written the moment a teacher uploads a document.
type DocumentRecord struct {
	DocumentHash string `json:"documentHash"`
	StaffID      string `json:"staffId"`
	FileName     string `json:"fileName"`
	Revoked      bool   `json:"revoked"`
	RevokeReason string `json:"revokeReason,omitempty" metadata:",optional"`
	AnchoredBy   string `json:"anchoredBy"`
	Timestamp    string `json:"timestamp"`
}

// PromotionRecord on the public ledger — written by GES after HR approval.
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

// Verification result types

type QualVerificationResult struct {
	CertID   string `json:"certId"`
	Result   string `json:"result"` // match | mismatch | not_found | revoked
	CertType string `json:"certType"`
	Message  string `json:"message"`
}

type LicenseVerificationResult struct {
	CertID             string `json:"certId"`
	Result             string `json:"result"` // match | mismatch | not_found | revoked | expired
	CertType           string `json:"certType"`
	ProfessionalStatus string `json:"professionalStatus"`
	ExpiryDate         string `json:"expiryDate"`
	Message            string `json:"message"`
}

type DocumentVerificationResult struct {
	DocumentHash string `json:"documentHash"`
	Result       string `json:"result"` // match | not_found | revoked
	StaffID      string `json:"staffId"`
	Timestamp    string `json:"timestamp"`
	Message      string `json:"message"`
}

type TeacherSummary struct {
	StaffID    string           `json:"staffId"`
	Documents  []DocumentRecord `json:"documents"`
	Promotions []PromotionRecord `json:"promotions"`
	Timestamp  string           `json:"timestamp"`
}

type HealthCheckResponse struct {
	Status    string `json:"status"`
	ChannelID string `json:"channelId"`
	TxID      string `json:"txId"`
	ClientMSP string `json:"clientMsp"`
	Chaincode string `json:"chaincode"`
	Timestamp string `json:"timestamp"`
}

// QualificationInput is used for bulk seeding operations.
type QualificationInput struct {
	CertID        string `json:"certId"`
	StaffName     string `json:"staffName"`
	Institution   string `json:"institution"`
	Degree        string `json:"degree"`
	FieldOfStudy  string `json:"fieldOfStudy"`
	DateConferred string `json:"dateConferred"`
}

// LicenseInput is used for bulk seeding operations.
type LicenseInput struct {
	CertID             string `json:"certId"`
	StaffName          string `json:"staffName"`
	ProfessionalStatus string `json:"professionalStatus"`
	SubjectSpecialism  string `json:"subjectSpecialism"`
	TeachingLevel      string `json:"teachingLevel"`
	IssueDate          string `json:"issueDate"`
	ExpiryDate         string `json:"expiryDate"`
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

// flexMatch normalises both strings (upper-case, collapse punctuation and
// whitespace) before comparing. Returns true when either string contains the
// other, so OCR text like "BACHELOR OF EDUCATION IN MATHEMATICS" will still
// match a record field of "BACHELOR OF EDUCATION". An empty supplied value
// means the OCR did not extract this field — treated as "don't care" (true).
func flexMatch(recorded, supplied string) bool {
	if supplied == "" {
		return true
	}
	norm := func(s string) string {
		s = strings.ToUpper(strings.TrimSpace(s))
		for _, ch := range []string{",", ".", "-", "/"} {
			s = strings.ReplaceAll(s, ch, " ")
		}
		for strings.Contains(s, "  ") {
			s = strings.ReplaceAll(s, "  ", " ")
		}
		return s
	}
	r := norm(recorded)
	su := norm(supplied)
	return r == su || strings.Contains(r, su) || strings.Contains(su, r)
}

// ─── GTEC: Qualification functions ────────────────────────────────────────────

// AnchorQualification stores a qualification cert in the GTEC private collection.
// Fails if already anchored — use UpdateQualification for renewals.
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

// UpdateQualification replaces an existing qualification (e.g. for degree renewals).
// GTEC org only — only they hold the private collection.
func (s *SmartContract) UpdateQualification(
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
	if existing == nil {
		return fmt.Errorf("qualification %s not found — use AnchorQualification to create it", certId)
	}

	var old QualificationRecord
	if err := json.Unmarshal(existing, &old); err != nil {
		return fmt.Errorf("failed to unmarshal existing record: %v", err)
	}
	if old.Status == "revoked" {
		return fmt.Errorf("qualification %s is revoked and cannot be updated", certId)
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
		AnchoredBy:    old.AnchoredBy,
		UpdatedBy:     mspID,
		Timestamp:     old.Timestamp,
		UpdatedAt:     time.Now().UTC().Format(time.RFC3339),
	}

	recordBytes, err := json.Marshal(record)
	if err != nil {
		return fmt.Errorf("failed to marshal record: %v", err)
	}

	return ctx.GetStub().PutPrivateData(pdcGTEC, certId, recordBytes)
}

// VerifyQualification checks OCR-extracted fields against the GTEC record.
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

	// Use flexible matching: case-insensitive, partial-match, punctuation-agnostic.
	// Empty OCR fields (supplied="") are skipped — OCR may not extract all fields.
	mismatches := []string{}
	if !flexMatch(record.StaffName, staffName) {
		mismatches = append(mismatches, "name")
	}
	if !flexMatch(record.Institution, institution) {
		mismatches = append(mismatches, "institution")
	}
	if !flexMatch(record.Degree, degree) {
		mismatches = append(mismatches, "degree")
	}
	if !flexMatch(record.FieldOfStudy, fieldOfStudy) {
		mismatches = append(mismatches, "field of study")
	}

	if len(mismatches) > 0 {
		return &QualVerificationResult{
			CertID:   certId,
			Result:   "mismatch",
			CertType: "qualification",
			Message:  "Certificate found but the following do not match: " + strings.Join(mismatches, ", "),
		}, nil
	}

	return &QualVerificationResult{
		CertID:   certId,
		Result:   "match",
		CertType: "qualification",
		Message:  "Qualification certificate is authentic — all fields confirmed",
	}, nil
}

// GetQualification returns the full qualification record from GTEC's collection.
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

// RevokeQualification marks a qualification as revoked. Called by GTEC only.
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
	record.UpdatedAt = time.Now().UTC().Format(time.RFC3339)

	mspID, _ := ctx.GetClientIdentity().GetMSPID()
	record.UpdatedBy = mspID

	recordBytes, err = json.Marshal(record)
	if err != nil {
		return fmt.Errorf("failed to marshal record: %v", err)
	}

	return ctx.GetStub().PutPrivateData(pdcGTEC, certId, recordBytes)
}

// SeedGTECRecord upserts a qualification record into the GTEC private collection.
// Unlike AnchorQualification there is no duplicate check — safe to call
// repeatedly during demo seeding. CertID convention: QUAL_<staffId>.
func (s *SmartContract) SeedGTECRecord(
	ctx contractapi.TransactionContextInterface,
	certId string,
	staffName string,
	institution string,
	degree string,
	fieldOfStudy string,
	dateConferred string,
) error {
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

	rb, err := json.Marshal(record)
	if err != nil {
		return fmt.Errorf("failed to marshal record: %v", err)
	}
	return ctx.GetStub().PutPrivateData(pdcGTEC, certId, rb)
}

// BulkSeedGTEC seeds multiple GTEC qualification records in one transaction.
// recordsJSON is a JSON array where each element matches QualificationInput.
// All records are upserted — existing entries are silently overwritten.
//
// Example payload:
//
//	[{"certId":"QUAL_GES001","staffName":"KWAME ASANTE BOATENG",
//	  "institution":"UNIVERSITY OF EDUCATION WINNEBA",
//	  "degree":"BACHELOR OF EDUCATION","fieldOfStudy":"MATHEMATICS",
//	  "dateConferred":"2018-07-15"}, ...]
func (s *SmartContract) BulkSeedGTEC(
	ctx contractapi.TransactionContextInterface,
	recordsJSON string,
) error {
	var inputs []QualificationInput
	if err := json.Unmarshal([]byte(recordsJSON), &inputs); err != nil {
		return fmt.Errorf("invalid JSON: %v", err)
	}

	mspID, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return fmt.Errorf("failed to get MSP ID: %v", err)
	}

	ts := time.Now().UTC().Format(time.RFC3339)

	for _, inp := range inputs {
		record := QualificationRecord{
			CertID:        inp.CertID,
			StaffName:     inp.StaffName,
			Institution:   inp.Institution,
			Degree:        inp.Degree,
			FieldOfStudy:  inp.FieldOfStudy,
			DateConferred: inp.DateConferred,
			Status:        "active",
			AnchoredBy:    mspID,
			Timestamp:     ts,
		}
		rb, err := json.Marshal(record)
		if err != nil {
			return fmt.Errorf("failed to marshal record %s: %v", inp.CertID, err)
		}
		if err := ctx.GetStub().PutPrivateData(pdcGTEC, inp.CertID, rb); err != nil {
			return fmt.Errorf("failed to write record %s: %v", inp.CertID, err)
		}
	}
	return nil
}

// ListQualifications returns all qualification records from the GTEC private
// collection. Must be endorsed by a GTEC peer (only they hold the collection).
func (s *SmartContract) ListQualifications(
	ctx contractapi.TransactionContextInterface,
) ([]*QualificationRecord, error) {
	iterator, err := ctx.GetStub().GetPrivateDataByRange(pdcGTEC, "", "")
	if err != nil {
		return nil, fmt.Errorf("failed to query private data: %v", err)
	}
	defer iterator.Close()

	var records []*QualificationRecord
	for iterator.HasNext() {
		item, err := iterator.Next()
		if err != nil {
			return nil, fmt.Errorf("iteration error: %v", err)
		}
		var rec QualificationRecord
		if err := json.Unmarshal(item.Value, &rec); err != nil {
			continue
		}
		records = append(records, &rec)
	}

	if records == nil {
		records = []*QualificationRecord{}
	}
	return records, nil
}

// ─── NTC: License functions ───────────────────────────────────────────────────

// AnchorLicense stores a teaching license in the NTC private collection.
// Fails if already anchored — use UpdateLicense for renewals.
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

// UpdateLicense replaces an existing license (e.g. annual NTC renewal).
// NTC org only — only they hold the NTC private collection.
func (s *SmartContract) UpdateLicense(
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
	if existing == nil {
		return fmt.Errorf("license %s not found — use AnchorLicense to create it", certId)
	}

	var old LicenseRecord
	if err := json.Unmarshal(existing, &old); err != nil {
		return fmt.Errorf("failed to unmarshal existing record: %v", err)
	}
	if old.Status == "revoked" {
		return fmt.Errorf("license %s is revoked and cannot be updated", certId)
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
		AnchoredBy:         old.AnchoredBy,
		UpdatedBy:          mspID,
		Timestamp:          old.Timestamp,
		UpdatedAt:          time.Now().UTC().Format(time.RFC3339),
	}

	recordBytes, err := json.Marshal(record)
	if err != nil {
		return fmt.Errorf("failed to marshal record: %v", err)
	}

	return ctx.GetStub().PutPrivateData(pdcNTC, certId, recordBytes)
}

// VerifyLicense checks OCR-extracted fields against the NTC record.
// Also auto-detects expired licenses.
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

	// Use flexible matching — same rationale as VerifyQualification above.
	mismatches := []string{}
	if !flexMatch(record.StaffName, staffName) {
		mismatches = append(mismatches, "name")
	}
	if !flexMatch(record.ProfessionalStatus, professionalStatus) {
		mismatches = append(mismatches, "professional status")
	}
	if !flexMatch(record.SubjectSpecialism, subjectSpecialism) {
		mismatches = append(mismatches, "subject specialism")
	}
	if !flexMatch(record.TeachingLevel, teachingLevel) {
		mismatches = append(mismatches, "teaching level")
	}
	if !flexMatch(record.ExpiryDate, expiryDate) {
		mismatches = append(mismatches, "expiry date")
	}

	if len(mismatches) > 0 {
		return &LicenseVerificationResult{
			CertID:             certId,
			Result:             "mismatch",
			CertType:           "license",
			ProfessionalStatus: record.ProfessionalStatus,
			ExpiryDate:         record.ExpiryDate,
			Message:            "License found but the following do not match: " + strings.Join(mismatches, ", "),
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

// GetLicense returns the full license record from NTC's collection.
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

// RevokeLicense marks a teaching license as revoked. Called by NTC only.
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
	record.UpdatedAt = time.Now().UTC().Format(time.RFC3339)

	mspID, _ := ctx.GetClientIdentity().GetMSPID()
	record.UpdatedBy = mspID

	recordBytes, err = json.Marshal(record)
	if err != nil {
		return fmt.Errorf("failed to marshal record: %v", err)
	}

	return ctx.GetStub().PutPrivateData(pdcNTC, certId, recordBytes)
}

// SeedNTCRecord upserts a license record into the NTC private collection.
// Unlike AnchorLicense there is no duplicate check — safe to call
// repeatedly during demo seeding. CertID convention: LICENSE_<staffId>.
func (s *SmartContract) SeedNTCRecord(
	ctx contractapi.TransactionContextInterface,
	certId string,
	staffName string,
	professionalStatus string,
	subjectSpecialism string,
	teachingLevel string,
	issueDate string,
	expiryDate string,
) error {
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

	rb, err := json.Marshal(record)
	if err != nil {
		return fmt.Errorf("failed to marshal record: %v", err)
	}
	return ctx.GetStub().PutPrivateData(pdcNTC, certId, rb)
}

// BulkSeedNTC seeds multiple NTC license records in one transaction.
// recordsJSON is a JSON array where each element matches LicenseInput.
// All records are upserted — existing entries are silently overwritten.
//
// Example payload:
//
//	[{"certId":"LICENSE_GES001","staffName":"KWAME ASANTE BOATENG",
//	  "professionalStatus":"PT","subjectSpecialism":"MATHEMATICS",
//	  "teachingLevel":"SHS","issueDate":"2020-09-01","expiryDate":"2025-08-31"}, ...]
func (s *SmartContract) BulkSeedNTC(
	ctx contractapi.TransactionContextInterface,
	recordsJSON string,
) error {
	var inputs []LicenseInput
	if err := json.Unmarshal([]byte(recordsJSON), &inputs); err != nil {
		return fmt.Errorf("invalid JSON: %v", err)
	}

	mspID, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return fmt.Errorf("failed to get MSP ID: %v", err)
	}

	ts := time.Now().UTC().Format(time.RFC3339)

	for _, inp := range inputs {
		record := LicenseRecord{
			CertID:             inp.CertID,
			StaffName:          inp.StaffName,
			ProfessionalStatus: inp.ProfessionalStatus,
			SubjectSpecialism:  inp.SubjectSpecialism,
			TeachingLevel:      inp.TeachingLevel,
			IssueDate:          inp.IssueDate,
			ExpiryDate:         inp.ExpiryDate,
			Status:             "active",
			AnchoredBy:         mspID,
			Timestamp:          ts,
		}
		rb, err := json.Marshal(record)
		if err != nil {
			return fmt.Errorf("failed to marshal record %s: %v", inp.CertID, err)
		}
		if err := ctx.GetStub().PutPrivateData(pdcNTC, inp.CertID, rb); err != nil {
			return fmt.Errorf("failed to write record %s: %v", inp.CertID, err)
		}
	}
	return nil
}

// ListLicenses returns all license records from the NTC private collection.
// Must be endorsed by an NTC peer (only they hold the collection).
func (s *SmartContract) ListLicenses(
	ctx contractapi.TransactionContextInterface,
) ([]*LicenseRecord, error) {
	iterator, err := ctx.GetStub().GetPrivateDataByRange(pdcNTC, "", "")
	if err != nil {
		return nil, fmt.Errorf("failed to query private data: %v", err)
	}
	defer iterator.Close()

	var records []*LicenseRecord
	for iterator.HasNext() {
		item, err := iterator.Next()
		if err != nil {
			return nil, fmt.Errorf("iteration error: %v", err)
		}
		var rec LicenseRecord
		if err := json.Unmarshal(item.Value, &rec); err != nil {
			continue
		}
		records = append(records, &rec)
	}

	if records == nil {
		records = []*LicenseRecord{}
	}
	return records, nil
}

// ─── Document hash anchoring (public ledger) ──────────────────────────────────

// AnchorDocumentHash records a document hash on the public ledger and builds a
// composite key so all documents for a staff ID can be range-queried later.
// Idempotent: re-anchoring the same hash for the same staff is a no-op.
func (s *SmartContract) AnchorDocumentHash(
	ctx contractapi.TransactionContextInterface,
	documentHash string,
	staffId string,
	fileName string,
) error {
	existing, err := ctx.GetStub().GetState(documentHash)
	if err != nil {
		return fmt.Errorf("failed to read from ledger: %v", err)
	}
	if existing != nil {
		var existingRecord DocumentRecord
		if err := json.Unmarshal(existing, &existingRecord); err == nil && existingRecord.StaffID == staffId {
			return nil // already anchored for this teacher — no-op
		}
	}

	mspID, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return fmt.Errorf("failed to get MSP ID: %v", err)
	}

	record := DocumentRecord{
		DocumentHash: documentHash,
		StaffID:      staffId,
		FileName:     fileName,
		Revoked:      false,
		AnchoredBy:   mspID,
		Timestamp:    time.Now().UTC().Format(time.RFC3339),
	}

	recordBytes, err := json.Marshal(record)
	if err != nil {
		return fmt.Errorf("failed to marshal record: %v", err)
	}

	if err := ctx.GetStub().PutState(documentHash, recordBytes); err != nil {
		return fmt.Errorf("failed to write to ledger: %v", err)
	}

	// Build composite key STAFF_DOC~staffId~documentHash for range queries
	compositeKey, err := ctx.GetStub().CreateCompositeKey(docIndexKey, []string{staffId, documentHash})
	if err != nil {
		return fmt.Errorf("failed to create composite key: %v", err)
	}
	return ctx.GetStub().PutState(compositeKey, []byte{0x00})
}

// VerifyDocumentHash checks whether a document hash is anchored and belongs to
// the given staff ID. A tampered (re-hashed) document will simply not be found.
func (s *SmartContract) VerifyDocumentHash(
	ctx contractapi.TransactionContextInterface,
	documentHash string,
	staffId string,
) (*DocumentVerificationResult, error) {
	recordBytes, err := ctx.GetStub().GetState(documentHash)
	if err != nil {
		return nil, fmt.Errorf("failed to read from ledger: %v", err)
	}

	if recordBytes == nil {
		return &DocumentVerificationResult{
			DocumentHash: documentHash,
			Result:       "not_found",
			Message:      "This document hash is not anchored on the blockchain",
		}, nil
	}

	var record DocumentRecord
	if err := json.Unmarshal(recordBytes, &record); err != nil {
		return nil, fmt.Errorf("failed to unmarshal record: %v", err)
	}

	if record.Revoked {
		return &DocumentVerificationResult{
			DocumentHash: documentHash,
			Result:       "revoked",
			StaffID:      record.StaffID,
			Timestamp:    record.Timestamp,
			Message:      "This document has been marked as revoked: " + record.RevokeReason,
		}, nil
	}

	if record.StaffID != staffId {
		return &DocumentVerificationResult{
			DocumentHash: documentHash,
			Result:       "not_found",
			StaffID:      record.StaffID,
			Timestamp:    record.Timestamp,
			Message:      "This document hash is anchored, but not for this staff ID",
		}, nil
	}

	return &DocumentVerificationResult{
		DocumentHash: documentHash,
		Result:       "match",
		StaffID:      record.StaffID,
		Timestamp:    record.Timestamp,
		Message:      "Document hash matches the anchored blockchain record — authentic and untampered",
	}, nil
}

// RevokeDocumentHash marks an anchored document hash as revoked (e.g. fraudulent
// document discovered after upload). Future VerifyDocumentHash calls return "revoked".
func (s *SmartContract) RevokeDocumentHash(
	ctx contractapi.TransactionContextInterface,
	documentHash string,
	reason string,
) error {
	recordBytes, err := ctx.GetStub().GetState(documentHash)
	if err != nil {
		return fmt.Errorf("failed to read from ledger: %v", err)
	}
	if recordBytes == nil {
		return fmt.Errorf("document hash %s not found on ledger", documentHash)
	}

	var record DocumentRecord
	if err := json.Unmarshal(recordBytes, &record); err != nil {
		return fmt.Errorf("failed to unmarshal record: %v", err)
	}
	if record.Revoked {
		return fmt.Errorf("document hash %s is already revoked", documentHash)
	}

	record.Revoked = true
	record.RevokeReason = reason

	recordBytes, err = json.Marshal(record)
	if err != nil {
		return fmt.Errorf("failed to marshal record: %v", err)
	}

	return ctx.GetStub().PutState(documentHash, recordBytes)
}

// GetDocumentsByStaff returns all document records anchored for a given staff ID
// using the composite key index built by AnchorDocumentHash.
func (s *SmartContract) GetDocumentsByStaff(
	ctx contractapi.TransactionContextInterface,
	staffId string,
) ([]DocumentRecord, error) {
	iterator, err := ctx.GetStub().GetStateByPartialCompositeKey(docIndexKey, []string{staffId})
	if err != nil {
		return nil, fmt.Errorf("failed to query composite index: %v", err)
	}
	defer iterator.Close()

	var records []DocumentRecord
	for iterator.HasNext() {
		item, err := iterator.Next()
		if err != nil {
			return nil, fmt.Errorf("failed to iterate: %v", err)
		}

		// The composite key encodes: STAFF_DOC~staffId~documentHash
		// Extract the documentHash from the composite key attributes
		_, attrs, err := ctx.GetStub().SplitCompositeKey(item.Key)
		if err != nil || len(attrs) < 2 {
			continue
		}
		docHash := attrs[1]

		docBytes, err := ctx.GetStub().GetState(docHash)
		if err != nil || docBytes == nil {
			continue
		}

		var rec DocumentRecord
		if err := json.Unmarshal(docBytes, &rec); err != nil {
			continue
		}
		records = append(records, rec)
	}

	if records == nil {
		records = []DocumentRecord{}
	}

	return records, nil
}

// ─── GES Promotion functions (public ledger) ──────────────────────────────────

// RecordPromotionDecision writes a promotion decision to the public ledger.
// Also builds a composite key for per-staff promotion history queries.
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

	if err := ctx.GetStub().PutState(key, recordBytes); err != nil {
		return fmt.Errorf("failed to write to ledger: %v", err)
	}

	// Build composite key STAFF_PROMO~staffId~promotionId for range queries
	compositeKey, err := ctx.GetStub().CreateCompositeKey(promoIndexKey, []string{staffId, promotionId})
	if err != nil {
		return fmt.Errorf("failed to create composite key: %v", err)
	}
	return ctx.GetStub().PutState(compositeKey, []byte{0x00})
}

// GetPromotionRecord returns a single promotion from the public ledger.
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

// GetPromotionsByStaff returns all promotion records for a given staff ID
// using the composite key index built by RecordPromotionDecision.
func (s *SmartContract) GetPromotionsByStaff(
	ctx contractapi.TransactionContextInterface,
	staffId string,
) ([]PromotionRecord, error) {
	iterator, err := ctx.GetStub().GetStateByPartialCompositeKey(promoIndexKey, []string{staffId})
	if err != nil {
		return nil, fmt.Errorf("failed to query composite index: %v", err)
	}
	defer iterator.Close()

	var records []PromotionRecord
	for iterator.HasNext() {
		item, err := iterator.Next()
		if err != nil {
			return nil, fmt.Errorf("failed to iterate: %v", err)
		}

		_, attrs, err := ctx.GetStub().SplitCompositeKey(item.Key)
		if err != nil || len(attrs) < 2 {
			continue
		}
		promotionId := attrs[1]

		promoBytes, err := ctx.GetStub().GetState("PROMOTION_" + promotionId)
		if err != nil || promoBytes == nil {
			continue
		}

		var rec PromotionRecord
		if err := json.Unmarshal(promoBytes, &rec); err != nil {
			continue
		}
		records = append(records, rec)
	}

	if records == nil {
		records = []PromotionRecord{}
	}

	return records, nil
}

// GetTeacherSummary returns a combined view of all on-chain records for a teacher:
// document hashes (public ledger) and promotion history (public ledger).
// Note: qualification and license details are in private collections (GTEC/NTC)
// and cannot be included here without org-specific endorsement.
func (s *SmartContract) GetTeacherSummary(
	ctx contractapi.TransactionContextInterface,
	staffId string,
) (*TeacherSummary, error) {
	docs, err := s.GetDocumentsByStaff(ctx, staffId)
	if err != nil {
		return nil, fmt.Errorf("failed to get documents: %v", err)
	}

	promos, err := s.GetPromotionsByStaff(ctx, staffId)
	if err != nil {
		return nil, fmt.Errorf("failed to get promotions: %v", err)
	}

	return &TeacherSummary{
		StaffID:    staffId,
		Documents:  docs,
		Promotions: promos,
		Timestamp:  time.Now().UTC().Format(time.RFC3339),
	}, nil
}

// ─── Health check ─────────────────────────────────────────────────────────────

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

// ─── Main ─────────────────────────────────────────────────────────────────────

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
// new chaincode