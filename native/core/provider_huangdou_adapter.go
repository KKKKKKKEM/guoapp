package core

import (
	"context"
	"fmt"
	"net/url"
	"strconv"
	"strings"
)

type huangdouProvider struct{}

var huangdouDefinition = ProviderDefinition{
	SourceInfo: SourceInfo{ID: sourceHuangdou, Name: "黄豆", Description: "精选短剧", GroupID: sourceHuangdou, GroupName: "黄豆", EntryName: "黄豆", Restricted: true, SearchMode: "local"},
	BaseURL:    huangdouBaseURL, Aliases: []string{"tideember.cc", "xqjurgek.top"}, Hosts: []string{"tideember.cc", "xqjurgek.top"}, StaticCategories: true,
	RankingOrder: 1,
}

func (huangdouProvider) Definition() *ProviderDefinition { return &huangdouDefinition }
func (huangdouProvider) ValidCategory(string) bool       { return false }
func (huangdouProvider) Categories(context.Context, *Downloader, bool) ([]nativeCategory, error) {
	return nil, nil
}

func (huangdouProvider) Catalog(ctx context.Context, d *Downloader, request providerCatalogRequest) (providerCatalogPage, error) {
	var decoded any
	err := newHuangdouAPIClient(d).call(ctx, "/drama/list", map[string]any{"page": strconv.Itoa(request.Page), "page_size": "30"}, &decoded)
	result := providerCatalogPage{Page: request.Page}
	if err == nil {
		rows := huangdouList(decoded)
		for _, row := range rows {
			if drama := huangdouDramaFromMap(row); drama.ID != "" {
				result.Items = append(result.Items, drama)
			}
		}
		result.HasMore = len(rows) >= 30
	}
	return result, err
}

func (huangdouProvider) Detail(ctx context.Context, d *Downloader, drama Drama) (Drama, []Chapter, error) {
	title, chapters, err := d.fetchHuangdouChapters(ctx, drama.SourceID)
	if title != "" && title != "短剧" {
		drama.Title = title
	}
	if err == nil {
		if row, detailErr := d.huangdouDetail(ctx, drama.SourceID); detailErr == nil {
			if fresh := huangdouDramaFromMap(row); fresh.ID == drama.ID {
				drama = mergeDramaMetadata(drama, fresh)
			}
		}
	}
	return drama, chapters, err
}

func (huangdouProvider) Resolve(ctx context.Context, d *Downloader, task Task) (providerMedia, error) {
	_, id, valid := splitProviderDramaID(task.DramaID)
	if !valid {
		return d.resolveDirectProviderMedia(ctx, task)
	}
	sequence, err := strconv.Atoi(task.Chapter.EpisodeString(task.Index))
	if err != nil || sequence < 1 {
		return providerMedia{}, fmt.Errorf("黄豆集数无效")
	}
	client := newHuangdouAPIClient(d)
	media, err := d.resolveHuangdouPlayback(ctx, client, id, sequence)
	if err != nil {
		return providerMedia{}, err
	}
	media.Referer = client.host + "/home"
	return d.finishProviderMedia(ctx, media, sourceHuangdou)
}

var huangdouMetadataFields = []string{"heat", "vip"}

func (huangdouProvider) MetadataFields() []string { return huangdouMetadataFields }

func (huangdouProvider) Metadata(ctx context.Context, d *Downloader, drama nativeDrama) (Drama, error) {
	row, err := d.huangdouDetail(ctx, drama.SourceID)
	if err != nil {
		return Drama{}, err
	}
	raw := huangdouDramaFromMap(row)
	if raw.Heat == "" && drama.Heat == "" {
		var decoded any
		err = newHuangdouAPIClient(d).call(ctx, "/drama/list", map[string]any{"keywords": firstNonEmpty(raw.Title, drama.Title), "page": "1", "page_size": "50"}, &decoded)
		if err != nil {
			return Drama{}, err
		}
		for _, candidate := range huangdouList(decoded) {
			if strings.TrimPrefix(mapString(candidate, "id", "drama_id"), "rp_") == drama.SourceID {
				raw = mergeDramaMetadata(huangdouDramaFromMap(candidate), raw)
				break
			}
		}
	}
	return raw, nil
}

func (huangdouProvider) CoverAddress(ctx context.Context, d *Downloader, drama nativeDrama) (string, error) {
	row, err := d.huangdouDetail(ctx, drama.SourceID)
	if err != nil {
		return "", err
	}
	fresh := nativeNormalize(huangdouDramaFromMap(row))
	if fresh.ID != drama.ID {
		return "", fmt.Errorf("黄豆详情与请求剧集不符")
	}
	return fresh.Cover, nil
}

func (huangdouProvider) Rankings(ctx context.Context, d *Downloader, board rankingBoard, page int) (rankingPage, error) {
	var decoded any
	err := newHuangdouAPIClient(d).call(ctx, "/drama/rank", map[string]any{"tab": board.upstreamKey, "page": strconv.Itoa(page)}, &decoded)
	if err != nil {
		return rankingPage{}, err
	}
	return parseHuangdouRanking(decoded, page)
}

var huangdouBoards = []rankingBoard{
	{ID: "huangdou-all", Source: sourceHuangdou, Name: "总榜", Description: "黄豆短剧总榜，保留站点返回的顺序。", upstreamKey: "all"},
	{ID: "huangdou-mogai", Source: sourceHuangdou, Name: "魔改榜", Description: "黄豆站点魔改榜。", upstreamKey: "mogai"},
	{ID: "huangdou-search", Source: sourceHuangdou, Name: "搜索榜", Description: "黄豆站点搜索榜。", upstreamKey: "search"},
	{ID: "huangdou-favorite", Source: sourceHuangdou, Name: "收藏榜", Description: "黄豆站点收藏榜。", upstreamKey: "favorite"},
	{ID: "huangdou-finish", Source: sourceHuangdou, Name: "完结榜", Description: "黄豆站点完结榜。", upstreamKey: "finish"},
}

func (huangdouProvider) Boards() []rankingBoard { return huangdouBoards }

func (huangdouProvider) CoverReferer(d *Downloader, address string) string {
	if parsed, err := url.Parse(address); err == nil && (strings.EqualFold(parsed.Hostname(), "tideember.cc") || strings.EqualFold(parsed.Hostname(), "xqjurgek.top")) {
		return parsed.Scheme + "://" + parsed.Host + "/home"
	}
	d.providerMu.Lock()
	host := d.providerHosts[sourceHuangdou]
	d.providerMu.Unlock()
	if host == "" {
		host = d.providerBaseURL(sourceHuangdou)
	}
	return host + "/home"
}
