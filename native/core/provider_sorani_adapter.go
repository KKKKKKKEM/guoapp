package core

import (
	"context"
)

type soraniProvider struct{}

var soraniDefinition = ProviderDefinition{
	SourceInfo: SourceInfo{ID: sourceSorani, Name: "青空", Description: "番剧 · 剧场动画 · 特摄", GroupID: sourceSorani, GroupName: "青空", EntryName: "青空", Restricted: false, SearchMode: "paged"},
	BaseURL:    soraniSiteBaseURL, Aliases: []string{"sorani.net", "www.sorani.net", "api.sorani.cc", "sorani.cc"}, Hosts: []string{"sorani.net", "www.sorani.net", "api.sorani.cc", "sorani.cc"},
	PreserveMediaHost: false, AllowEmptyCatalog: true, PreserveEpisodeCount: false, SinglePageRankings: false,
}

func (soraniProvider) Definition() *ProviderDefinition { return &soraniDefinition }

func (soraniProvider) ValidCategory(category string) bool { return validSoraniCategory(category) }

func (soraniProvider) Categories(ctx context.Context, d *Downloader, force bool) ([]nativeCategory, error) {
	return d.fetchSoraniCategories(), nil
}

func (soraniProvider) Catalog(ctx context.Context, d *Downloader, request providerCatalogRequest) (providerCatalogPage, error) {
	category := request.Category
	if request.Query != "" {
		category = ""
	}
	items, more, err := d.fetchSoraniCatalogPage(ctx, request.Page, category, request.Query)
	return providerCatalogPage{Items: items, HasMore: more, Page: request.Page}, err
}

func (soraniProvider) Detail(ctx context.Context, d *Downloader, drama Drama) (Drama, []Chapter, error) {
	return d.fetchSoraniDetail(ctx, drama.SourceID)
}

func (soraniProvider) Resolve(ctx context.Context, d *Downloader, task Task) (providerMedia, error) {
	return d.resolveSoraniMedia(ctx, task)
}
