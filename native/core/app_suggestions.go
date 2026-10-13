package core

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"unicode/utf8"
)

func (engine *nativeEngine) suggestions(ctx context.Context, source, query string) ([]string, error) {
	provider, found := findProvider(source)
	if !found {
		return nil, errNativeBuildSource
	}
	suggestions, supported := provider.(ProviderSuggestions)
	if !supported {
		return nil, errors.New("当前站源不支持搜索联想")
	}
	if strings.TrimSpace(query) == "" {
		return []string{}, nil
	}
	return suggestions.Suggestions(ctx, engine.downloader, query)
}

func nativeParseSuggestions(body []byte) ([]string, error) {
	var result map[string]json.RawMessage
	if json.Unmarshal(body, &result) != nil {
		return nil, errors.New("搜索联想暂不可用")
	}
	list := result["suggest_list"]
	if len(list) == 0 {
		var data map[string]json.RawMessage
		if json.Unmarshal(result["data"], &data) == nil {
			list = data["suggest_list"]
		}
	}
	if len(list) == 0 || string(list) == "null" {
		return []string{}, nil
	}
	var entries []struct {
		Name string `json:"name"`
	}
	if json.Unmarshal(list, &entries) != nil {
		return nil, errors.New("搜索联想暂不可用")
	}
	names, seen := []string{}, map[string]bool{}
	for _, entry := range entries {
		name := strings.TrimSpace(entry.Name)
		if name != "" && !seen[name] && utf8.RuneCountInString(name) <= 200 {
			names = append(names, name)
			seen[name] = true
			if len(names) == 10 {
				break
			}
		}
	}
	return names, nil
}
