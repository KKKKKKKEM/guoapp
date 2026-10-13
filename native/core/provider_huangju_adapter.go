package core

import (
	"context"
	"strings"
)

type huangjuProvider struct{}

var huangjuDefinition = ProviderDefinition{
	SourceInfo: SourceInfo{ID: sourceHuangju, Name: "剧果", Description: "热门 · 最新 · 分类短剧", GroupID: sourceHuangju, GroupName: "剧果", EntryName: "剧果", Restricted: true, SearchMode: "paged"},
	BaseURL:    huangjuBaseURL, Aliases: []string{"huangju.net", "api.huangju.net"}, Hosts: []string{"huangju.net", "www.huangju.net", "api.huangju.net"},
	PreserveMediaHost: true, AllowEmptyCatalog: true, PreserveEpisodeCount: true, SinglePageRankings: false,
	RankingOrder: 3,
}

func (huangjuProvider) Definition() *ProviderDefinition { return &huangjuDefinition }

func (huangjuProvider) ValidCategory(category string) bool {
	return category == huangjuNewestCategory || validHuangjuID(category) && !strings.HasPrefix(category, "@")
}

func (huangjuProvider) Categories(ctx context.Context, d *Downloader, force bool) ([]nativeCategory, error) {
	return d.fetchHuangjuCategories(ctx)
}

func (huangjuProvider) Catalog(ctx context.Context, d *Downloader, request providerCatalogRequest) (providerCatalogPage, error) {
	category := request.Category
	if request.Query != "" {
		category = ""
	}
	items, more, err := d.fetchHuangjuCatalogPage(ctx, request.Page, category, request.Query)
	return providerCatalogPage{Items: items, HasMore: more, Page: request.Page}, err
}

func (huangjuProvider) Detail(ctx context.Context, d *Downloader, drama Drama) (Drama, []Chapter, error) {
	return d.fetchHuangjuDetail(ctx, drama.SourceID)
}

func (huangjuProvider) Resolve(ctx context.Context, d *Downloader, task Task) (providerMedia, error) {
	return d.resolveHuangjuMedia(ctx, task)
}

func (huangjuProvider) Rankings(ctx context.Context, d *Downloader, board rankingBoard, page int) (rankingPage, error) {
	return d.fetchCatalogRankingPage(ctx, board, page)
}

var huangjuBoards = []rankingBoard{
	{ID: "huangju-hot", Source: sourceHuangju, Name: "热门榜", Description: "剧果目录热门顺序，按源站返回顺序展示。"},
	{ID: "huangju-new", Source: sourceHuangju, Name: "最新榜", Description: "剧果最新目录顺序，按源站返回顺序展示。", path: huangjuNewestCategory},
}

func (huangjuProvider) Boards() []rankingBoard { return huangjuBoards }
