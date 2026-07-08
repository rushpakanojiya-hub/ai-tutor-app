// Package cloudinary is a minimal signed-upload client for Cloudinary,
// written against Cloudinary's plain HTTP API (no third-party SDK) so it
// has zero new dependencies. The API secret never leaves the backend -
// the signature is computed here and the Flutter app only ever talks to
// our own /api/live-classes/:id/resources endpoint, never Cloudinary
// directly.
package cloudinary

import (
	"bytes"
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"sort"
	"strconv"
	"time"
)

type Client struct {
	cloudName string
	apiKey    string
	apiSecret string
	http      *http.Client
}

func NewClient(cloudName, apiKey, apiSecret string) *Client {
	return &Client{
		cloudName: cloudName,
		apiKey:    apiKey,
		apiSecret: apiSecret,
		http:      &http.Client{Timeout: 60 * time.Second},
	}
}

// UploadResult is the subset of Cloudinary's response we actually use.
type UploadResult struct {
	SecureURL    string `json:"secure_url"`
	PublicID     string `json:"public_id"`
	Bytes        int64  `json:"bytes"`
	ResourceType string `json:"resource_type"`
	Format       string `json:"format"`
}

// Upload sends fileBytes to Cloudinary using the given resource type
// ("image", "video", or "raw"). We pass this explicitly rather than
// using Cloudinary's "auto" endpoint because PDFs/Office docs uploaded
// as "image" (auto's default for PDFs) are blocked from public delivery
// on new Cloudinary accounts by default (a security restriction against
// PDF/ZIP hosting abuse) - "raw" has no such restriction and works for
// any non-image/video file type.
func (c *Client) Upload(fileBytes []byte, filename, resourceType string) (*UploadResult, error) {
	timestamp := strconv.FormatInt(time.Now().Unix(), 10)

	paramsToSign := map[string]string{"timestamp": timestamp}
	signature := c.sign(paramsToSign)

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)

	fileWriter, err := writer.CreateFormFile("file", filename)
	if err != nil {
		return nil, err
	}
	if _, err := fileWriter.Write(fileBytes); err != nil {
		return nil, err
	}

	_ = writer.WriteField("api_key", c.apiKey)
	_ = writer.WriteField("timestamp", timestamp)
	_ = writer.WriteField("signature", signature)
	if err := writer.Close(); err != nil {
		return nil, err
	}

	url := fmt.Sprintf("https://api.cloudinary.com/v1_1/%s/%s/upload", c.cloudName, resourceType)
	req, err := http.NewRequest(http.MethodPost, url, body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("cloudinary upload failed (status %d): %s", resp.StatusCode, string(respBody))
	}

	var result UploadResult
	if err := json.Unmarshal(respBody, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// Delete removes a previously-uploaded asset by its public_id - the
// resource type must match what it was uploaded as (image/video/raw).
func (c *Client) Delete(publicID, resourceType string) error {
	timestamp := strconv.FormatInt(time.Now().Unix(), 10)
	paramsToSign := map[string]string{"public_id": publicID, "timestamp": timestamp}
	signature := c.sign(paramsToSign)

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	_ = writer.WriteField("public_id", publicID)
	_ = writer.WriteField("api_key", c.apiKey)
	_ = writer.WriteField("timestamp", timestamp)
	_ = writer.WriteField("signature", signature)
	if err := writer.Close(); err != nil {
		return err
	}

	url := fmt.Sprintf("https://api.cloudinary.com/v1_1/%s/%s/destroy", c.cloudName, resourceType)
	req, err := http.NewRequest(http.MethodPost, url, body)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())

	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	return nil // best-effort - a failed remote delete shouldn't block removing our own DB row
}

func (c *Client) sign(params map[string]string) string {
	keys := make([]string, 0, len(params))
	for k := range params {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	toSign := ""
	for i, k := range keys {
		if i > 0 {
			toSign += "&"
		}
		toSign += k + "=" + params[k]
	}
	toSign += c.apiSecret

	sum := sha1.Sum([]byte(toSign))
	return hex.EncodeToString(sum[:])
}
