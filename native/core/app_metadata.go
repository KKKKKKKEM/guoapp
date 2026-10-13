package core

import (
	"context"
	"errors"
	"time"
)

func nativeNeedsExtraMetadata(drama nativeDrama) bool {
	provider, found := findProvider(drama.Source)
	if !found {
		return false
	}
	metadata, supported := provider.(ProviderMetadata)
	if !supported {
		return false
	}
	for _, field := range metadata.MetadataFields() {
		if nativeMetadataMissing(drama, field) {
			return true
		}
	}
	return false
}

func nativeMetadataMissing(drama nativeDrama, field string) bool {
	switch field {
	case "title":
		return drama.Title == ""
	case "description":
		return drama.Description == ""
	case "cover":
		return drama.Cover == ""
	case "episodes":
		return drama.Episodes <= 0
	case "category":
		return drama.Category == ""
	case "vip":
		return drama.VIP == nil
	case "heat":
		return drama.Heat == ""
	case "views":
		return drama.Views == ""
	case "onlineDate":
		return drama.OnlineDate == ""
	case "tags":
		return len(drama.Tags) == 0
	case "releaseStatus":
		return drama.ReleaseStatus == ""
	default:
		return false
	}
}

func (engine *nativeEngine) nativeExtraMetadata(ctx context.Context, drama nativeDrama) (nativeDrama, error) {
	source, id, valid := splitProviderDramaID(drama.ID)
	if !valid {
		return drama, errors.New("剧集信息无效")
	}
	if !nativeNeedsExtraMetadata(drama) {
		return drama, nil
	}
	provider, _ := findProvider(source)
	metadata, supported := provider.(ProviderMetadata)
	if !supported {
		return drama, nil
	}
	ctx, cancel := context.WithTimeout(context.WithValue(ctx, backgroundCatalogKey{}, true), 15*time.Second)
	defer cancel()
	request := drama
	request.Source, request.SourceID = source, id
	raw, err := metadata.Metadata(ctx, engine.downloader, request)
	if err != nil {
		return drama, err
	}
	if raw.ID == drama.ID {
		drama = mergeNativeDrama(drama, nativeNormalize(raw))
	}
	return drama, ctx.Err()
}

func (engine *nativeEngine) nativeMetadata(ctx context.Context, drama nativeDrama) (any, error) {
	fresh, err := engine.nativeExtraMetadata(ctx, drama)
	if err != nil {
		return nil, err
	}
	warning := ""
	if err := engine.saveDetailMetadata(fresh); err != nil {
		warning = err.Error()
	}
	return map[string]any{"drama": fresh, "warning": warning}, nil
}
