package core

import (
	"context"
	"errors"
	"net/url"
	"strings"
)

type cloudfrontProvider struct{}

var cloudfrontDefinition = ProviderDefinition{
	SourceInfo: SourceInfo{ID: sourceCloudFront, Name: "黄果旧版", Description: "旧 API 剧库", GroupID: "huangguo", GroupName: "黄果", EntryName: "旧版", Restricted: true, SearchMode: "local"},
	BaseURL:    "https://d2pypzndaqisk.cloudfront.net",
}

func (cloudfrontProvider) Definition() *ProviderDefinition { return &cloudfrontDefinition }
func (cloudfrontProvider) ValidCategory(category string) bool {
	return strings.TrimSpace(category) == category
}
func (cloudfrontProvider) Categories(ctx context.Context, d *Downloader, _ bool) ([]nativeCategory, error) {
	var tabs legacyTabList
	if err := d.fetchAPI(ctx, "/api/app/playlet-tab/all", nil, &tabs); err != nil {
		return nil, err
	}
	var result []nativeCategory
	for _, tab := range tabs {
		if validNativeCategory(sourceCloudFront, tab.ID) && tab.ID != "" && tab.Name != "" {
			result = append(result, nativeCategory{ID: tab.ID, Name: tab.Name})
		}
	}
	return result, nil
}
func (cloudfrontProvider) Catalog(ctx context.Context, d *Downloader, request providerCatalogRequest) (providerCatalogPage, error) {
	items, more, err := d.fetchLegacyCatalogCategoryPage(ctx, request.Page, request.Category)
	return providerCatalogPage{Items: items, HasMore: more, Page: request.Page}, err
}
func (cloudfrontProvider) Detail(ctx context.Context, d *Downloader, drama Drama) (Drama, []Chapter, error) {
	return d.fetchLegacyDetail(ctx, drama.SourceID)
}
func (cloudfrontProvider) Resolve(ctx context.Context, d *Downloader, task Task) (providerMedia, error) {
	return d.resolveLegacyMedia(ctx, task)
}
func (cloudfrontProvider) CoverAddress(ctx context.Context, d *Downloader, drama nativeDrama) (string, error) {
	id := drama.SourceID
	if !rankingSourceID.MatchString(id) {
		return "", errors.New("无效的黄果剧集 ID")
	}
	var raw Drama
	if err := d.fetchAPI(ctx, "/api/app/playlet/detail/"+url.PathEscape(id), nil, &raw); err != nil {
		return "", err
	}
	if raw.ID != "" && raw.ID != id && raw.ID != drama.ID {
		return "", errors.New("黄果详情与请求剧集不符")
	}
	for _, value := range []any{raw.Cover, raw.CoverURL, raw.CoverURLSnake, raw.Image, raw.ImageURL, raw.ImageURLSnake, raw.Img, raw.Pic, raw.Picture, raw.Poster, raw.Thumb, raw.Thumbnail} {
		if address := legacyCoverURL(value); address != "" {
			return address, nil
		}
	}
	return "", errors.New("详情暂未返回海报地址")
}

func (cloudfrontProvider) CoverReferer(d *Downloader, address string) string {
	if parsed, err := url.Parse(address); err == nil && (strings.HasSuffix(strings.ToLower(parsed.Hostname()), ".zdmhyg.cn") || strings.EqualFold(parsed.Hostname(), "pic.tuafjz.cn")) {
		return d.providerBaseURL(sourceHuangguoAI) + "/"
	}
	return d.providerBaseURL(sourceCloudFront) + "/"
}
