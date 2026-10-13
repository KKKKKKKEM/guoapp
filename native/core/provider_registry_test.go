package core

import (
	"context"
	"net/http"
	"testing"
)

func TestProviderDetailPreservesReportedTotalWithUnavailableEpisodes(t *testing.T) {
	engine := sourceFixtureEngine(t, func(request *http.Request) (*http.Response, error) {
		switch request.URL.Path {
		case "/auth/guest":
			return sourceFixtureResponse(request, 200, `{"token":"fixture-token"}`), nil
		case "/dramas/sample-77":
			return sourceFixtureResponse(request, 200, `{"id":"77","slug":"sample","title":"完整资料","description":"合成简介","totalEpisodes":12,"episodes":[{"id":"episode-1","epNo":1,"playable":true},{"id":"episode-2","epNo":2,"playable":false}]}`), nil
		default:
			t.Fatalf("unexpected request: %s", request.URL)
			return nil, nil
		}
	})
	engine.downloader.cfg.ProviderURLs[sourceHuangju+":api"] = "https://fixture.example.test"
	engine.catalogs[sourceHuangju] = []nativeDrama{{ID: "huangju:sample-77", Source: sourceHuangju, Title: "旧资料"}}
	result, err := engine.nativeDetail(context.Background(), nativeDrama{ID: "huangju:sample-77", Source: sourceHuangju, Title: "旧资料"})
	if err != nil {
		t.Fatal(err)
	}
	detail := result.(map[string]any)
	drama := detail["drama"].(nativeDrama)
	chapters := detail["chapters"].([]Chapter)
	if drama.ID != "huangju:sample-77" || drama.SourceID != "sample-77" || drama.Title != "完整资料" || drama.Episodes != 12 {
		t.Fatalf("detail lost identity or reported episode total: %+v", drama)
	}
	if len(chapters) != 1 || chapters[0].ID != "huangju:sample-77:episode-1" {
		t.Fatalf("unavailable episode entered playable detail: %+v", chapters)
	}
	cached := engine.nativeCached(sourceHuangju).Items[0]
	if cached.Episodes != 12 || cached.Description != "合成简介" {
		t.Fatalf("detail metadata was not retained by the library: %+v", cached)
	}
}

func TestProviderOnlineSearchPreservesLibraryAndPagination(t *testing.T) {
	engine := sourceFixtureEngine(t, func(request *http.Request) (*http.Response, error) {
		switch request.URL.Path {
		case "/auth/guest":
			return sourceFixtureResponse(request, 200, `{"token":"fixture-token"}`), nil
		case "/dramas":
			if request.URL.Query().Get("q") != "合成搜索" || request.URL.Query().Get("page") != "2" {
				t.Fatalf("search did not preserve its query and page: %s", request.URL)
			}
			return sourceFixtureResponse(request, 200, `{"items":[{"id":"99","slug":"search","title":"搜索结果"}],"page":2,"pageSize":1,"total":3}`), nil
		default:
			t.Fatalf("unexpected request: %s", request.URL)
			return nil, nil
		}
	})
	engine.downloader.cfg.ProviderURLs[sourceHuangju+":api"] = "https://fixture.example.test"
	engine.catalogs[sourceHuangju] = []nativeDrama{{ID: "huangju:library-77", Source: sourceHuangju, Title: "已有剧库"}}
	engine.catalogStates[sourceHuangju] = nativeCatalogState{Page: 7, HasMore: true}
	result, err := engine.nativeCatalog(context.Background(), nativeInput{Source: sourceHuangju, Query: "合成搜索", Page: 2})
	if err != nil {
		t.Fatal(err)
	}
	if result.Page != 2 || !result.HasMore || result.LocalSearch || len(result.Items) != 1 || result.Items[0].ID != "huangju:search-99" {
		t.Fatalf("online search lost its result or continuation: %+v", result)
	}
	cached := engine.nativeCached(sourceHuangju)
	if cached.Page != 7 || len(cached.Items) != 1 || cached.Items[0].ID != "huangju:library-77" {
		t.Fatalf("search replaced the browsable library: %+v", cached)
	}
}

func TestProviderLocalSearchUsesCachedMetadataWithoutNetwork(t *testing.T) {
	engine := sourceFixtureEngine(t, func(request *http.Request) (*http.Response, error) {
		t.Fatalf("local search issued a network request: %s", request.URL)
		return nil, nil
	})
	engine.catalogs[sourceHuangdou] = []nativeDrama{
		{ID: "huangdou:1", Source: sourceHuangdou, Title: "合成剧目", Tags: []string{"重生"}},
		{ID: "huangdou:2", Source: sourceHuangdou, Title: "合成剧目", Tags: []string{"都市"}},
	}
	result, err := engine.nativeCatalog(context.Background(), nativeInput{Source: sourceHuangdou, Query: "合成 重生", Page: 1})
	if err != nil {
		t.Fatal(err)
	}
	if !result.LocalSearch || result.HasMore || len(result.Items) != 1 || result.Items[0].ID != "huangdou:1" {
		t.Fatalf("local metadata search did not retain all-word matching: %+v", result)
	}
}

func TestProviderMetadataRequirementsPreserveKnownVIPStatus(t *testing.T) {
	free := false
	drama := nativeDrama{ID: "huangdou:1", Source: sourceHuangdou, Heat: "123", VIP: &free}
	if nativeNeedsExtraMetadata(drama) {
		t.Fatal("known free status was mistaken for missing metadata")
	}
	drama.VIP = nil
	if !nativeNeedsExtraMetadata(drama) {
		t.Fatal("unknown VIP status was mistaken for known free status")
	}
	drama.VIP, drama.Heat = &free, ""
	if !nativeNeedsExtraMetadata(drama) {
		t.Fatal("known VIP status masked missing popularity metadata")
	}
}
