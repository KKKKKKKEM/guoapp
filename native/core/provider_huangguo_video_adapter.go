package core

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"strconv"
	"strings"
)

type huangguoVideoProvider struct{}

var huangguoVideoDefinition = ProviderDefinition{
	SourceInfo: SourceInfo{ID: sourceHuangguoVideo, Name: "黄果视频", Description: "视频剧集", GroupID: "huangguo", GroupName: "黄果", EntryName: "视频", Restricted: true, SearchMode: "local"},
	BaseURL:    huangguoVideoBaseURL, Aliases: []string{"huangguo.video"}, Hosts: []string{"huangguo.video"},
}

func (huangguoVideoProvider) Definition() *ProviderDefinition { return &huangguoVideoDefinition }
func (huangguoVideoProvider) ValidCategory(category string) bool {
	id, err := strconv.Atoi(category)
	return err == nil && id > 0
}
func (huangguoVideoProvider) Categories(ctx context.Context, d *Downloader, _ bool) ([]nativeCategory, error) {
	body, err := d.fetchProviderText(ctx, d.providerBaseURL(sourceHuangguoVideo)+"/videos", d.providerBaseURL(sourceHuangguoVideo)+"/")
	if err != nil {
		return nil, err
	}
	return parseHuangguoVideoCategories(body), nil
}
func (huangguoVideoProvider) Catalog(ctx context.Context, d *Downloader, request providerCatalogRequest) (providerCatalogPage, error) {
	address := fmt.Sprintf("%s/videos?page=%d", d.providerBaseURL(sourceHuangguoVideo), request.Page)
	if request.Category != "" {
		address += "&category=" + url.QueryEscape(request.Category)
	}
	body, err := d.fetchProviderText(ctx, address, d.providerBaseURL(sourceHuangguoVideo)+"/")
	result := providerCatalogPage{Page: request.Page}
	if err == nil {
		result.Items = parseHuangguoVideoCards(body, address)
	}
	result.HasMore = len(result.Items) >= 20
	return result, err
}
func (huangguoVideoProvider) Detail(ctx context.Context, d *Downloader, drama Drama) (Drama, []Chapter, error) {
	return d.fetchHuangguoVideoDetail(ctx, drama.SourceID)
}
func (huangguoVideoProvider) Resolve(ctx context.Context, d *Downloader, task Task) (providerMedia, error) {
	return d.resolveProviderPageMedia(ctx, task, parseDataHLS)
}
func (huangguoVideoProvider) CoverAddress(ctx context.Context, d *Downloader, drama nativeDrama) (string, error) {
	parts := strings.Split(drama.SourceID, "/")
	if len(parts) == 1 {
		parts = []string{"series", drama.SourceID}
	}
	if len(parts) != 2 || (parts[0] != "series" && parts[0] != "video") || !rankingSourceID.MatchString(parts[1]) {
		return "", errors.New("无效的黄果剧集 ID")
	}
	return d.huangguoPageCoverAddress(ctx, drama, "/"+parts[0]+"/"+url.PathEscape(parts[1]))
}
