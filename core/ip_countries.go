package main

import (
	"context"
	"net"
	"strings"
	"time"

	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
	"github.com/oschwald/maxminddb-golang"
)

func handleLookupIPCountries(ips []string) map[string]string {
	result := map[string]string{}
	if len(ips) == 0 || len(ips) > 128 {
		return result
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	unlock, err := requestscope.LockResource(ctx, C.Path.MMDB())
	if err != nil {
		return result
	}
	defer unlock()
	reader, err := maxminddb.Open(C.Path.MMDB())
	if err != nil {
		return result
	}
	defer reader.Close()
	for _, address := range ips {
		if !publicIPAddress(address) {
			continue
		}
		var value any
		if err := reader.Lookup(net.ParseIP(address), &value); err != nil {
			continue
		}
		code := countryFromMMDB(value)
		if len(code) == 2 && code[0] >= 'A' && code[0] <= 'Z' && code[1] >= 'A' && code[1] <= 'Z' {
			result[address] = code
		}
	}
	return result
}

func countryFromMMDB(value any) string {
	switch record := value.(type) {
	case string:
		return strings.ToUpper(record)
	case []any:
		code := ""
		for _, item := range record {
			candidate := countryFromMMDB(item)
			if len(candidate) != 2 || candidate[0] < 'A' || candidate[0] > 'Z' || candidate[1] < 'A' || candidate[1] > 'Z' {
				continue
			}
			if code != "" && code != candidate {
				return ""
			}
			code = candidate
		}
		return code
	case map[string]any:
		if country, ok := record["country"].(map[string]any); ok {
			if code, ok := country["iso_code"].(string); ok {
				return strings.ToUpper(code)
			}
		}
	}
	return ""
}
