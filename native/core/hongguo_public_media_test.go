package core

import "testing"

func TestHongguoPublicMediaAddresses(t *testing.T) {
	body := `<script data-rh="true" type="application/ld+json">{"@context":"https://schema.org","contentUrl":"https://hongguoduanju.com/video/public/123456/360p.mp4"}</script>` +
		`<video class="pc-media" src="/video/public/123456/480p.mp4" controls></video>` +
		`<a href="/video/public/999/360p.mp4">其他集</a>`
	addresses := hongguoPublicMediaAddresses(body, "123456")
	if len(addresses) != 2 {
		t.Fatalf("addresses = %v, want 2 entries", addresses)
	}
	if addresses[0] != "https://hongguoduanju.com/video/public/123456/360p.mp4" {
		t.Fatalf("first address = %q", addresses[0])
	}
	if addresses[1] != "https://hongguoduanju.com/video/public/123456/480p.mp4" {
		t.Fatalf("second address = %q", addresses[1])
	}
	if got := hongguoPublicMediaAddresses(body, "999"); len(got) != 1 || got[0] != "https://hongguoduanju.com/video/public/999/360p.mp4" {
		t.Fatalf("other episode addresses = %v", got)
	}
	if got := hongguoPublicMediaAddresses(body, "888"); len(got) != 0 {
		t.Fatalf("missing episode addresses = %v", got)
	}
}
