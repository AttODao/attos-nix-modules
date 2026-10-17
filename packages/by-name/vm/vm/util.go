package main

import (
	"bytes"
	"encoding/json"
)

func compact(raw json.RawMessage) []byte {
	var buffer bytes.Buffer
	if json.Compact(&buffer, raw) != nil {
		return raw
	}
	return buffer.Bytes()
}

// objectList decodes a JSON array whose elements are all objects; null is rejected.
func objectList(data []byte) ([]map[string]any, bool) {
	var value any
	if json.Unmarshal(data, &value) != nil {
		return nil, false
	}
	items, ok := value.([]any)
	if !ok {
		return nil, false
	}
	list := make([]map[string]any, 0, len(items))
	for _, item := range items {
		object, ok := item.(map[string]any)
		if !ok {
			return nil, false
		}
		list = append(list, object)
	}
	return list, true
}
