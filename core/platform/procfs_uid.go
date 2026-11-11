package platform

import (
	"bufio"
	"bytes"
	"io"
	"strconv"
)

const ambiguousSocketUID = -2

func column(row []byte, index int) []byte {
	for i := 0; ; i++ {
		row = bytes.TrimLeft(row, " \t")
		if len(row) == 0 {
			return nil
		}
		end := bytes.IndexAny(row, " \t")
		if end < 0 {
			end = len(row)
		}
		if i == index {
			return row[:end]
		}
		row = row[end:]
	}
}

func uniqueSocketUID(reader io.Reader, local []byte, localIndex, uidIndex int) int {
	result := -1
	scanner := bufio.NewScanner(reader)
	for scanner.Scan() {
		row := scanner.Bytes()
		if !bytes.EqualFold(local, column(row, localIndex)) {
			continue
		}
		uid, err := strconv.Atoi(string(column(row, uidIndex)))
		if err != nil || uid < 0 || result >= 0 && result != uid {
			return ambiguousSocketUID
		}
		result = uid
	}
	if scanner.Err() != nil {
		return ambiguousSocketUID
	}
	return result
}
