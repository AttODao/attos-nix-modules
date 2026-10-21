package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

type call struct {
	method, suffix string
	query          url.Values
	body           string
}

type fake struct {
	byName map[string][]record
	owned  []record
	calls  []call
}

func (f *fake) request(method, suffix string, query url.Values, body any) (map[string]json.RawMessage, error) {
	encoded := ""
	if body != nil {
		raw, _ := json.Marshal(body)
		encoded = string(raw)
	}
	f.calls = append(f.calls, call{method, suffix, query, encoded})
	result := []record{}
	if method == "GET" {
		if name := query.Get("name"); name != "" {
			result = f.byName[name]
		} else {
			result = f.owned
		}
	}
	raw, _ := json.Marshal(result)
	return map[string]json.RawMessage{"result": raw, "result_info": json.RawMessage(`{"total_pages":1}`)}, nil
}

func ptr[T any](value T) *T { return &value }

func mutations(f *fake) []call {
	var result []call
	for _, item := range f.calls {
		if item.method != "GET" {
			result = append(result, item)
		}
	}
	return result
}

func TestSync(t *testing.T) {
	comment := "managed"
	f := &fake{
		byName: map[string][]record{
			"new.example.org":  nil,
			"addr.example.org": {{ID: "a1", Type: "A", Name: "addr.example.org", Content: "192.0.2.1"}},
			"same.example.org": {{ID: "c1", Type: "CNAME", Name: "same.example.org", Content: "home.example.org", TTL: ptr(1), Proxied: ptr(false), Comment: &comment}},
			"old.example.org":  {{ID: "c2", Type: "CNAME", Name: "old.example.org", Content: "elsewhere.example.org", TTL: ptr(1), Proxied: ptr(false), Comment: &comment}},
		},
		owned: []record{
			{ID: "s1", Type: "CNAME", Name: "stale.example.org", Content: "home.example.org", Comment: &comment},
			{ID: "s2", Type: "CNAME", Name: "foreign.example.org", Content: "home.example.org", Comment: ptr("other")},
		},
	}
	cfg := config{Records: []string{"new.example.org", "addr.example.org", "same.example.org", "old.example.org"}, Target: "home.example.org", Comment: comment}
	if err := sync(f, cfg); err != nil {
		t.Fatal(err)
	}
	got := mutations(f)
	want := []call{
		{"POST", "", nil, `{"type":"CNAME","name":"new.example.org","content":"home.example.org","ttl":1,"proxied":false,"comment":"managed"}`},
		{"POST", "/batch", nil, `{"deletes":[{"id":"a1"}],"posts":[{"type":"CNAME","name":"addr.example.org","content":"home.example.org","ttl":1,"proxied":false,"comment":"managed"}],"puts":[]}`},
		{"PUT", "/c2", nil, `{"type":"CNAME","name":"old.example.org","content":"home.example.org","ttl":1,"proxied":false,"comment":"managed"}`},
		{"DELETE", "/s1", nil, ""},
	}
	if len(got) != len(want) {
		t.Fatalf("calls: %+v", got)
	}
	for index := range want {
		if got[index].method != want[index].method || got[index].suffix != want[index].suffix || got[index].body != want[index].body {
			t.Errorf("call %d: got %+v want %+v", index, got[index], want[index])
		}
	}
}

func TestAPIError(t *testing.T) {
	err := apiError("POST", 403, json.RawMessage(`[{"code":10000,"message":"Authentication error"},{"code":81057,"message":"Record already exists"}]`))
	want := "Cloudflare refused the DNS POST request (HTTP 403): 10000 Authentication error; 81057 Record already exists"
	if err.Error() != want {
		t.Fatalf("got %q", err.Error())
	}
	if got := apiError("GET", 502, nil).Error(); got != "Cloudflare refused the DNS GET request (HTTP 502)" {
		t.Fatalf("got %q", got)
	}
}

func TestSyncRejects(t *testing.T) {
	f := &fake{byName: map[string][]record{"mx.example.org": {{ID: "m", Type: "MX", Name: "mx.example.org"}}}}
	cases := []config{
		{Records: []string{"Bad.example.org"}, Target: "home.example.org", Comment: "c"},
		{Records: []string{"a.example.org", "a.example.org"}, Target: "home.example.org", Comment: "c"},
		{Records: []string{"home.example.org"}, Target: "home.example.org", Comment: "c"},
		{Records: []string{"a.example.org"}, Target: "home.example.org"},
		{Records: []string{"a.example.org"}, Target: "home.example.org", Comment: "c", TTL: ptr(0)},
		{Records: []string{"mx.example.org"}, Target: "home.example.org", Comment: "c"},
		{Target: "home.example.org", Comment: "c"},
	}
	for index, cfg := range cases {
		if sync(f, cfg) == nil {
			t.Errorf("case %d accepted", index)
		}
	}
	if len(mutations(f)) != 0 {
		t.Fatal("mutated on invalid input")
	}
	if _, err := newCloudflare("", "0123456789abcdef0123456789abcdef"); err == nil {
		t.Fatal("empty token accepted")
	}
}

func TestRequestError(t *testing.T) {
	const token = "test-private-token"
	for _, body := range []string{
		`{"success":false,"errors":[{"code":10000,"message":"Rejected test-private-token"}],"other":"private response"}`,
		`invalid private response`,
	} {
		t.Run(body, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Header.Get("Authorization") != "Bearer "+token {
					t.Error("missing auth")
				}
				w.WriteHeader(http.StatusForbidden)
				w.Write([]byte(body))
			}))
			defer server.Close()
			client := cloudflare{token: token, base: server.URL, client: server.Client()}
			_, err := client.request("POST", "", nil, nil)
			if err == nil {
				t.Fatal("accepted error response")
			}
			text := err.Error()
			if !strings.Contains(text, "HTTP 403") || strings.Contains(text, token) || strings.Contains(text, "private response") {
				t.Fatalf("unsafe/missing diagnostics: %s", text)
			}
			if strings.HasPrefix(body, "{") && (!strings.Contains(text, "10000") || !strings.Contains(text, "Rejected")) {
				t.Fatalf("missing code/message: %s", text)
			}
		})
	}
}
