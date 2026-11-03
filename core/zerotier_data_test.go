package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"net/netip"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	ZT "github.com/metacubex/zerotier-go"
)

type zeroTierReviewWire struct {
	Endpoint string `json:"endpoint"`
	Data     []byte `json:"data"`
}

type zeroTierReviewReceipt struct {
	Destination string `json:"destination"`
	Verb        string `json:"verb"`
	Payload     []byte `json:"payload"`
	FrameData   []byte `json:"frameData,omitempty"`
}

func zeroTierReviewDictionary(values map[string][]byte) []byte {
	var lines []string
	for key, value := range values {
		var escaped strings.Builder
		for _, b := range value {
			switch b {
			case 0:
				escaped.WriteString(`\0`)
			case '\n':
				escaped.WriteString(`\n`)
			case '\r':
				escaped.WriteString(`\r`)
			case '\\':
				escaped.WriteString(`\\`)
			case '=':
				escaped.WriteString(`\e`)
			default:
				escaped.WriteByte(b)
			}
		}
		lines = append(lines, key+"="+escaped.String())
	}
	return []byte(strings.Join(lines, "\n"))
}

func zeroTierReviewConfig(network uint64, member, observer ZT.Address, trace bool, action byte, limit uint16) []byte {
	values := make(map[string][]byte)
	for key, value := range map[string]uint64{"v": 7, "nwid": network, "id": member.Uint64(), "t": uint64(ZT.NetworkTypePublic), "mtu": 2800, "r": 1, "ts": uint64(time.Now().UnixMilli())} {
		values[key] = []byte(fmt.Sprintf("%x", value))
	}
	rules := []byte{1, 0}
	if action != 0 {
		forward := make([]byte, 14)
		binary.BigEndian.PutUint64(forward, observer.Uint64())
		binary.BigEndian.PutUint16(forward[12:], limit)
		rules = append(append([]byte{action, 14}, forward...), rules...)
	}
	values["R"] = rules
	if trace {
		values["tt"] = []byte(fmt.Sprintf("%x", observer.Uint64()))
		values["tl"] = []byte("f")
	}
	return zeroTierReviewDictionary(values)
}

func zeroTierReviewPush(t *testing.T, local, signer ZT.Identity, network uint64, config []byte, corrupt bool) []byte {
	t.Helper()
	packet, err := ZT.NewPacket(local.Address(), signer.Address(), ZT.VerbNetworkConfig)
	if err != nil {
		t.Fatal(err)
	}
	_ = packet.AppendUint64(network)
	_ = packet.AppendUint16(uint16(len(config)))
	_ = packet.Append(config...)
	_ = packet.Append(0)
	_ = packet.AppendUint64(0x11223344)
	_ = packet.AppendUint32(uint32(len(config)))
	_ = packet.AppendUint32(0)
	signature, err := signer.Sign(packet.Payload())
	if err != nil {
		t.Fatal(err)
	}
	if corrupt {
		signature[0] ^= 1
	}
	_ = packet.Append(1)
	_ = packet.AppendUint16(ZT.SignatureSize)
	_ = packet.Append(signature[:]...)
	key, err := signer.Agree(local)
	if err != nil {
		t.Fatal(err)
	}
	if err := packet.Armor(key[:], true); err != nil {
		t.Fatal(err)
	}
	return bytes.Clone(packet.Bytes())
}

func zeroTierReviewNode(t *testing.T, local ZT.Identity, peers []ZT.Identity, global ZT.Address) (*ZT.Node, *[]zeroTierReviewWire) {
	t.Helper()
	world := ZT.World{Type: ZT.WorldTypePlanet, ID: 0x1234, Timestamp: uint64(time.Now().UnixMilli())}
	for i, identity := range peers {
		public, err := ZT.ParseIdentity(identity.PublicString())
		if err != nil {
			t.Fatal(err)
		}
		world.Roots = append(world.Roots, ZT.WorldRoot{Identity: public, Endpoints: []netip.AddrPort{netip.MustParseAddrPort(fmt.Sprintf("192.0.2.%d:9993", i+1))}})
	}
	var sent []zeroTierReviewWire
	node, err := ZT.NewNode(ZT.NodeConfig{
		Identity: local,
		Store:    ZT.NewMemoryStore(),
		Planet:   &world,
		Sender: ZT.WireSenderFunc(func(_ int64, endpoint netip.AddrPort, packet []byte) error {
			if len(sent) >= 256 {
				return fmt.Errorf("bounded review sender full")
			}
			sent = append(sent, zeroTierReviewWire{endpoint.String(), bytes.Clone(packet)})
			return nil
		}),
		RemoteTraceTarget: global,
		RemoteTraceLevel:  ZT.TraceLevelRules,
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = node.Close() })
	return node, &sent
}

func zeroTierReviewDatagram() []byte {
	body := append([]byte("synthetic-UDP-business-body-"), bytes.Repeat([]byte{'x'}, 320)...)
	data := make([]byte, 28+len(body))
	data[0], data[8], data[9] = 0x45, 64, 17
	binary.BigEndian.PutUint16(data[2:], uint16(len(data)))
	copy(data[12:16], []byte{10, 1, 1, 1})
	copy(data[16:20], []byte{10, 1, 1, 2})
	binary.BigEndian.PutUint16(data[20:], 12000)
	binary.BigEndian.PutUint16(data[22:], 13000)
	binary.BigEndian.PutUint16(data[24:], uint16(8+len(body)))
	copy(data[28:], body)
	var sum uint32
	for offset := 0; offset < 20; offset += 2 {
		sum += uint32(binary.BigEndian.Uint16(data[offset:]))
	}
	for sum>>16 != 0 {
		sum = sum&0xffff + sum>>16
	}
	binary.BigEndian.PutUint16(data[10:], ^uint16(sum))
	return data
}

func zeroTierReviewLearnPeer(t *testing.T, node *ZT.Node, local, peer ZT.Identity, endpoint netip.AddrPort, sent *[]zeroTierReviewWire) [][]byte {
	t.Helper()
	key, err := peer.Agree(local)
	if err != nil {
		t.Fatal(err)
	}
	hello, err := ZT.NewPacket(local.Address(), peer.Address(), ZT.VerbHello)
	if err != nil {
		t.Fatal(err)
	}
	_ = hello.Append(ZT.ProtocolVersion, 1, 14)
	_ = hello.AppendUint16(0)
	_ = hello.AppendUint64(uint64(time.Now().UnixMilli()))
	_ = hello.Append(peer.AppendBinary(nil, false)...)
	if err := hello.Armor(key[:], false); err != nil {
		t.Fatal(err)
	}
	start := len(*sent)
	input := bytes.Clone(hello.Bytes())
	if err := node.ProcessWirePacket(1, endpoint, input, time.Now()); err != nil {
		t.Fatal("peer HELLO rejected", err)
	}
	for _, wire := range (*sent)[start:] {
		packet, err := ZT.ParsePacket(wire.Data)
		if err != nil || packet.Destination() != peer.Address() {
			continue
		}
		if err := packet.Dearmor(key[:]); err != nil {
			t.Fatal(err)
		}
		if packet.Verb() != ZT.VerbHello {
			continue
		}
		reply, err := ZT.NewPacket(local.Address(), peer.Address(), ZT.VerbOK)
		if err != nil {
			t.Fatal(err)
		}
		_ = reply.Append(byte(ZT.VerbHello))
		_ = reply.AppendUint64(packet.PacketID())
		_ = reply.AppendUint64(binary.BigEndian.Uint64(packet.Payload()[5:13]))
		_ = reply.Append(ZT.ProtocolVersion, 1, 14)
		_ = reply.AppendUint16(0)
		if err := reply.Armor(key[:], true); err != nil {
			t.Fatal(err)
		}
		response := bytes.Clone(reply.Bytes())
		if err := node.ProcessWirePacket(1, endpoint, response, time.Now()); err != nil {
			t.Fatal("matched peer HELLO OK rejected", err)
		}
		return [][]byte{input, response}
	}
	t.Fatal("node did not emit peer path challenge")
	return nil
}

func TestZeroTierPayloadReview(t *testing.T) {
	root := os.Getenv("FLCLASH_ZEROTIER_DATA_EVIDENCE")
	if root == "" {
		t.Skip("explicit pinned-dependency in-memory review; no OS network")
	}
	identities := make([]ZT.Identity, 4)
	for i := range identities {
		identity, err := ZT.GenerateIdentity()
		if err != nil {
			t.Fatal(err)
		}
		identities[i] = identity
	}
	local, controller, original, observer := identities[0], identities[1], identities[2], identities[3]
	network := controller.Address().Uint64()<<24 | 0x1234
	frame := zeroTierReviewDatagram()
	var observations []map[string]any
	for _, scenario := range []struct {
		name   string
		global bool
		trace  bool
		action byte
		limit  uint16
	}{
		{name: "no-copy"},
		{name: "global-trace", global: true},
		{name: "controller-trace-local-off", trace: true},
		{name: "controller-tee-local-off", action: 2},
		{name: "controller-tee-prefix-local-off", action: 2, limit: 64},
		{name: "controller-watch-local-off", action: 3},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			global := ZT.Address(0)
			if scenario.global {
				global = observer.Address()
			}
			node, sent := zeroTierReviewNode(t, local, []ZT.Identity{controller, original, observer}, global)
			var handshake [][][]byte
			for i, peer := range []ZT.Identity{controller, original, observer} {
				handshake = append(handshake, zeroTierReviewLearnPeer(t, node, local, peer, netip.MustParseAddrPort(fmt.Sprintf("192.0.2.%d:9993", i+1)), sent))
			}
			if err := node.Join(network); err != nil {
				t.Fatal(err)
			}
			config := zeroTierReviewConfig(network, local.Address(), observer.Address(), scenario.trace, scenario.action, scenario.limit)
			push := zeroTierReviewPush(t, local, controller, network, config, false)
			if err := node.ProcessWirePacket(1, netip.MustParseAddrPort("192.0.2.1:9993"), push, time.Now()); err != nil {
				t.Fatal("signed controller input rejected", err)
			}
			accepted, ok := node.Network(network)
			if !ok || accepted.Status != ZT.NetworkStatusOK || accepted.Config.IssuedTo != local.Address() {
				t.Fatal("network config not accepted via public wire consumer")
			}
			start := len(*sent)
			setupWire := append([]zeroTierReviewWire(nil), (*sent)...)
			if err := node.SendFrame(network, ZT.MACForAddress(original.Address(), network), ZT.EtherTypeIPv4, frame); err != nil {
				t.Fatal(err)
			}
			var receipts []zeroTierReviewReceipt
			originalCount, extraCount := 0, 0
			for _, wire := range (*sent)[start:] {
				packet, err := ZT.ParsePacket(wire.Data)
				if err != nil {
					t.Fatal(err)
				}
				var recipient ZT.Identity
				for _, id := range []ZT.Identity{controller, original, observer} {
					if packet.Destination() == id.Address() {
						recipient = id
					}
				}
				if recipient.Address().IsZero() {
					t.Fatal("unexpected destination identity")
				}
				key, err := recipient.Agree(local)
				if err != nil || packet.Dearmor(key[:]) != nil || packet.Uncompress() != nil {
					t.Fatal("independent recipient could not decode", err)
				}
				receipt := zeroTierReviewReceipt{Destination: recipient.Address().String(), Verb: packet.Verb().String(), Payload: bytes.Clone(packet.Payload())}
				if recipient.Address() == original.Address() && packet.Verb() == ZT.VerbFrame {
					if len(packet.Payload()) < 10 || !bytes.Equal(packet.Payload()[10:], frame) {
						t.Fatal("ordinary recipient frame differs")
					}
					originalCount++
				}
				if recipient.Address() == observer.Address() && packet.Verb() == ZT.VerbRemoteTrace {
					dictionary, err := ZT.ParseDictionary(packet.Payload())
					if err != nil {
						t.Fatal(err)
					}
					if dictionary.String("event") == "2006" {
						receipt.FrameData = bytes.Clone(dictionary["frameData"])
						if !bytes.Equal(receipt.FrameData, frame[:256]) {
							t.Fatal("trace recipient did not receive expected prefix")
						}
						extraCount++
					}
				}
				if recipient.Address() == observer.Address() && packet.Verb() == ZT.VerbExtFrame {
					limit := len(frame)
					if scenario.limit != 0 {
						limit = int(scenario.limit)
					}
					if len(packet.Payload()) < 23 || !bytes.Equal(packet.Payload()[23:], frame[:limit]) {
						t.Fatal("TEE/WATCH recipient frame differs")
					}
					receipt.FrameData = bytes.Clone(packet.Payload()[23:])
					extraCount++
				}
				receipts = append(receipts, receipt)
			}
			wanted := 1
			if scenario.name == "no-copy" {
				wanted = 0
			}
			observations = append(observations, map[string]any{"name": scenario.name, "controllerConfig": config, "signedPush": push, "accepted": accepted.Config, "handshakeInputs": handshake, "setupWire": setupWire, "peers": node.Peers(), "receipts": receipts, "originalCount": originalCount, "extraCount": extraCount, "wire": (*sent)[start:]})
			if originalCount != 1 || extraCount != wanted {
				t.Fatalf("independent receipts original=%d extra=%d, want 1/%d", originalCount, extraCount, wanted)
			}
		})
	}
	var rejections []map[string]any
	for _, name := range []string{"corrupt-controller-signature", "wrong-signer", "wrong-issued-to"} {
		t.Run(name, func(t *testing.T) {
			node, sent := zeroTierReviewNode(t, local, []ZT.Identity{controller, original, observer}, 0)
			if err := node.Join(network); err != nil {
				t.Fatal(err)
			}
			signer, member, endpoint := controller, local.Address(), "192.0.2.1:9993"
			if name == "wrong-signer" {
				signer, endpoint = observer, "192.0.2.3:9993"
			}
			if name == "wrong-issued-to" {
				member = observer.Address()
			}
			config := zeroTierReviewConfig(network, member, observer.Address(), true, 2, 0)
			push := zeroTierReviewPush(t, local, signer, network, config, name == "corrupt-controller-signature")
			pushErr := node.ProcessWirePacket(1, netip.MustParseAddrPort(endpoint), push, time.Now())
			state, ok := node.Network(network)
			sendErr := node.SendFrame(network, ZT.MACForAddress(original.Address(), network), ZT.EtherTypeIPv4, frame)
			rejections = append(rejections, map[string]any{"name": name, "config": config, "signedPush": push, "network": state, "pushError": fmt.Sprint(pushErr), "sendError": fmt.Sprint(sendErr), "wire": *sent})
			if !ok || state.Status == ZT.NetworkStatusOK || !errors.Is(sendErr, ZT.ErrNetworkNotReady) {
				t.Fatalf("invalid configuration became usable: status=%v, push=%v, send=%v", state.Status, pushErr, sendErr)
			}
		})
	}
	if err := os.MkdirAll(root, 0700); err != nil {
		t.Fatal(err)
	}
	secrets := map[string]string{"local": local.SecretString(), "controller": controller.SecretString(), "original": original.SecretString(), "observer": observer.SecretString()}
	identityData, err := json.MarshalIndent(map[string]any{"syntheticOnly": true, "identities": secrets}, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "synthetic_identities.json"), identityData, 0600); err != nil {
		t.Fatal(err)
	}
	data, err := json.MarshalIndent(map[string]any{"network": fmt.Sprintf("%016x", network), "local": local.PublicString(), "controller": controller.PublicString(), "original": original.PublicString(), "observer": observer.PublicString(), "frame": frame, "cases": observations, "negativeControls": rejections, "scope": "public Node API + accepted signed controller input + memory WireSender; synthetic planet identities/endpoints; no sockets, wireTransport, overlay, Core or Android execution"}, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "receipts.json"), data, 0600); err != nil {
		t.Fatal(err)
	}
}
