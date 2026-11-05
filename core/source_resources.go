package main

import (
	"github.com/metacubex/mihomo/config"
	"io"
)

func closeSourceConfigProxies(p *preparedConfig, cfg *config.Config) {
	if p == nil || p.inputVersion != 2 || cfg == nil {
		return
	}
	p.sourceClose.Do(func() {
		p.sourceSerial.Lock()
		defer p.sourceSerial.Unlock()
		for _, proxy := range cfg.Proxies {
			_ = proxy.Close()
		}
		for _, generation := range p.sourceInlineRetired {
			for _, provider := range generation.providers {
				if closer, valid := provider.(io.Closer); valid {
					_ = closer.Close()
				}
			}
			for _, proxy := range generation.proxies {
				_ = proxy.Close()
			}
		}
		p.sourceInlineRetired = nil
	})
}
