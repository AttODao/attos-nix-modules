package main

import (
	"flag"
	"fmt"
	"go/ast"
	"go/format"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
)

const libraryImportPath = "atcoder.jp/golang/library"

type sourceFile struct {
	path      string
	file      *ast.File
	isLibrary bool
}

func main() {
	entry := flag.String("entry", "main.go", "entry Go source file")
	libraryDir := flag.String("library-dir", "", "directory containing package library files")
	output := flag.String("output", ".submit/main.go", "combined output file")
	flag.Parse()

	if err := run(*entry, *libraryDir, *output); err != nil {
		fmt.Fprintln(os.Stderr, "atcoder-snippet:", err)
		os.Exit(1)
	}
}

func run(entryPath, libraryDir, outputPath string) error {
	fset := token.NewFileSet()
	entryPath, err := filepath.Abs(entryPath)
	if err != nil {
		return err
	}

	projectRoot := os.Getenv("ATCODER_GO_ROOT")
	if projectRoot == "" {
		projectRoot = findProjectRoot(filepath.Dir(entryPath))
	}
	if libraryDir == "" {
		libraryDir = filepath.Join(projectRoot, "library")
	}

	files := []sourceFile{}
	entry, err := parseSource(fset, entryPath, "main")
	if err != nil {
		return err
	}
	entrySource := sourceFile{path: entryPath, file: entry}
	files = append(files, entrySource)

	libraryFiles, err := collectLibraryFiles(libraryDir, entryPath)
	if err != nil {
		return err
	}
	for _, path := range libraryFiles {
		file, err := parseSource(fset, path, "library")
		if err != nil {
			return err
		}
		files = append(files, sourceFile{path: path, file: file, isLibrary: true})
	}

	combined, err := combine(entrySource, files[1:])
	if err != nil {
		return err
	}

	if err := os.MkdirAll(filepath.Dir(outputPath), 0o755); err != nil {
		return err
	}
	out, err := os.Create(outputPath)
	if err != nil {
		return err
	}
	defer out.Close()

	return format.Node(out, fset, combined)
}

func parseSource(fset *token.FileSet, path, packageName string) (*ast.File, error) {
	file, err := parser.ParseFile(fset, path, nil, parser.ParseComments)
	if err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	if file.Name.Name != packageName {
		return nil, fmt.Errorf("%s must use package %s", path, packageName)
	}
	return file, nil
}

func collectLibraryFiles(root, entry string) ([]string, error) {
	paths := []string{}
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			if os.IsNotExist(err) {
				return nil
			}
			return err
		}
		if info.IsDir() || filepath.Ext(path) != ".go" || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		absolute, err := filepath.Abs(path)
		if err != nil {
			return err
		}
		if absolute != entry {
			paths = append(paths, absolute)
		}
		return nil
	})
	sort.Strings(paths)
	return paths, err
}

func combine(entry sourceFile, libraries []sourceFile) (*ast.File, error) {
	imports := []*ast.ImportSpec{}
	importByPath := map[string]*ast.ImportSpec{}
	declarations := []ast.Decl{}
	libraryAliases := map[string]bool{}

	for _, source := range append([]sourceFile{entry}, libraries...) {
		for _, spec := range source.file.Imports {
			path := spec.Path.Value
			if !source.isLibrary && strings.Trim(path, "\"") == libraryImportPath {
				alias := importName(spec)
				if alias == "" {
					alias = filepath.Base(strings.Trim(path, "\""))
				}
				if alias != "" && alias != "." && alias != "_" {
					libraryAliases[alias] = true
				}
				continue
			}
			if existing, ok := importByPath[path]; ok {
				if importName(existing) != importName(spec) {
					return nil, fmt.Errorf("import %s has conflicting names", path)
				}
				continue
			}
			importByPath[path] = spec
			imports = append(imports, spec)
		}

		for _, declaration := range source.file.Decls {
			if gen, ok := declaration.(*ast.GenDecl); ok && gen.Tok == token.IMPORT {
				continue
			}
			if !source.isLibrary {
				rewriteLibrarySelectors(declaration, libraryAliases)
			}
			declarations = append(declarations, declaration)
		}
	}

	imports = usedImports(imports, declarations)
	if len(imports) > 0 {
		declarations = append([]ast.Decl{&ast.GenDecl{
			Tok:   token.IMPORT,
			Specs: importSpecs(imports),
		}}, declarations...)
	}

	return &ast.File{
		Name:  ast.NewIdent("main"),
		Decls: declarations,
	}, nil
}

var (
	selectorExprPtrType = reflect.TypeOf((*ast.SelectorExpr)(nil))
	objectPtrType       = reflect.TypeOf((*ast.Object)(nil))
)

// rewriteLibrarySelectors removes the package qualifier from references to
// the project library before the source files are combined into package main.
func rewriteLibrarySelectors(node ast.Node, aliases map[string]bool) {
	rewriteAST(reflect.ValueOf(node), aliases)
}

func rewriteAST(value reflect.Value, aliases map[string]bool) reflect.Value {
	if !value.IsValid() {
		return value
	}
	if value.Type() == objectPtrType {
		return value
	}

	switch value.Kind() {
	case reflect.Interface:
		if value.IsNil() {
			return value
		}
		rewritten := rewriteAST(value.Elem(), aliases)
		if value.CanSet() && rewritten.IsValid() && rewritten.Type().AssignableTo(value.Type()) {
			value.Set(rewritten)
		}
		return value
	case reflect.Pointer:
		if value.IsNil() {
			return value
		}
		if value.Type() == selectorExprPtrType {
			selector := value.Interface().(*ast.SelectorExpr)
			rewriteAST(value.Elem(), aliases)
			if ident, ok := selector.X.(*ast.Ident); ok && aliases[ident.Name] {
				return reflect.ValueOf(ast.NewIdent(selector.Sel.Name))
			}
			return value
		}
		rewriteAST(value.Elem(), aliases)
		return value
	case reflect.Struct:
		for i := 0; i < value.NumField(); i++ {
			field := value.Field(i)
			if field.CanSet() {
				rewriteAST(field, aliases)
			}
		}
	case reflect.Slice, reflect.Array:
		for i := 0; i < value.Len(); i++ {
			rewriteAST(value.Index(i), aliases)
		}
	}
	return value
}

func importSpecs(imports []*ast.ImportSpec) []ast.Spec {
	specs := make([]ast.Spec, len(imports))
	for i, spec := range imports {
		specs[i] = spec
	}
	return specs
}

func importName(spec *ast.ImportSpec) string {
	if spec.Name == nil {
		return ""
	}
	return spec.Name.Name
}

func usedImports(imports []*ast.ImportSpec, declarations []ast.Decl) []*ast.ImportSpec {
	used := map[string]bool{}
	for _, declaration := range declarations {
		ast.Inspect(declaration, func(node ast.Node) bool {
			if ident, ok := node.(*ast.Ident); ok {
				used[ident.Name] = true
			}
			return true
		})
	}

	result := make([]*ast.ImportSpec, 0, len(imports))
	for _, spec := range imports {
		name := importName(spec)
		if name == "_" || name == "." {
			result = append(result, spec)
			continue
		}
		if name == "" {
			path := strings.Trim(spec.Path.Value, "\"")
			name = filepath.Base(path)
		}
		if used[name] {
			result = append(result, spec)
		}
	}
	return result
}

func findProjectRoot(start string) string {
	current, err := filepath.Abs(start)
	if err != nil {
		return "."
	}
	for {
		if _, err := os.Stat(filepath.Join(current, "go.mod")); err == nil {
			return current
		}
		parent := filepath.Dir(current)
		if parent == current {
			return start
		}
		current = parent
	}
}
