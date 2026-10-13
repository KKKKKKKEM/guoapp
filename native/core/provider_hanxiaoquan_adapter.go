package core

import (
	"context"
)

type hanxiaoquanProvider struct{}

var hanxiaoquanDefinition = ProviderDefinition{
	SourceInfo: SourceInfo{ID: sourceHanxiaoquan, Name: "韩小圈", Description: "韩剧 · 韩国电影 · 综艺动漫", GroupID: sourceHanxiaoquan, GroupName: "韩小圈", EntryName: "韩小圈", Restricted: false, SearchMode: "paged"},
	BaseURL:    hanxiaoquanSiteBaseURL, Aliases: []string{"jennyhow.com", "www.jennyhow.com"}, Hosts: []string{"jennyhow.com", "www.jennyhow.com"},
	PreserveMediaHost: false, AllowEmptyCatalog: true, PreserveEpisodeCount: false, SinglePageRankings: false,
}

func (hanxiaoquanProvider) Definition() *ProviderDefinition { return &hanxiaoquanDefinition }

func (hanxiaoquanProvider) ValidCategory(category string) bool {
	return validHanxiaoquanCategory(category)
}

func (hanxiaoquanProvider) Categories(ctx context.Context, d *Downloader, force bool) ([]nativeCategory, error) {
	return d.fetchHanxiaoquanCategories(), nil
}

func (hanxiaoquanProvider) Catalog(ctx context.Context, d *Downloader, request providerCatalogRequest) (providerCatalogPage, error) {
	category := request.Category
	if request.Query != "" {
		category = ""
	}
	items, more, err := d.fetchHanxiaoquanCatalogPage(ctx, request.Page, category, request.Query)
	return providerCatalogPage{Items: items, HasMore: more, Page: request.Page}, err
}

func (hanxiaoquanProvider) Detail(ctx context.Context, d *Downloader, drama Drama) (Drama, []Chapter, error) {
	return d.fetchHanxiaoquanDetail(ctx, drama.SourceID)
}

func (hanxiaoquanProvider) Resolve(ctx context.Context, d *Downloader, task Task) (providerMedia, error) {
	return d.resolveHanxiaoquanMedia(ctx, task)
}
