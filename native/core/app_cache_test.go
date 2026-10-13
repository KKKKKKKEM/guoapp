package core

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"encoding/json"
	"fmt"
	"image"
	"image/png"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func syntheticNativeCover(t *testing.T) ([]byte, []byte) {
	t.Helper()
	var buffer bytes.Buffer
	if err := png.Encode(&buffer, image.NewNRGBA(image.Rect(0, 0, 2, 3))); err != nil {
		t.Fatal(err)
	}
	plain := buffer.Bytes()
	block, err := aes.NewCipher([]byte("f5d965df75336270"))
	if err != nil {
		t.Fatal(err)
	}
	padded := pkcs7Pad(append([]byte(nil), plain...), block.BlockSize())
	encrypted := make([]byte, len(padded))
	cipher.NewCBCEncrypter(block, []byte("97b60394abc2fbe1")).CryptBlocks(encrypted, padded)
	return plain, encrypted
}

func TestNativeCoverDecryptsAndPersistsAcrossRestart(t *testing.T) {
	plain, encrypted := syntheticNativeCover(t)
	var calls atomic.Int32
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		if r.URL.RawQuery != "signature=%2F%2b%3D&auth_key=fixture" || r.Header.Get("Referer") != "https://huangguoai.com/" || r.Header.Get("User-Agent") == "" {
			t.Error("cover request changed its signed URL or lost source headers")
		}
		w.Write(encrypted)
	}))
	defer upstream.Close()
	directory := t.TempDir()
	engine, err := newNativeEngine(directory)
	if err != nil {
		t.Fatal(err)
	}
	drama := nativeDrama{ID: "huangguoai:1", Source: sourceHuangguoAI, Cover: upstream.URL + "/poster.jpg?signature=%2F%2b%3D&auth_key=fixture"}
	var workers sync.WaitGroup
	for range 12 {
		workers.Add(1)
		go func() {
			defer workers.Done()
			path, err := engine.covers.load(context.Background(), drama, false)
			if err != nil {
				t.Error(err)
				return
			}
			data, err := os.ReadFile(path)
			if err != nil || !bytes.Equal(data, plain) {
				t.Error("cover was not decrypted to a local image", err)
			}
		}()
	}
	workers.Wait()
	if calls.Load() != 1 {
		t.Fatal("concurrent cover requests were not coalesced", calls.Load())
	}
	restarted, err := newNativeEngine(directory)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := restarted.covers.load(context.Background(), drama, false); err != nil || calls.Load() != 1 {
		t.Fatal("restart did not reuse the disk image", err, calls.Load())
	}
	if _, err := restarted.covers.load(context.Background(), drama, true); err != nil || calls.Load() != 2 {
		t.Fatal("explicit cover retry did not refetch", err, calls.Load())
	}
}

func TestNativeCoverFormatsFailuresAndOfflineFallback(t *testing.T) {
	plain, encrypted := syntheticNativeCover(t)
	xor := append([]byte(nil), plain...)
	key := []byte("2019ysapp7527")
	for index := 0; index < min(100, len(xor)); index++ {
		xor[index] ^= key[index%len(key)]
	}
	for name, data := range map[string][]byte{"plain": plain, "aes": encrypted, "header": xor} {
		t.Run(name, func(t *testing.T) {
			if !bytes.Equal(nativeDecodeCover(data), plain) {
				t.Fatal("image was decoded incorrectly")
			}
		})
	}
	if nativeIsCoverImage(nativeDecodeCover([]byte("<html>verification required</html>"))) {
		t.Fatal("HTML was accepted as a cover")
	}
	var calls atomic.Int32
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch calls.Add(1) {
		case 1:
			w.Write([]byte("<html>verification required</html>"))
		case 2:
			w.Write(plain)
		default:
			w.WriteHeader(http.StatusServiceUnavailable)
		}
	}))
	defer upstream.Close()
	directory := t.TempDir()
	engine, err := newNativeEngine(directory)
	if err != nil {
		t.Fatal(err)
	}
	drama := nativeDrama{ID: "huangguoai:2", Source: sourceHuangguoAI, Cover: upstream.URL + "/cover"}
	if _, err := engine.covers.load(context.Background(), drama, false); err == nil || len(engine.covers.entries) != 0 {
		t.Fatal("invalid cover was cached")
	}
	path, err := engine.covers.load(context.Background(), drama, false)
	if err != nil {
		t.Fatal("cover failure could not be retried", err)
	}
	old := time.Now().Add(-nativeCoverTTL - time.Hour)
	if err := os.Chtimes(path, old, old); err != nil {
		t.Fatal(err)
	}
	restarted, err := newNativeEngine(directory)
	if err != nil {
		t.Fatal(err)
	}
	if cached, err := restarted.covers.load(context.Background(), drama, false); err != nil || cached != path || calls.Load() != 3 {
		t.Fatal("expired image was not retained during a network failure", err, cached, calls.Load())
	}
	if _, err := restarted.covers.load(context.Background(), drama, true); err == nil {
		t.Fatal("forced retry hid an upstream failure behind stale data")
	}
}

func TestNativeCoverRedirectAndBoundedDiskCache(t *testing.T) {
	plain, _ := syntheticNativeCover(t)
	var calls atomic.Int32
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		if r.Header.Get("Referer") != "https://huangguoai.com/" {
			t.Error("redirect lost the source referer")
		}
		if r.URL.Path == "/redirect" {
			http.Redirect(w, r, "/cover?signature=%2F%2b%3D", http.StatusFound)
			return
		}
		if r.URL.Path == "/cover" && r.URL.RawQuery != "signature=%2F%2b%3D" {
			t.Error("redirect changed the signed query")
		}
		w.Write(plain)
	}))
	defer upstream.Close()
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	engine.covers.limit = int64(len(plain) * 2)
	for _, path := range []string{"/redirect", "/second", "/third"} {
		_, err := engine.covers.load(context.Background(), nativeDrama{Source: sourceHuangguoAI, Cover: upstream.URL + path}, false)
		if err != nil {
			t.Fatal(err)
		}
	}
	files, err := os.ReadDir(engine.covers.directory)
	if err != nil || len(files) != 2 || engine.covers.size > engine.covers.limit || calls.Load() != 4 {
		t.Fatal("disk cache did not enforce its limit", err, len(files), engine.covers.size, calls.Load())
	}
}

func TestNativeCatalogCacheFreshnessPagingAndRefresh(t *testing.T) {
	var revision atomic.Int32
	var networkAllowed atomic.Bool
	networkAllowed.Store(true)
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !networkAllowed.Load() {
			t.Error("fresh cache accessed the network")
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		base, valid := map[string]int{
			"/api/videos/category/ai-duanju": 1000, "/api/videos/category/ai-manju": 2000,
			"/api/videos/category/ai-huanlian": 3000, "/api/videos/category/ai-mogai": 4000,
		}[r.URL.Path]
		if !valid {
			t.Error("unexpected non-catalog request", r.URL.Path)
			w.WriteHeader(http.StatusNotFound)
			return
		}
		page, _ := strconv.Atoi(r.URL.Query().Get("page"))
		count := 24
		if page > 1 {
			count = 1
		}
		var rows []map[string]any
		for index := range count {
			id := base + page*100 + index
			rows = append(rows, map[string]any{"id": strconv.Itoa(id), "title": fmt.Sprintf("合成剧集%d版本%d", id, revision.Load())})
		}
		json.NewEncoder(w).Encode(map[string]any{"data": rows})
	}))
	defer upstream.Close()
	directory := t.TempDir()
	open := func() *nativeEngine {
		engine, err := newNativeEngine(directory)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(engine.downloads.close)
		engine.downloader.cfg.ProviderURLs[sourceHuangguoAI] = upstream.URL
		engine.downloader.limiter = newRequestLimiter(3, 0)
		return engine
	}
	engine := open()
	first, err := engine.nativeCatalog(context.Background(), nativeInput{Source: sourceHuangguoAI, Page: 1})
	if err != nil || len(first.Items) != 96 || !first.Fresh || !first.HasMore {
		t.Fatal("initial aggregate catalog was not cached", err, first)
	}
	networkAllowed.Store(false)
	if cached, err := engine.nativeCatalog(context.Background(), nativeInput{Source: sourceHuangguoAI, Page: 1}); err != nil || cached.Items[0].Title != first.Items[0].Title {
		t.Fatal("fresh cache lost its metadata", err)
	}
	networkAllowed.Store(true)
	if _, err := engine.nativeCatalog(context.Background(), nativeInput{Source: sourceHuangguoAI, Page: 2}); err != nil {
		t.Fatal(err)
	}
	engine = open()
	cached := engine.nativeCached(sourceHuangguoAI)
	if len(cached.Items) != 100 || cached.Page != 2 || cached.HasMore || !cached.Fresh {
		t.Fatal("cached pagination state did not survive a restart", cached)
	}
	networkAllowed.Store(false)
	if result, err := engine.nativeCatalog(context.Background(), nativeInput{Source: sourceHuangguoAI, Page: 1}); err != nil || len(result.Items) != 100 || result.Page != 2 {
		t.Fatal("restart did not use its durable library", err, result)
	}
	networkAllowed.Store(true)
	revision.Store(1)
	refreshed, err := engine.nativeCatalog(context.Background(), nativeInput{Source: sourceHuangguoAI, Page: 1, Force: true})
	if err != nil || refreshed.Items[0].Title != "合成剧集1100版本1" || len(engine.nativeCached(sourceHuangguoAI).Items) != 100 {
		t.Fatal("refresh lost historical entries or reused old metadata", err, refreshed)
	}
	state := engine.catalogStates[sourceHuangguoAI]
	state.UpdatedAt = time.Now().Add(-nativeCatalogTTL - time.Second)
	engine.catalogStates[sourceHuangguoAI] = state
	if engine.nativeCached(sourceHuangguoAI).Fresh {
		t.Fatal("expired catalog is marked fresh")
	}
	revision.Store(2)
	updated, err := engine.nativeCatalog(context.Background(), nativeInput{Source: sourceHuangguoAI, Page: 1})
	if err != nil || updated.Items[0].Title != "合成剧集1100版本2" || !updated.Fresh {
		t.Fatal("expired metadata was not updated", err, updated)
	}
}

func TestNativeCatalogCacheMigratesAndKeepsHongguoCursorItems(t *testing.T) {
	directory := t.TempDir()
	old := nativeDrama{ID: "hongguo:101", Title: "原有合成记录"}
	legacy, _ := json.Marshal(map[string][]nativeDrama{sourceHongguo: {old}})
	if err := os.WriteFile(filepath.Join(directory, "catalogs.json"), legacy, 0600); err != nil {
		t.Fatal(err)
	}
	engine, err := newNativeEngine(directory)
	if err != nil {
		t.Fatal(err)
	}
	if cached := engine.nativeCached(sourceHongguo); len(cached.Items) != 1 || cached.Fresh {
		t.Fatal("legacy data was lost or marked as freshly fetched", cached)
	}
	engine.catalogStates[sourceHongguo] = nativeCatalogState{Page: 4, HasMore: true}
	result := nativeCatalogResult{Items: []nativeDrama{{ID: "hongguo:102", Title: "新的合成记录"}}, Page: 1, HasMore: true}
	engine.saveCatalogCache(sourceHongguo, &result)
	if result.Page != 4 || len(result.Items) != 2 || result.Items[0].ID != "hongguo:102" || result.Items[1].ID != old.ID {
		t.Fatal("refresh lost catalog items preceding the saved feed cursor", result)
	}
	restarted, err := newNativeEngine(directory)
	if err != nil || !restarted.nativeCached(sourceHongguo).Fresh {
		t.Fatal("upgraded cache could not be reopened", err)
	}
}
