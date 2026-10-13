package core

import (
	"context"
)

type guipianProvider struct{}

var guipianDefinition = ProviderDefinition{
	SourceInfo: SourceInfo{ID: sourceGuipian, Name: "鬼片", Description: "鬼片 · 电视剧 · 动漫", GroupID: sourceGuipian, GroupName: "鬼片", EntryName: "鬼片", Restricted: false, SearchMode: "paged"},
	BaseURL:    guipianSiteBaseURL, Aliases: []string{"guipianwu.com", "www.guipianwu.com"}, Hosts: []string{"guipianwu.com", "www.guipianwu.com"},
	PreserveMediaHost: false, AllowEmptyCatalog: true, PreserveEpisodeCount: false, SinglePageRankings: false,
}

func (guipianProvider) Definition() *ProviderDefinition { return &guipianDefinition }

func (guipianProvider) ValidCategory(category string) bool { return validGuipianCategory(category) }

func (guipianProvider) Categories(ctx context.Context, d *Downloader, force bool) ([]nativeCategory, error) {
	return d.fetchGuipianCategories(), nil
}

func (guipianProvider) Catalog(ctx context.Context, d *Downloader, request providerCatalogRequest) (providerCatalogPage, error) {
	category := request.Category
	if request.Query != "" {
		category = ""
	}
	items, more, err := d.fetchGuipianCatalogPage(ctx, request.Page, category, request.Query)
	return providerCatalogPage{Items: items, HasMore: more, Page: request.Page}, err
}

func (guipianProvider) Detail(ctx context.Context, d *Downloader, drama Drama) (Drama, []Chapter, error) {
	return d.fetchGuipianDetail(ctx, drama.SourceID)
}

func (guipianProvider) Resolve(ctx context.Context, d *Downloader, task Task) (providerMedia, error) {
	return d.resolveGuipianMedia(ctx, task)
}
