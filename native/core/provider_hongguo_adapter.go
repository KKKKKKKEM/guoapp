package core

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

type hongguoProvider struct{}

var hongguoDefinition = ProviderDefinition{
	SourceInfo: SourceInfo{ID: sourceHongguo, Name: "红果", Description: "短剧 · 漫剧 · AI 剧", GroupID: sourceHongguo, GroupName: "红果", EntryName: "红果", Default: true, SearchMode: "online"},
	BaseURL:    hongguoBaseURL, Aliases: []string{"hongguoduanju.com"}, Hosts: []string{"hongguoduanju.com", "www.hongguoduanju.com"},
	StaticCategories: true, IncrementalCatalog: true,
}

func (hongguoProvider) Definition() *ProviderDefinition { return &hongguoDefinition }

func (hongguoProvider) ValidCategory(category string) bool {
	for _, genre := range hongguoAppGenres {
		if category == genre.key {
			return true
		}
	}
	return false
}

func (hongguoProvider) Categories(_ context.Context, _ *Downloader, _ bool) ([]nativeCategory, error) {
	categories := make([]nativeCategory, 0, len(hongguoAppGenres))
	for _, genre := range hongguoAppGenres {
		categories = append(categories, nativeCategory{ID: genre.key, Name: genre.name})
	}
	return categories, nil
}

func (hongguoProvider) Catalog(ctx context.Context, d *Downloader, request providerCatalogRequest) (providerCatalogPage, error) {
	result := providerCatalogPage{Page: request.Page}
	if request.Query != "" {
		entry, err := d.searchHongguoDramas(ctx, request.Query)
		if err != nil {
			return result, err
		}
		result.Items, result.Warning, result.Page = entry.Dramas, entry.Warning, 1
		if entry.Limited && result.Warning == "" {
			result.Warning = "已显示当前可获取的匹配结果，使用更完整的剧名可继续查找"
		}
		return result, nil
	}
	if request.Page > 1 {
		ctx = context.WithValue(ctx, libraryMoreKey{}, true)
	}
	items, err := d.fetchHongguoAppCatalogCategory(ctx, request.Category)
	state := d.hongguoCatalogSnapshot()
	result.Items, result.hongguo, result.HasMore = items, state, hongguoCatalogHasMore(state)
	if request.Category != "" && state != nil {
		result.HasMore = !state.Feeds["category:"+request.Category].Exhausted
	}
	if len(items) == 0 && err != nil && ctx.Err() == nil && (request.Category == "" || request.Category == "short_play") {
		var totalPages int
		result.Items, totalPages, err = d.fetchHongguoCategoryPage(ctx, "real-drama?page="+strconv.Itoa(request.Page), "真人剧")
		result.HasMore = request.Page < totalPages
	}
	return result, err
}

func (hongguoProvider) Detail(ctx context.Context, d *Downloader, drama Drama) (Drama, []Chapter, error) {
	title, chapters, err := d.fetchHongguoChapters(ctx, drama.SourceID)
	if title != "" && title != "短剧" {
		drama.Title = title
	}
	return d.hongguoCachedDrama(drama), chapters, err
}

func (hongguoProvider) Resolve(ctx context.Context, d *Downloader, task Task) (providerMedia, error) {
	if strings.HasPrefix(task.Chapter.VideoURL, "hongguo-cenc://") {
		return d.resolveHongguoMedia(ctx, task)
	}
	return d.resolveDirectProviderMedia(ctx, task)
}

var hongguoMetadataFields = []string{"onlineDate"}

func (hongguoProvider) MetadataFields() []string { return hongguoMetadataFields }

func (hongguoProvider) Metadata(ctx context.Context, d *Downloader, drama nativeDrama) (Drama, error) {
	if !hongguoNumericID.MatchString(drama.SourceID) {
		return Drama{}, errors.New("红果剧集 ID 无效")
	}
	body, err := d.fetchProviderText(ctx, hongguoBaseURL+"/detail?series_id="+url.QueryEscape(drama.SourceID), hongguoBaseURL+"/")
	if err != nil {
		return Drama{}, err
	}
	return parseHongguoSortDetail(body, drama.SourceID)
}

func (hongguoProvider) CoverAddress(ctx context.Context, d *Downloader, drama nativeDrama) (string, error) {
	id := drama.SourceID
	if !hongguoNumericID.MatchString(id) {
		return "", errors.New("无效的红果剧集 ID")
	}
	result, err := d.hongguoAppRequest(ctx, http.MethodPost, "/novel/player/video_detail/v1/", nil, map[string]any{"series_id": id})
	if err != nil {
		return "", err
	}
	row := nestedMap(result, "data", "video_data")
	if mapString(row, "series_id_str", "series_id") != id {
		return "", errors.New("红果详情与请求剧集不符")
	}
	return hongguoCoverAddress(mapString(row, "series_cover", "cover")), nil
}

func (hongguoProvider) Rankings(ctx context.Context, d *Downloader, board rankingBoard, page int) (rankingPage, error) {
	return d.fetchHongguoRankingPage(ctx, board, page)
}

func (hongguoProvider) Suggestions(ctx context.Context, d *Downloader, query string) ([]string, error) {
	items, err := d.hongguoSearchSuggestions(ctx, query)
	names := make([]string, 0, len(items))
	for _, item := range items {
		names = append(names, item.Name)
	}
	return names, err
}

var hongguoBoards = []rankingBoard{
	{ID: "hongguo-hot", Source: sourceHongguo, Name: "总热播榜", Description: "红果观看、互动等综合热度；每日更新。", path: "hot-drama", upstreamKey: "hongguo"},
	{ID: "hongguo-real", Source: sourceHongguo, Name: "真人剧榜", Description: "红果真人剧热播榜；每日更新。", path: "hot-real-drama", upstreamKey: "real"},
	{ID: "hongguo-comic", Source: sourceHongguo, Name: "漫剧榜", Description: "红果漫剧热播榜；每日更新。", path: "hot-comic-drama", upstreamKey: "comic"},
	{ID: "hongguo-ai", Source: sourceHongguo, Name: "AI剧榜", Description: "红果 AI 剧热播榜；每日更新。", path: "hot-ai-drama", upstreamKey: "ai"},
}

func (hongguoProvider) Boards() []rankingBoard { return hongguoBoards }
