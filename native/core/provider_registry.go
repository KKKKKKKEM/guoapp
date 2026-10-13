package core

import (
	"context"
	"fmt"
	"net/url"
	"sort"
	"strings"
)

const (
	sourceHuangguoAI    = "huangguoai"
	sourceHuangguoVideo = "huangguo-video"
	sourceHuangdou      = "huangdou"
	sourceHongguo       = "hongguo"
	sourceHuangju       = "huangju"
	sourceYeguo         = "yeguo"
	sourceDSD           = "dsd"
	sourceCloudFront    = "cloudfront"
	sourceSorani        = "sorani"
	sourceGuipian       = "guipian"
	sourceHanxiaoquan   = "hanxiaoquan"
)

type SourceInfo struct {
	ID                string   `json:"id"`
	Name              string   `json:"name"`
	Description       string   `json:"description"`
	GroupID           string   `json:"groupId"`
	GroupName         string   `json:"groupName"`
	EntryName         string   `json:"entryName"`
	Restricted        bool     `json:"restricted"`
	Default           bool     `json:"default"`
	SearchMode        string   `json:"searchMode"`
	SearchSuggestions bool     `json:"searchSuggestions"`
	MetadataFields    []string `json:"metadataFields"`
}

type ProviderDefinition struct {
	SourceInfo
	BaseURL              string
	Aliases              []string
	Hosts                []string
	HostSuffixes         []string
	PreserveMediaHost    bool
	StaticCategories     bool
	IncrementalCatalog   bool
	AllowEmptyCatalog    bool
	PreserveEpisodeCount bool
	SinglePageRankings   bool
	RankingOrder         int
}

type providerCatalogRequest struct {
	Page     int
	Category string
	Query    string
}

type providerCatalogPage struct {
	Items   []Drama
	HasMore bool
	Page    int
	Warning string
	hongguo *hongguoCatalogState
}

type Provider interface {
	Definition() *ProviderDefinition
	ValidCategory(string) bool
	Categories(context.Context, *Downloader, bool) ([]nativeCategory, error)
	Catalog(context.Context, *Downloader, providerCatalogRequest) (providerCatalogPage, error)
	Detail(context.Context, *Downloader, Drama) (Drama, []Chapter, error)
	Resolve(context.Context, *Downloader, Task) (providerMedia, error)
}

type ProviderMetadata interface {
	MetadataFields() []string
	Metadata(context.Context, *Downloader, nativeDrama) (Drama, error)
}

type ProviderCoverAddress interface {
	CoverAddress(context.Context, *Downloader, nativeDrama) (string, error)
}

type ProviderCoverReferer interface {
	CoverReferer(*Downloader, string) string
}

type ProviderRankings interface {
	Rankings(context.Context, *Downloader, rankingBoard, int) (rankingPage, error)
	Boards() []rankingBoard
}

type ProviderRankingCategory interface {
	RankingCategory(context.Context, *Downloader, string) string
}

type ProviderSuggestions interface {
	Suggestions(context.Context, *Downloader, string) ([]string, error)
}

type providerRegistry struct {
	ordered []Provider
	byID    map[string]Provider
	aliases map[string]string
	hosts   map[string]string
}

var providers providerRegistry

func init() {
	providers = newProviderRegistry(
		hongguoProvider{}, hanxiaoquanProvider{}, guipianProvider{}, soraniProvider{},
		huangdouProvider{}, huangjuProvider{}, yeguoProvider{}, dsdProvider{},
		huangguoVideoProvider{}, huangguoAIProvider{}, cloudfrontProvider{},
	)
	ranked := make([]Provider, 0, len(providers.ordered))
	total := 0
	for _, provider := range providers.ordered {
		if rankings, supported := provider.(ProviderRankings); supported {
			ranked = append(ranked, provider)
			total += len(rankings.Boards())
		}
	}
	sort.SliceStable(ranked, func(i, j int) bool {
		return ranked[i].Definition().RankingOrder < ranked[j].Definition().RankingOrder
	})
	rankingBoards = make([]rankingBoard, 0, total)
	for _, provider := range ranked {
		rankingBoards = append(rankingBoards, provider.(ProviderRankings).Boards()...)
	}
}

func newProviderRegistry(entries ...Provider) providerRegistry {
	registry := providerRegistry{ordered: entries, byID: make(map[string]Provider, len(entries)), aliases: map[string]string{}, hosts: map[string]string{}}
	for _, provider := range entries {
		definition := provider.Definition()
		id := definition.ID
		if id == "" || id != strings.ToLower(strings.TrimSpace(id)) || strings.ContainsAny(id, ":|/\\") || registry.byID[id] != nil {
			panic("invalid or duplicate provider ID: " + id)
		}
		if definition.SearchMode != "local" && definition.SearchMode != "online" && definition.SearchMode != "paged" {
			panic("invalid provider search mode: " + id)
		}
		registry.byID[id] = provider
		registry.addAlias(id, id)
		for _, alias := range definition.Aliases {
			registry.addAlias(alias, id)
		}
		for _, host := range definition.Hosts {
			if previous := registry.hosts[host]; previous != "" && previous != id {
				panic("duplicate provider host: " + host)
			}
			registry.hosts[host] = id
		}
	}
	return registry
}

func (registry *providerRegistry) addAlias(alias, id string) {
	alias = strings.ToLower(strings.TrimSpace(alias))
	if previous := registry.aliases[alias]; previous != "" && previous != id {
		panic("duplicate provider alias: " + alias)
	}
	registry.aliases[alias] = id
}

func canonicalProviderSource(source string) string {
	trimmed := strings.TrimSpace(source)
	if id := providers.aliases[strings.ToLower(trimmed)]; id != "" {
		return id
	}
	return trimmed
}

func findProvider(source string) (Provider, bool) {
	provider, found := providers.byID[canonicalProviderSource(source)]
	return provider, found
}

func isProviderSource(source string) bool {
	_, found := findProvider(source)
	return found
}

func ProviderSources() []SourceInfo {
	result := make([]SourceInfo, 0, len(providers.ordered))
	for _, provider := range providers.ordered {
		info := provider.Definition().SourceInfo
		_, info.SearchSuggestions = provider.(ProviderSuggestions)
		info.MetadataFields = []string{}
		if metadata, supported := provider.(ProviderMetadata); supported {
			info.MetadataFields = metadata.MetadataFields()
		}
		result = append(result, info)
	}
	return result
}

func ProviderManifest() map[string]any {
	rankings := make(map[string]string, len(rankingBoards))
	for _, board := range rankingBoards {
		rankings[board.ID] = board.Source
	}
	return map[string]any{"sources": ProviderSources(), "rankingSources": rankings}
}

func providerDramaID(source, sourceID string) string {
	return source + ":" + strings.TrimSpace(sourceID)
}

func providerChapterID(source, sourceID, chapterKey string) string {
	return source + ":" + strings.TrimSpace(sourceID) + ":" + strings.TrimSpace(chapterKey)
}

func splitProviderDramaID(id string) (source, sourceID string, ok bool) {
	source, sourceID, ok = strings.Cut(strings.TrimSpace(id), ":")
	source = canonicalProviderSource(source)
	if !ok || strings.TrimSpace(sourceID) == "" || !isProviderSource(source) {
		return "", "", false
	}
	return source, strings.TrimSpace(sourceID), true
}

func (d *Downloader) providerChapters(ctx context.Context, source, id string) (string, []Chapter, error) {
	provider, found := findProvider(source)
	if !found {
		return "", nil, fmt.Errorf("unsupported provider source: %s", source)
	}
	drama, chapters, err := provider.Detail(ctx, d, Drama{ID: providerDramaID(provider.Definition().ID, id), Source: provider.Definition().ID, SourceID: id})
	return drama.DisplayTitle(), chapters, err
}

func (d *Downloader) providerBaseURL(source string) string {
	provider, found := findProvider(source)
	if !found {
		return "https://d2pypzndaqisk.cloudfront.net"
	}
	return strings.TrimRight(firstNonEmpty(d.cfg.ProviderURLs[provider.Definition().ID], provider.Definition().BaseURL), "/")
}

func providerSourceForURL(raw string) string {
	parsed, err := url.Parse(raw)
	if err != nil {
		return ""
	}
	host := strings.ToLower(parsed.Hostname())
	if source := providers.hosts[host]; source != "" {
		return source
	}
	for _, provider := range providers.ordered {
		for _, suffix := range provider.Definition().HostSuffixes {
			if strings.HasSuffix(host, suffix) {
				return provider.Definition().ID
			}
		}
	}
	return ""
}

func (d *Downloader) resolveProviderMedia(ctx context.Context, task Task) (providerMedia, error) {
	task.Chapter.Source = canonicalProviderSource(task.Chapter.Source)
	if task.Chapter.Source == "" {
		task.Chapter.Source = sourceFromDramaID(task.DramaID)
	}
	provider, found := findProvider(task.Chapter.Source)
	if !found {
		return providerMedia{}, fmt.Errorf("unsupported provider source: %s", task.Chapter.Source)
	}
	return provider.Resolve(ctx, d, task)
}
