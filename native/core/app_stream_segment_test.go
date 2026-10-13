package core

import (
	"bytes"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestNativeEncryptedHLSSegmentRemainsBinary(t *testing.T) {
	segment := bytes.Repeat([]byte{0x47, 0x8f, 0xa3, 0x01}, (5<<20)/4)
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/segment.ts" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/octet-stream")
		_, _ = w.Write(segment)
	}))
	defer upstream.Close()
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	stream, err := newNativeStreamServer(engine.downloader)
	if err != nil {
		t.Fatal(err)
	}
	defer stream.server.Close()
	address, token := stream.nativeOpen(providerMedia{
		URL:      upstream.URL + "/master.m3u8",
		HLSKey:   []byte("0123456789abcdef"),
		Playlist: "#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-KEY:METHOD=AES-128,URI=\"key\"\n#EXTINF:2,\nsegment.ts\n#EXT-X-ENDLIST\n",
	})
	defer stream.nativeRelease(token)
	response, err := http.Get(address)
	if err != nil {
		t.Fatal(err)
	}
	playlist, err := io.ReadAll(response.Body)
	response.Body.Close()
	if err != nil {
		t.Fatal(err)
	}
	var segmentURL string
	for _, line := range strings.Split(string(playlist), "\n") {
		if strings.HasPrefix(line, "http://") {
			segmentURL = line
			break
		}
	}
	if segmentURL == "" {
		t.Fatal("missing rewritten media segment")
	}
	response, err = http.Get(segmentURL)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	actual, err := io.ReadAll(response.Body)
	if err != nil {
		t.Fatal(err)
	}
	if response.StatusCode != http.StatusOK || !bytes.Equal(actual, segment) {
		t.Fatalf("binary HLS segment corrupted: status=%d bytes=%d expected=%d", response.StatusCode, len(actual), len(segment))
	}
}
