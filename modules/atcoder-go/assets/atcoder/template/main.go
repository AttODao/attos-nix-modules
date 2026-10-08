package main

import (
	"bufio"
	"fmt"
	"os"

	"atcoder.jp/golang/library"
)

func main() {
	in := library.NewInput(os.Stdin)
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()

	_ = in
	_ = fmt.Fprintln
}
