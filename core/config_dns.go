package main

import (
	"context"
	"errors"
	"fmt"
	"net"
	"sync"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/adapter/inbound"
	"github.com/metacubex/mihomo/component/requestscope"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/dns"
	D "github.com/miekg/dns"
)

type configDNSService struct {
	scope   *requestscope.BusinessScope
	service resolver.Service
}

func (s configDNSService) ServeMsg(_ context.Context, msg *D.Msg) (*D.Msg, error) {
	if err := s.scope.Check(); err != nil {
		return nil, err
	}
	return s.service.ServeMsg(requestscope.WithLease(s.scope.Context(), s.scope), msg)
}

type configDNSBinding struct {
	tcp     net.Listener
	udp     net.PacketConn
	servers [2]*D.Server
	once    sync.Once
	closed  atomic.Bool
	failed  atomic.Bool
}

var ordinaryDNS atomic.Pointer[configDNSBinding]

func prepareConfigDNS(address string, mark int, scope *requestscope.BusinessScope) (*configDNSBinding, error) {
	if address == "" {
		return nil, nil
	}
	if _, port, err := net.SplitHostPort(address); err != nil || port == "0" || port == "" {
		return nil, nil
	}
	lc := inbound.NewListenConfig()
	lc.SetRouteMark(mark)
	tcp, err := lc.Listen(scope.Context(), "tcp", address)
	if err != nil {
		return nil, errors.New("DNS TCP listener could not bind")
	}
	udp, err := lc.ListenPacket(scope.Context(), "udp", address)
	if err != nil {
		_ = tcp.Close()
		return nil, errors.New("DNS UDP listener could not bind")
	}
	return &configDNSBinding{tcp: tcp, udp: udp}, nil
}

func (b *configDNSBinding) start(scope *requestscope.BusinessScope, service resolver.Service) error {
	if b == nil {
		return nil
	}
	if service == nil {
		return errors.New("DNS service is unavailable")
	}
	server := &dns.Server{}
	server.SetService(configDNSService{scope: scope, service: service})
	started, stopped := make(chan struct{}, 2), make(chan error, 2)
	notify := func() { started <- struct{}{} }
	b.servers = [2]*D.Server{
		{Listener: b.tcp, Handler: server.TCPHandler(), NotifyStartedFunc: notify},
		{PacketConn: b.udp, Handler: server.UDPHandler(), NotifyStartedFunc: notify},
	}
	for _, server := range b.servers {
		go func(server *D.Server) {
			err := server.ActivateAndServe()
			if !b.closed.Load() {
				b.failed.Store(true)
			}
			stopped <- err
		}(server)
	}
	timer := time.NewTimer(5 * time.Second)
	defer timer.Stop()
	for count := 0; count < 2; {
		select {
		case <-started:
			count++
		case err := <-stopped:
			return fmt.Errorf("DNS listener could not start: %w", err)
		case <-timer.C:
			return errors.New("DNS listener start timed out")
		}
	}
	return b.validate()
}

func (b *configDNSBinding) validate() error {
	if b != nil && (b.closed.Load() || b.failed.Load()) {
		return errors.New("DNS listener is unavailable")
	}
	return nil
}

func (b *configDNSBinding) close() {
	if b == nil {
		return
	}
	b.once.Do(func() {
		b.closed.Store(true)
		_ = b.tcp.Close()
		_ = b.udp.Close()
		for _, server := range b.servers {
			if server == nil {
				continue
			}
			go func(server *D.Server) {
				ctx, cancel := context.WithTimeout(context.Background(), time.Second)
				defer cancel()
				_ = server.ShutdownContext(ctx)
			}(server)
		}
	})
}
