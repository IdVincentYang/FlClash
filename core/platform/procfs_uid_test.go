package platform

import (
	"strings"
	"testing"
)

func TestProcfsSocketUIDRequiresUnambiguousOwnership(t *testing.T) {
	cases := []struct {
		name, rows string
		want       int
	}{
		{"unique", "0: ABCD:0050 10123\n", 10123},
		{"same owner", "0: ABCD:0050 10123\n1: ABCD:0050 10123\n", 10123},
		{"two owners", "0: ABCD:0050 10123\n1: ABCD:0050 10124\n", ambiguousSocketUID},
		{"other socket", "0: ABCD:0051 10123\n", -1},
		{"missing uid", "0: ABCD:0050\n", ambiguousSocketUID},
		{"invalid uid", "0: ABCD:0050 unknown\n", ambiguousSocketUID},
		{"root", "0: ABCD:0050 0\n", 0},
		{"lower case", "0: abcd:0050 10123\n", 10123},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := uniqueSocketUID(strings.NewReader(tc.rows), []byte("ABCD:0050"), 1, 2); got != tc.want {
				t.Fatalf("got %d, want %d", got, tc.want)
			}
		})
	}
}
