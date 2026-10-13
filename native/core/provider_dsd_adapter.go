package core

import (
	"context"
)

type dsdProvider struct{}

var dsdDefinition = ProviderDefinition{
	SourceInfo: SourceInfo{ID: sourceDSD, Name: "帝果", Description: "分类视频 · 在线搜索", GroupID: sourceDSD, GroupName: "帝果", EntryName: "帝果", Restricted: true, SearchMode: "paged"},
	BaseURL:    dsdBaseURL, Aliases: []string{"dsd.com.se", "www.dsd.com.se"}, Hosts: []string{"dsd.com.se", "www.dsd.com.se"},
	PreserveMediaHost: false, AllowEmptyCatalog: true, PreserveEpisodeCount: false, SinglePageRankings: true,
	RankingOrder: 5,
}

func (dsdProvider) Definition() *ProviderDefinition { return &dsdDefinition }

func (dsdProvider) ValidCategory(category string) bool {
	return webProviderNumericID.MatchString(category)
}

func (dsdProvider) Categories(ctx context.Context, d *Downloader, force bool) ([]nativeCategory, error) {
	return d.fetchDSDCategories(ctx, force)
}

func (dsdProvider) Catalog(ctx context.Context, d *Downloader, request providerCatalogRequest) (providerCatalogPage, error) {
	category := request.Category
	if request.Query != "" {
		category = ""
	}
	items, more, err := d.fetchDSDCatalogPage(ctx, request.Page, category, request.Query)
	return providerCatalogPage{Items: items, HasMore: more, Page: request.Page}, err
}

func (dsdProvider) Detail(ctx context.Context, d *Downloader, drama Drama) (Drama, []Chapter, error) {
	return d.fetchDSDDetail(ctx, drama.SourceID)
}

func (dsdProvider) Resolve(ctx context.Context, d *Downloader, task Task) (providerMedia, error) {
	return d.resolveDSDMedia(ctx, task)
}

func (dsdProvider) Rankings(ctx context.Context, d *Downloader, board rankingBoard, page int) (rankingPage, error) {
	return d.fetchCatalogRankingPage(ctx, board, page)
}

var dsdBoards = []rankingBoard{
	{ID: "dsd-catalog", Source: sourceDSD, Name: "目录榜", Description: "帝果分类目录聚合顺序，按源站返回顺序展示。"},
}

func (dsdProvider) Boards() []rankingBoard { return dsdBoards }
