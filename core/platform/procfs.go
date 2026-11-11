//go:build linux

package platform

import (
	"bufio"
	"encoding/binary"
	"encoding/hex"
	"net"
	"os"
	"strings"
	"unsafe"
)

var netIndexOfLocal = -1
var netIndexOfUid = -1

var nativeEndian binary.ByteOrder

func QuerySocketUidFromProcFs(source, _ net.Addr) int {
	if netIndexOfLocal < 0 || netIndexOfUid < 0 {
		return -1
	}

	network := source.Network()

	if strings.HasSuffix(network, "4") || strings.HasSuffix(network, "6") {
		network = network[:len(network)-1]
	}

	path := "/proc/net/" + network

	var sIP net.IP
	var sPort int

	switch s := source.(type) {
	case *net.TCPAddr:
		sIP = s.IP
		sPort = s.Port
	case *net.UDPAddr:
		sIP = s.IP
		sPort = s.Port
	default:
		return -1
	}

	sIP = sIP.To16()
	if sIP == nil {
		return -1
	}

	uid := doQuery(path+"6", sIP, sPort)
	if uid == ambiguousSocketUID {
		return -1
	}
	if ipv4 := sIP.To4(); ipv4 != nil {
		other := doQuery(path, ipv4, sPort)
		if other == ambiguousSocketUID || uid >= 0 && other >= 0 && uid != other {
			return -1
		}
		if other >= 0 {
			uid = other
		}
	}

	return uid
}

func localAddressColumn(sIP net.IP, sPort int) []byte {
	ip := nativeEndianIP(sIP)
	column := make([]byte, 0, hex.EncodedLen(len(ip))+1+4)

	encoded := make([]byte, hex.EncodedLen(len(ip)))
	hex.Encode(encoded, ip)
	column = append(column, encoded...)

	column = append(column, ':')

	var port [2]byte
	binary.BigEndian.PutUint16(port[:], uint16(sPort))
	var encodedPort [4]byte
	hex.Encode(encodedPort[:], port[:])
	return append(column, encodedPort[:]...)
}

func doQuery(path string, sIP net.IP, sPort int) int {
	file, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return -1
		}
		return ambiguousSocketUID
	}

	defer func(file *os.File) {
		_ = file.Close()
	}(file)

	return uniqueSocketUID(file, localAddressColumn(sIP, sPort), netIndexOfLocal, netIndexOfUid)
}

func nativeEndianIP(ip net.IP) []byte {
	result := make([]byte, len(ip))

	for i := 0; i < len(ip); i += 4 {
		value := binary.BigEndian.Uint32(ip[i:])

		nativeEndian.PutUint32(result[i:], value)
	}

	return result
}

func init() {
	file, err := os.Open("/proc/net/tcp")
	if err != nil {
		return
	}

	defer func(file *os.File) {
		_ = file.Close()
	}(file)

	reader := bufio.NewReader(file)

	header, _, err := reader.ReadLine()
	if err != nil {
		return
	}

	columns := strings.Fields(string(header))

	var txQueue, rxQueue, tr, tmWhen bool

	for idx, col := range columns {
		offset := 0

		if txQueue && rxQueue {
			offset--
		}

		if tr && tmWhen {
			offset--
		}

		switch col {
		case "tx_queue":
			txQueue = true
		case "rx_queue":
			rxQueue = true
		case "tr":
			tr = true
		case "tm->when":
			tmWhen = true
		case "local_address":
			netIndexOfLocal = idx + offset
		case "uid":
			netIndexOfUid = idx + offset
		}
	}
}

func init() {
	var x uint32 = 0x01020304
	if *(*byte)(unsafe.Pointer(&x)) == 0x01 {
		nativeEndian = binary.BigEndian
	} else {
		nativeEndian = binary.LittleEndian
	}
}
