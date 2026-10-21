// Runtime-only initialization; neither credentials nor mutable state enter the Nix store.
// Directories and packaged asset symlinks are created by systemd-tmpfiles.
package main

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
	"unicode/utf16"
)

type settings struct {
	DataDir       string `json:"dataDir"`
	ListenAddress string `json:"listenAddress"`
	Hostname      string `json:"hostname"`
	Standalone    bool   `json:"standalone"`
	WebPort       int    `json:"webPort"`
	DaemonPort    int    `json:"daemonPort"`
	InitialAdmin  bool   `json:"initialAdmin"`
}

var (
	daemonKey   = regexp.MustCompile(`^[A-Za-z0-9_-]{32,256}$`)
	bcryptHash  = regexp.MustCompile(`^\$2[aby]\$\d{2}\$[./A-Za-z0-9]{53}$`)
	controlChar = regexp.MustCompile(`[\x00-\x1f\x7f]`)
)

func readObject(file string) (map[string]any, error) {
	info, err := os.Lstat(file)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() {
		return nil, errors.New("state is not a regular file")
	}
	content, err := os.ReadFile(file)
	if err != nil {
		return nil, err
	}
	decoder := json.NewDecoder(bytes.NewReader(content))
	decoder.UseNumber()
	var value any
	if err := decoder.Decode(&value); err != nil {
		return nil, err
	}
	object, ok := value.(map[string]any)
	if !ok || object == nil {
		return nil, errors.New("invalid object")
	}
	return object, nil
}

func load(file string) (map[string]any, error) {
	if _, err := os.Lstat(file); errors.Is(err, os.ErrNotExist) {
		return map[string]any{}, nil
	}
	return readObject(file)
}

func randomHex() string {
	bytes := make([]byte, 16)
	if _, err := rand.Read(bytes); err != nil {
		panic(err)
	}
	return hex.EncodeToString(bytes)
}

func encode(value any) ([]byte, error) {
	var buffer bytes.Buffer
	encoder := json.NewEncoder(&buffer)
	encoder.SetEscapeHTML(false)
	if err := encoder.Encode(value); err != nil {
		return nil, err
	}
	return bytes.TrimSuffix(buffer.Bytes(), []byte("\n")), nil
}

func save(file string, value map[string]any) error {
	if _, err := os.Lstat(file); err == nil {
		// Do not follow a state-file symlink.
		if _, err := readObject(file); err != nil {
			return err
		}
	}
	if err := os.MkdirAll(filepath.Dir(file), 0o700); err != nil {
		return err
	}
	content, err := encode(value)
	if err != nil {
		return err
	}
	temporary := file + "." + randomHex() + ".tmp"
	handle, err := os.OpenFile(temporary, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return err
	}
	defer os.Remove(temporary)
	_, err = handle.Write(content)
	if closeErr := handle.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	return os.Rename(temporary, file)
}

func merge(file string, fields map[string]any) error {
	value, err := load(file)
	if err != nil {
		return err
	}
	for key, field := range fields {
		value[key] = field
	}
	return save(file, value)
}

func validAdmin(admin map[string]any) bool {
	name, nameOK := admin["userName"].(string)
	password, passwordOK := admin["passWord"].(string)
	return nameOK && strings.TrimSpace(name) != "" && len(utf16.Encode([]rune(name))) <= 64 &&
		!controlChar.MatchString(name) && passwordOK && bcryptHash.MatchString(password)
}

func hasUsers(dir string) (bool, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return false, err
	}
	for _, entry := range entries {
		if strings.HasSuffix(entry.Name(), ".json") {
			return true, nil
		}
	}
	return false, nil
}

func bootstrap(kind string, cfg settings, credentials string) error {
	content, err := os.ReadFile(filepath.Join(credentials, "daemon-key"))
	if err != nil {
		return err
	}
	key := strings.TrimSpace(string(content))
	if !daemonKey.MatchString(key) {
		return errors.New("invalid daemon key")
	}
	root := filepath.Join(cfg.DataDir, kind)
	switch kind {
	case "daemon":
		return merge(filepath.Join(root, "data/Config/global.json"), map[string]any{
			"version": 2, "ip": cfg.ListenAddress, "port": cfg.DaemonPort,
			"prefix": "/daemon/", "key": key, "ssl": false, "updateSourceUrl": "",
		})
	case "web":
		err := merge(filepath.Join(root, "data/SystemConfig/config.json"), map[string]any{
			"httpIp": cfg.ListenAddress, "httpPort": cfg.WebPort, "prefix": "",
			"ssl": false, "reverseProxyMode": !cfg.Standalone, "reverseProxyHeader": "X-Real-IP",
			"crossDomain": false, "updateSourceUrl": "",
		})
		if err != nil {
			return err
		}
		remoteMappings := []any{}
		if !cfg.Standalone {
			remoteMappings = append(remoteMappings, map[string]any{
				"from": map[string]any{"ip": cfg.Hostname, "port": 443, "prefix": ""},
				"to":   map[string]any{"ip": "https://" + cfg.Hostname, "port": 443, "prefix": "/daemon/"},
			})
		}
		err = merge(filepath.Join(root, "data/RemoteServiceConfig/00000000000000000000000000000001.json"), map[string]any{
			"ip": cfg.ListenAddress, "port": cfg.DaemonPort, "prefix": "/daemon/",
			"remarks": "Local native daemon", "apiKey": key, "remoteMappings": remoteMappings,
		})
		if err != nil {
			return err
		}
		users := filepath.Join(root, "data/User")
		if err := os.MkdirAll(users, 0o700); err != nil {
			return err
		}
		if !cfg.InitialAdmin {
			return nil
		}
		if existing, err := hasUsers(users); err != nil || existing {
			return err
		}
		admin, err := readObject(filepath.Join(credentials, "initial-admin"))
		if err != nil {
			return err
		}
		if !validAdmin(admin) {
			return errors.New("invalid initial administrator")
		}
		uuid := randomHex()
		return save(filepath.Join(users, uuid+".json"), map[string]any{
			"uuid": uuid, "userName": admin["userName"], "passWord": admin["passWord"],
			"passWordType": 1, "permission": 10, "isInit": false, "instances": []any{}, "apiKey": "",
			"secret": "", "open2FA": false, "registerTime": time.Now().UTC().Format("2006-01-02T15:04:05.000Z"),
			"loginTime": "", "salt": "",
		})
	}
	return errors.New("invalid component")
}

func run(arguments []string) error {
	if len(arguments) != 2 {
		return errors.New("usage")
	}
	object, err := readObject(arguments[1])
	if err != nil {
		return err
	}
	encoded, _ := json.Marshal(object)
	var cfg settings
	if err := json.Unmarshal(encoded, &cfg); err != nil {
		return err
	}
	return bootstrap(arguments[0], cfg, os.Getenv("CREDENTIALS_DIRECTORY"))
}

// describe names only the operation, path and errno of a file-system failure.
// Upstream JSON/parser errors may contain secret contents and are never printed.
func describe(err error) string {
	message := "MCSManager runtime initialization failed; check credential formats and state permissions."
	var pathErr *os.PathError
	if errors.As(err, &pathErr) {
		kind := "filesystem error"
		switch {
		case errors.Is(pathErr, os.ErrNotExist):
			kind = "not found"
		case errors.Is(pathErr, os.ErrPermission):
			kind = "permission denied"
		case errors.Is(pathErr, os.ErrExist):
			kind = "already exists"
		case errors.Is(pathErr, os.ErrInvalid):
			kind = "invalid operation"
		}
		message += " (" + pathErr.Op + " " + pathErr.Path + ": " + kind + ")"
	}
	return message
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, describe(err))
		os.Exit(1)
	}
}
