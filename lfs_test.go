package lfs_test

import (
	"bufio"
	"crypto/md5"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

func TestExampleDescriptorsAreValid(t *testing.T) {
	tests := []struct {
		folder         string
		descriptorName string
	}{
		{folder: "build-system", descriptorName: "xbee-pack-system.yaml"},
		{folder: "rootfs", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "image", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/sources", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/cross-toolchain", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/temporary-system", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/chroot-system", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/final-sources", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/final-system", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/bootable-system", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/provisioned-system", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/cloud-image", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/uefi-system", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/release-system", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-manager", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-template", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-zlib", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-bzip2", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-xz", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-zstd", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-repository", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/system-rootfs", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/lfs-system", descriptorName: "xbee-pack-system.yaml"},
	}

	for _, test := range tests {
		t.Run(test.folder, func(t *testing.T) {
			path := filepath.Join(test.folder, test.descriptorName)
			content, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}

			var descriptor struct {
				SchemaVersion string         `yaml:"schema-version"`
				Require       string         `yaml:"require"`
				Build         []any          `yaml:"build"`
				System        map[string]any `yaml:"system"`
			}
			if err := yaml.Unmarshal(content, &descriptor); err != nil {
				t.Fatalf("invalid YAML: %v", err)
			}
			if descriptor.SchemaVersion != "1.0" {
				t.Fatalf("unsupported schema-version %q", descriptor.SchemaVersion)
			}
			if test.descriptorName == "xbee-pack-builder.yaml" {
				if descriptor.Require == "" {
					t.Fatal("builder descriptor must define require")
				}
				if len(descriptor.Build) == 0 {
					t.Fatal("builder descriptor must define build steps")
				}
			}
			if test.descriptorName == "xbee-pack-system.yaml" && len(descriptor.System) == 0 {
				t.Fatal("system descriptor must define system")
			}
		})
	}
}

func TestBuildScriptsHaveValidBashSyntax(t *testing.T) {
	scripts := []string{
		"rootfs/resources/build-rootfs.sh",
		"image/resources/build-image.sh",
		"native/sources/resources/download-sources.sh",
		"native/cross-toolchain/resources/build-cross-toolchain.sh",
		"native/temporary-system/resources/build-temporary-system.sh",
		"native/chroot-system/resources/build-chroot-system.sh",
		"native/final-sources/resources/download-final-sources.sh",
		"native/final-system/resources/build-final-system.sh",
		"native/bootable-system/resources/build-bootable-system.sh",
		"native/provisioned-system/resources/download-provisioning-sources.sh",
		"native/provisioned-system/resources/build-provisioned-system.sh",
		"native/cloud-image/resources/xbee-nocloud",
		"native/cloud-image/resources/build-cloud-image.sh",
		"native/uefi-system/resources/build-uefi-system.sh",
		"native/release-system/resources/build-release-system.sh",
		"native/release-system/resources/smoke-test.sh",
		"native/package-manager/resources/xbpkg",
		"native/package-template/resources/build-xbpkg.sh",
		"native/package-repository/resources/build-package-repository.sh",
		"native/system-rootfs/resources/build-system-rootfs.sh",
	}
	for _, script := range scripts {
		t.Run(script, func(t *testing.T) {
			if output, err := exec.Command("bash", "-n", script).CombinedOutput(); err != nil {
				t.Fatalf("bash syntax check failed: %v\n%s", err, output)
			}
		})
	}
}

func TestNativeSourceManifest(t *testing.T) {
	validateSourceManifest(t, "native/sources/resources/sources.tsv", 29)
	validateSourceManifest(t, "native/final-sources/resources/sources.tsv", 63)
}

func TestNativeSourceDownloaderFallsBackFromGNUDispatcher(t *testing.T) {
	tempDir := t.TempDir()
	binDir := filepath.Join(tempDir, "bin")
	outputDir := filepath.Join(tempDir, "out")
	manifest := filepath.Join(tempDir, "sources.tsv")
	logFile := filepath.Join(tempDir, "wget.log")
	payload := "verified GNU source\n"
	checksum := fmt.Sprintf("%x", md5.Sum([]byte(payload)))

	if err := os.Mkdir(binDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(manifest, []byte(fmt.Sprintf(
		"%s\ttest.tar.xz\thttps://ftpmirror.gnu.org/test/test.tar.xz\n",
		checksum,
	)), 0o644); err != nil {
		t.Fatal(err)
	}

	fakeWget := `#!/usr/bin/env bash
set -eu
output=
url=
for arg in "$@"; do
  case "$arg" in
    --output-document=*) output=${arg#*=} ;;
    https://*) url=$arg ;;
  esac
done
printf '%s\n' "$url" >>"$WGET_LOG"
if [[ "$url" == https://ftp.gnu.org/gnu/* ]]; then
  printf 'verified GNU source\n' >"$output"
  exit 0
fi
exit 1
`
	fakeWgetPath := filepath.Join(binDir, "wget")
	if err := os.WriteFile(fakeWgetPath, []byte(fakeWget), 0o755); err != nil {
		t.Fatal(err)
	}

	command := exec.Command(
		"bash",
		"native/sources/resources/download-sources.sh",
		manifest,
		"1",
		outputDir,
	)
	command.Env = append(
		os.Environ(),
		"PATH="+binDir+":"+os.Getenv("PATH"),
		"WGET_LOG="+logFile,
	)
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("source downloader failed: %v\n%s", err, output)
	}

	downloaded, err := os.ReadFile(filepath.Join(
		outputDir,
		"opt/xbee-lfs-native/sources/test.tar.xz",
	))
	if err != nil {
		t.Fatal(err)
	}
	if string(downloaded) != payload {
		t.Fatalf("unexpected downloaded content: %q", downloaded)
	}

	attempts, err := os.ReadFile(logFile)
	if err != nil {
		t.Fatal(err)
	}
	expectedAttempts := strings.Join([]string{
		"https://ftpmirror.gnu.org/test/test.tar.xz",
		"https://ftp.gnu.org/gnu/test/test.tar.xz",
		"",
	}, "\n")
	if string(attempts) != expectedAttempts {
		t.Fatalf("unexpected mirror attempts:\n%s", attempts)
	}
}

func validateSourceManifest(t *testing.T, path string, expected int) {
	t.Helper()
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()

	names := map[string]bool{}
	count := 0
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) != 3 {
			t.Fatalf("expected three tab-separated fields: %q", line)
		}
		checksum, name, url := fields[0], fields[1], fields[2]
		if len(checksum) != 32 {
			t.Fatalf("invalid MD5 for %s: %q", name, checksum)
		}
		if names[name] {
			t.Fatalf("duplicate source: %s", name)
		}
		if !strings.HasPrefix(url, "https://") {
			t.Fatalf("source does not use HTTPS: %s", url)
		}
		names[name] = true
		count++
	}
	if err := scanner.Err(); err != nil {
		t.Fatal(err)
	}
	if count != expected {
		t.Fatalf("expected %d sources in %s, got %d", expected, path, count)
	}
}
