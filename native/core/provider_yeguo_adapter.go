package core

import (
	"context"
	"strings"
)

type yeguoProvider struct{}

var yeguoDefinition = ProviderDefinition{
	SourceInfo: SourceInfo{ID: sourceYeguo, Name: "野果", Description: "分类短剧 · 在线搜索", GroupID: sourceYeguo, GroupName: "野果", EntryName: "野果", Restricted: true, SearchMode: "paged"},
	BaseURL:    yeguoBaseURL, Aliases: []string{"ygdj7.com", "www.ygdj7.com", "analyze.buxefaex.cc", "delta.ygrwdsgt.cc", "yeguodj.com", "www.yeguodj.com"}, Hosts: []string{"ygdj7.com", "www.ygdj7.com", "analyze.buxefaex.cc", "delta.ygrwdsgt.cc", "yeguodj.com", "www.yeguodj.com"}, HostSuffixes: []string{".buxefaex.cc", ".fzchosdi.cc"},
	PreserveMediaHost: true, AllowEmptyCatalog: true, PreserveEpisodeCount: true, SinglePageRankings: false,
	RankingOrder: 4,
}

func (yeguoProvider) Definition() *ProviderDefinition { return &yeguoDefinition }

func (yeguoProvider) ValidCategory(category string) bool { return validYeguoCategory(category) }

func (yeguoProvider) Categories(ctx context.Context, d *Downloader, force bool) ([]nativeCategory, error) {
	return d.fetchYeguoCategories(ctx)
}

func (yeguoProvider) Catalog(ctx context.Context, d *Downloader, request providerCatalogRequest) (providerCatalogPage, error) {
	category := request.Category
	if request.Query != "" {
		category = ""
	}
	items, more, err := d.fetchYeguoCatalogPage(ctx, request.Page, category, request.Query)
	return providerCatalogPage{Items: items, HasMore: more, Page: request.Page}, err
}

func (yeguoProvider) Detail(ctx context.Context, d *Downloader, drama Drama) (Drama, []Chapter, error) {
	return d.fetchYeguoDetail(ctx, drama.SourceID)
}

func (yeguoProvider) Resolve(ctx context.Context, d *Downloader, task Task) (providerMedia, error) {
	return d.resolveYeguoMedia(ctx, task)
}

func (yeguoProvider) Rankings(ctx context.Context, d *Downloader, board rankingBoard, page int) (rankingPage, error) {
	return d.fetchCatalogRankingPage(ctx, board, page)
}

func (yeguoProvider) RankingCategory(ctx context.Context, d *Downloader, category string) string {
	if category != "recommend" {
		return category
	}
	categories, err := d.fetchYeguoCategories(ctx)
	if err == nil {
		for _, item := range categories {
			if strings.HasPrefix(item.ID, "recommend:") {
				return item.ID
			}
		}
	}
	return ""
}

var yeguoBoards = []rankingBoard{
	{ID: "yeguo-recommend", Source: sourceYeguo, Name: "目录榜", Description: "野果默认目录顺序，按源站返回顺序展示。"},
}

func (yeguoProvider) Boards() []rankingBoard { return yeguoBoards }
