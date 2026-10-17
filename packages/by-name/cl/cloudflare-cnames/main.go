// Sync declared Cloudflare CNAMEs; only prune CNAMEs carrying our owner tag.
package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
)

type record struct {
	ID      string  `json:"id"`
	Type    string  `json:"type"`
	Name    string  `json:"name"`
	Content string  `json:"content"`
	TTL     *int    `json:"ttl"`
	Proxied *bool   `json:"proxied"`
	Comment *string `json:"comment"`
}

type payload struct {
	ID      string `json:"id,omitempty"`
	Type    string `json:"type"`
	Name    string `json:"name"`
	Content string `json:"content"`
	TTL     int    `json:"ttl"`
	Proxied bool   `json:"proxied"`
	Comment string `json:"comment"`
}

type config struct {
	Records []string `json:"records"`
	Target  string   `json:"target"`
	Comment string   `json:"comment"`
	TTL     *int     `json:"ttl"`
	Proxied *bool    `json:"proxied"`
}

type api interface {
	request(method, suffix string, query url.Values, body any) (map[string]json.RawMessage, error)
}

type cloudflare struct {
	token  string
	base   string
	client *http.Client
}

var (
	zoneID = regexp.MustCompile(`^[0-9a-fA-F]{32}$`)
	label  = regexp.MustCompile(`^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$`)
)

func newCloudflare(token, zone string) (*cloudflare, error) {
	if token == "" || !zoneID.MatchString(zone) {
		return nil, errors.New("CLOUDFLARE_API_TOKEN and a valid CLOUDFLARE_ZONE_ID are required")
	}
	return &cloudflare{
		token:  token,
		base:   "https://api.cloudflare.com/client/v4/zones/" + url.PathEscape(zone) + "/dns_records",
		client: &http.Client{Timeout: 30 * time.Second},
	}, nil
}

func (c *cloudflare) request(method, suffix string, query url.Values, body any) (map[string]json.RawMessage, error) {
	target := c.base + suffix
	if len(query) > 0 {
		target += "?" + query.Encode()
	}
	var reader *bytes.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return nil, err
		}
		reader = bytes.NewReader(encoded)
	} else {
		reader = bytes.NewReader(nil)
	}
	request, err := http.NewRequest(method, target, reader)
	if err != nil {
		return nil, errors.New("Cloudflare DNS request failed")
	}
	request.Header.Set("Authorization", "Bearer "+c.token)
	request.Header.Set("Content-Type", "application/json")
	response, err := c.client.Do(request)
	if err != nil {
		// Transport errors can include request details; never print them.
		return nil, errors.New("Cloudflare DNS request failed")
	}
	defer response.Body.Close()
	var data map[string]json.RawMessage
	if json.NewDecoder(response.Body).Decode(&data) != nil {
		return nil, errors.New("Cloudflare DNS request failed")
	}
	var success bool
	if json.Unmarshal(data["success"], &success) != nil || !success || response.StatusCode >= 300 {
		return nil, errors.New("Cloudflare refused the DNS operation")
	}
	return data, nil
}

func records(c api, query url.Values) ([]record, error) {
	var result []record
	for page := 1; ; page++ {
		paged := url.Values{}
		for key, values := range query {
			paged[key] = values
		}
		paged.Set("page", strconv.Itoa(page))
		paged.Set("per_page", "100")
		data, err := c.request("GET", "", paged, nil)
		if err != nil {
			return nil, err
		}
		var batch []record
		if err := json.Unmarshal(data["result"], &batch); err != nil {
			return nil, errors.New("Unexpected Cloudflare DNS response")
		}
		result = append(result, batch...)
		info := struct {
			TotalPages *int `json:"total_pages"`
		}{}
		if raw, ok := data["result_info"]; ok {
			json.Unmarshal(raw, &info)
		}
		if info.TotalPages == nil || page >= *info.TotalPages {
			return result, nil
		}
	}
}

func validHostname(name string) bool {
	if len(name) > 253 || !strings.Contains(name, ".") {
		return false
	}
	for _, part := range strings.Split(name, ".") {
		if len(part) > 63 || !label.MatchString(part) {
			return false
		}
	}
	return true
}

func differs(current record, want payload) bool {
	return current.Type != want.Type || current.Name != want.Name || current.Content != want.Content ||
		current.TTL == nil || *current.TTL != want.TTL ||
		current.Proxied == nil || *current.Proxied != want.Proxied ||
		current.Comment == nil || *current.Comment != want.Comment
}

func sync(c api, cfg config) error {
	ttl, proxied := 1, false
	if cfg.TTL != nil {
		ttl = *cfg.TTL
	}
	if cfg.Proxied != nil {
		proxied = *cfg.Proxied
	}
	names := map[string]bool{}
	if cfg.Records == nil {
		return errors.New("Expected valid fully qualified hostnames")
	}
	for _, name := range cfg.Records {
		if !validHostname(name) {
			return errors.New("Expected valid fully qualified hostnames")
		}
	}
	if cfg.Comment == "" || ttl < 1 {
		return errors.New("Expected an ownership comment, positive TTL and boolean proxied")
	}
	for _, name := range cfg.Records {
		if names[name] {
			return errors.New("Duplicate DNS record names")
		}
		names[name] = true
	}
	if !validHostname(cfg.Target) || names[cfg.Target] {
		return errors.New("CNAME target must be a different valid hostname")
	}

	for _, name := range cfg.Records {
		current, err := records(c, url.Values{"name": {name}})
		if err != nil {
			return err
		}
		// Validate before deleting any conflicting records for this hostname.
		var conflicting, existing []record
		for _, item := range current {
			switch item.Type {
			case "A", "AAAA":
				conflicting = append(conflicting, item)
			case "CNAME":
				existing = append(existing, item)
			default:
				return errors.New("Refusing to replace non-address DNS records for " + name)
			}
		}
		want := payload{Type: "CNAME", Name: name, Content: cfg.Target, TTL: ttl, Proxied: proxied, Comment: cfg.Comment}
		var updates []payload
		for _, item := range existing {
			if differs(item, want) {
				update := want
				update.ID = item.ID
				updates = append(updates, update)
			}
		}
		if len(conflicting) > 0 {
			// Cloudflare's database transaction keeps the old records if replacement fails.
			// DNS propagation itself is not atomic.
			deletes := []map[string]string{}
			for _, item := range conflicting {
				deletes = append(deletes, map[string]string{"id": item.ID})
			}
			posts := []payload{}
			if len(existing) == 0 {
				posts = append(posts, want)
			}
			if updates == nil {
				updates = []payload{}
			}
			body := map[string]any{"deletes": deletes, "puts": updates, "posts": posts}
			if _, err := c.request("POST", "/batch", nil, body); err != nil {
				return err
			}
			continue
		}
		if len(existing) == 0 {
			if _, err := c.request("POST", "", nil, want); err != nil {
				return err
			}
		}
		for _, update := range updates {
			id := update.ID
			update.ID = ""
			if _, err := c.request("PUT", "/"+url.PathEscape(id), nil, update); err != nil {
				return err
			}
		}
	}

	owned, err := records(c, url.Values{"type": {"CNAME"}, "content": {cfg.Target}})
	if err != nil {
		return err
	}
	for _, item := range owned {
		if item.Comment != nil && *item.Comment == cfg.Comment && !names[item.Name] {
			if _, err := c.request("DELETE", "/"+url.PathEscape(item.ID), nil, nil); err != nil {
				return err
			}
		}
	}
	return nil
}

func run(arguments []string) error {
	if len(arguments) != 1 {
		return errors.New("Usage: cloudflare-cnames CONFIG")
	}
	content, err := os.ReadFile(arguments[0])
	if err != nil {
		return err
	}
	var cfg config
	if err := json.Unmarshal(content, &cfg); err != nil {
		return errors.New("Expected an ownership comment, positive TTL and boolean proxied")
	}
	client, err := newCloudflare(os.Getenv("CLOUDFLARE_API_TOKEN"), os.Getenv("CLOUDFLARE_ZONE_ID"))
	if err != nil {
		return err
	}
	return sync(client, cfg)
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		// Do not dump requests, response bodies or the authentication header.
		fmt.Fprintln(os.Stderr, "DNS sync failed: "+err.Error())
		os.Exit(1)
	}
}
