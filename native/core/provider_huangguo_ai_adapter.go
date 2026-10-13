package core

import (
	"context"
	"errors"
	"net/url"
)

type huangguoAIProvider struct{}

var huangguoAIDefinition = ProviderDefinition{
	SourceInfo: SourceInfo{ID: sourceHuangguoAI, Name: "黄果 AI", Description: "AI 短剧", GroupID: "huangguo", GroupName: "黄果", EntryName: "AI", Restricted: true, SearchMode: "local"},
	BaseURL:    huangguoAIBaseURL, Aliases: []string{"huangguo", "huangguoai.com"}, Hosts: []string{"huangguoai.com"}, HostSuffixes: []string{".ediayikma.cc", ".agdkczeyx.cc"},
	StaticCategories: true, SinglePageRankings: true,
	RankingOrder: 2,
}

func (huangguoAIProvider) Definition() *ProviderDefinition { return &huangguoAIDefinition }
func (huangguoAIProvider) ValidCategory(category string) bool {
	for _, entry := range nativeAICategories {
		if category == entry.ID {
			return true
		}
	}
	return false
}
func (huangguoAIProvider) Categories(context.Context, *Downloader, bool) ([]nativeCategory, error) {
	return nativeAICategories, nil
}
func (huangguoAIProvider) Catalog(ctx context.Context, d *Downloader, request providerCatalogRequest) (providerCatalogPage, error) {
	items, more, err := d.fetchHuangguoAICatalogPage(ctx, request.Page, request.Category)
	return providerCatalogPage{Items: items, HasMore: more, Page: request.Page}, err
}
func (huangguoAIProvider) Detail(ctx context.Context, d *Downloader, drama Drama) (Drama, []Chapter, error) {
	return d.fetchHuangguoAIDetail(ctx, drama.SourceID)
}
func (huangguoAIProvider) Resolve(ctx context.Context, d *Downloader, task Task) (providerMedia, error) {
	return d.resolveProviderPageMedia(ctx, task, parseAIVideoURL)
}
func (huangguoAIProvider) CoverAddress(ctx context.Context, d *Downloader, drama nativeDrama) (string, error) {
	if !rankingSourceID.MatchString(drama.SourceID) {
		return "", errors.New("无效的黄果剧集 ID")
	}
	return d.huangguoPageCoverAddress(ctx, drama, "/detail/"+url.PathEscape(drama.SourceID)+"/")
}
func (huangguoAIProvider) Rankings(ctx context.Context, d *Downloader, board rankingBoard, page int) (rankingPage, error) {
	if page != 1 {
		return rankingPage{}, errors.New("该榜单只有一页")
	}
	pageURL := d.providerBaseURL(sourceHuangguoAI) + "/ranks/" + board.path + "/"
	body, err := d.fetchProviderText(ctx, pageURL, d.providerBaseURL(sourceHuangguoAI)+"/")
	if err != nil {
		return rankingPage{}, err
	}
	return parseHuangguoRanking(body, board)
}

var huangguoAIBoards = []rankingBoard{
	{ID: "huangguo-hot", Source: sourceHuangguoAI, Name: "热播榜", Description: "黄果站点热播 TOP 20；每日更新。", path: "hot"},
	{ID: "huangguo-recommend", Source: sourceHuangguoAI, Name: "推荐榜", Description: "黄果站点推荐 TOP 20。", path: "recommend"},
	{ID: "huangguo-potential", Source: sourceHuangguoAI, Name: "潜力榜", Description: "黄果站点潜力 TOP 20。", path: "potential"},
}

func (huangguoAIProvider) Boards() []rankingBoard { return huangguoAIBoards }
