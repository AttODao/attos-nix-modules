package main

import (
	"bytes"
	"errors"
	"os/exec"
)

// preseedCondition is a create-only Incus preseed guard; it never reconciles an
// existing storage pool. ExecCondition exit 1 skips initialization; errors are
// reported by the caller as 255, never as a skip code.
func preseedCondition(args []string) (int, error) {
	if len(args) != 1 {
		return 0, errors.New("usage: guest preseed-condition <pool>")
	}
	c := exec.Command("incus", "--force-local", "storage", "list", "--format=json")
	var out, discarded bytes.Buffer
	c.Stdout, c.Stderr = &out, &discarded
	if err := c.Run(); err != nil {
		return 0, errors.New("Incus operation failed: storage list")
	}
	return preseedDecision(out.Bytes(), args[0])
}

func preseedDecision(list []byte, pool string) (int, error) {
	pools, ok := objectList(list)
	if !ok {
		return 0, errors.New("Unexpected Incus storage list")
	}
	for _, item := range pools {
		if _, ok := item["name"].(string); !ok {
			return 0, errors.New("Unexpected Incus storage list")
		}
	}
	for _, item := range pools {
		if item["name"] == pool {
			return 1, nil
		}
	}
	if len(pools) > 0 {
		return 0, errors.New("Target pool is absent while other pools exist; explicit storage migration is required before preseed.")
	}
	return 0, nil
}
