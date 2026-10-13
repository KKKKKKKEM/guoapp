package core

import (
	"context"
	"errors"
	"net/url"
	"regexp"
	"strings"
)

var coverMetaTag = regexp.MustCompile(`(?is)<meta\b[^>]*>`)

func (d *Downloader) nativeCoverAddress(ctx context.Context, drama nativeDrama) (string, error) {
	source, id, valid := splitProviderDramaID(drama.ID)
	if !valid {
		return "", errors.New("无效的剧集 ID")
	}
	drama.Source, drama.SourceID = source, id
	provider, _ := findProvider(source)
	if cover, supported := provider.(ProviderCoverAddress); supported {
		return cover.CoverAddress(ctx, d, drama)
	}
	fresh, _, err := provider.Detail(ctx, d, Drama{ID: drama.ID, Source: source, SourceID: id, Title: drama.Title})
	return nativeNormalize(fresh).Cover, err
}

func (d *Downloader) huangguoPageCoverAddress(ctx context.Context, drama nativeDrama, route string) (string, error) {
	pageURL := d.providerBaseURL(drama.Source) + route
	body, err := d.fetchProviderText(ctx, pageURL, d.providerBaseURL(drama.Source)+"/")
	if err != nil {
		return "", err
	}
	fresh, err := parseHuangguoSortDetail(body, pageURL, Drama{ID: drama.ID, Source: drama.Source, SourceID: drama.SourceID})
	return nativeNormalize(fresh).Cover, err
}

func providerCoverAddress(value any, pageURL string) string {
	switch item := value.(type) {
	case []any:
		for _, value := range item {
			if address := providerCoverAddress(value, pageURL); address != "" {
				return address
			}
		}
	case map[string]any:
		for _, key := range []string{"url", "contentUrl", "thumbnailUrl"} {
			if address := providerCoverAddress(item[key], pageURL); address != "" {
				return address
			}
		}
	case string:
		if strings.TrimSpace(item) == "" {
			return ""
		}
		address, err := url.Parse(strings.TrimSpace(item))
		if err != nil {
			return ""
		}
		if base, err := url.Parse(pageURL); err == nil && base.IsAbs() {
			address = base.ResolveReference(address)
		}
		if validNativeCoverURL(address) {
			return address.String()
		}
	}
	return ""
}

func hongguoCoverAddress(values ...string) string {
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value == "" || len(value) > 8192 {
			continue
		}
		if strings.HasPrefix(value, "//") {
			value = "https:" + value
		}
		parsed, err := url.Parse(value)
		if err == nil && validNativeCoverURL(parsed) {
			return value
		}
	}
	return ""
}
