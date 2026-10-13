package main

import (
	"duanjuapp/native/core"
	"encoding/json"
	"os"
)

func main() {
	if err := json.NewEncoder(os.Stdout).Encode(core.ProviderManifest()); err != nil {
		panic(err)
	}
}
