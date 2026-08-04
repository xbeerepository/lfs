package lfs_test

import (
	"bufio"
	"crypto/md5"
	"crypto/sha256"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"gopkg.in/yaml.v3"
)

func TestPackageBuildersReferenceExistingPackages(t *testing.T) {
	descriptors, err := filepath.Glob(
		"native/package-*/xbee-pack-builder.yaml",
	)
	if err != nil {
		t.Fatal(err)
	}
	for _, descriptor := range descriptors {
		content, err := os.ReadFile(descriptor)
		if err != nil {
			t.Fatal(err)
		}
		var model struct {
			Builder []struct {
				Origin string `yaml:"origin"`
				Alias  string `yaml:"alias"`
			} `yaml:"builder"`
			Var struct {
				Package struct {
					Name string `yaml:"name"`
				} `yaml:"package"`
			} `yaml:"var"`
		}
		if err := yaml.Unmarshal(content, &model); err != nil {
			t.Fatalf("%s: %v", descriptor, err)
		}
		if model.Var.Package.Name == "" {
			continue
		}
		for _, builder := range model.Builder {
			if !strings.HasPrefix(builder.Origin, "../package-") ||
				builder.Origin == "../package-template" {
				continue
			}
			expectedAlias := strings.TrimPrefix(
				builder.Origin, "../package-",
			)
			if builder.Alias != expectedAlias {
				t.Errorf(
					"%s: package builder %q must use alias %q",
					descriptor, builder.Origin, expectedAlias,
				)
			}
			if _, err := os.Stat(filepath.Join(
				filepath.Dir(descriptor), builder.Origin,
				"xbee-pack-builder.yaml",
			)); err != nil {
				t.Errorf(
					"%s: package builder %q does not exist: %v",
					descriptor, builder.Origin, err,
				)
			}
		}
	}
}

func TestPackageSystemProfiles(t *testing.T) {
	descriptors, err := filepath.Glob(
		"native/package-*/xbee-pack-builder.yaml",
	)
	if err != nil {
		t.Fatal(err)
	}
	dependencies := make(map[string][]string)
	for _, descriptor := range descriptors {
		content, err := os.ReadFile(descriptor)
		if err != nil {
			t.Fatal(err)
		}
		var model struct {
			Var struct {
				Package struct {
					Name                string `yaml:"name"`
					RuntimeDependencies string `yaml:"runtime-dependencies"`
				} `yaml:"package"`
			} `yaml:"var"`
		}
		if err := yaml.Unmarshal(content, &model); err != nil {
			t.Fatalf("%s: %v", descriptor, err)
		}
		if model.Var.Package.Name == "" {
			continue
		}
		var packageDependencies []string
		if model.Var.Package.RuntimeDependencies != "" {
			packageDependencies = strings.Split(
				model.Var.Package.RuntimeDependencies, ",",
			)
		}
		dependencies[model.Var.Package.Name] = packageDependencies
	}
	resolve := func(profile string) map[string]bool {
		t.Helper()
		content, err := os.ReadFile(filepath.Join(
			"native/package-system-tools/resources/profiles", profile+".txt",
		))
		if err != nil {
			t.Fatal(err)
		}
		resolved := make(map[string]bool)
		var add func(string)
		add = func(name string) {
			if resolved[name] {
				return
			}
			if _, ok := dependencies[name]; !ok {
				t.Fatalf("%s profile references unknown package %q", profile, name)
			}
			resolved[name] = true
			for _, dependency := range dependencies[name] {
				add(dependency)
			}
		}
		for _, line := range strings.Split(string(content), "\n") {
			name := strings.TrimSpace(strings.SplitN(line, "#", 2)[0])
			if name != "" {
				add(name)
			}
		}
		return resolved
	}
	full := resolve("full")
	if len(full) != 91 || len(full) != len(dependencies) {
		t.Fatalf(
			"full profile resolves %d of %d packages, expected 91",
			len(full), len(dependencies),
		)
	}
	minimal := resolve("minimal")
	for _, required := range []string{
		"bash", "coreutils", "systemd", "openssh", "dhcpcd", "wget",
		"linux-kernel", "linux-modules",
	} {
		if !minimal[required] {
			t.Errorf("minimal profile is missing %s", required)
		}
	}
	for _, excluded := range []string{"curl", "gcc"} {
		if minimal[excluded] {
			t.Errorf("minimal profile unexpectedly resolves %s", excluded)
		}
	}
	if len(minimal) >= len(full) {
		t.Errorf(
			"minimal profile resolves %d packages, full resolves %d",
			len(minimal), len(full),
		)
	}
	t.Logf("minimal profile resolves %d packages", len(minimal))
}

func TestExampleDescriptorsAreValid(t *testing.T) {
	tests := []struct {
		folder         string
		descriptorName string
	}{
		{folder: ".", descriptorName: "xbee-pack-system.yaml"},
		{folder: "build-system", descriptorName: "xbee-pack-system.yaml"},
		{folder: "native/sources", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/cross-toolchain", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/temporary-system", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/chroot-system", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/final-sources", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/final-system", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/bootable-system", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/provisioned-system", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/cloud-image", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/nocloud-agent", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/uefi-system", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/release-system", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-manager", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-template", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-system-tools", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-minimal-system", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-glibc", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-linux-headers", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-linux-kernel", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-linux-modules", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-openssh", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-sudo", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-ca-certificates", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-wget", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-curl", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-dhcpcd", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-rsync", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-zlib", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-bzip2", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-xz", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-zstd", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-lz4", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-attr", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-acl", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-libpipeline", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-man-db", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-ncurses", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-readline", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-pcre2", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-libcap", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-libelf", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-gmp", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-mpfr", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-mpc", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-m4", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-bison", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-flex", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-autoconf", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-automake", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-libtool", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-pkgconf", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-binutils", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-gcc", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-libffi", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-expat", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-gdbm", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-openssl", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-sqlite", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-python", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-flit-core", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-packaging", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-markupsafe", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-jinja2", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-meson", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-ninja", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-bc", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-gperf", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-libxcrypt", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-less", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-kmod", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-procps-ng", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-e2fsprogs", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-shadow", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-iproute2", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-inetutils", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-kbd", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-psmisc", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-man-pages", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-iana-etc", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-file", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-tcl", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-expect", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-dejagnu", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-sed", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-gettext", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-grep", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-bash", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-perl", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-xml-parser", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-intltool", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-wheel", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-setuptools", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-coreutils", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-diffutils", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-gawk", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-findutils", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-groff", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-gzip", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-make", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-patch", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-tar", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-texinfo", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-vim", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-dbus", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-util-linux", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-systemd", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-grub", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-repository", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-system", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-uefi-system", descriptorName: "xbee-pack-builder.yaml"},
		{folder: "native/package-release-system", descriptorName: "xbee-pack-builder.yaml"},
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

func TestVirtualBoxSystemPackMatchesRelease(t *testing.T) {
	systemPack, err := os.ReadFile("xbee-pack-system.yaml")
	if err != nil {
		t.Fatal(err)
	}
	kernelConfig, err := os.ReadFile(
		"native/bootable-system/resources/kernel-x86_64.config",
	)
	if err != nil {
		t.Fatal(err)
	}
	releaseBuilder, err := os.ReadFile(
		"native/release-system/resources/build-release-system.sh",
	)
	if err != nil {
		t.Fatal(err)
	}

	for _, expected := range []string{
		"guest-additions: false",
		"xbee-lfs-native-13.0-x86_64-virtualbox.vmdk",
	} {
		if !strings.Contains(string(systemPack), expected) {
			t.Errorf("system pack does not contain %q", expected)
		}
	}
	if !strings.Contains(string(releaseBuilder), "-virtualbox.vmdk") {
		t.Fatal("release builder does not produce the VirtualBox VMDK")
	}
	for _, expected := range []string{
		"/dev/vda1|/dev/sda1",
		"subformat=monolithicSparse",
	} {
		if !strings.Contains(string(releaseBuilder), expected) {
			t.Errorf("release builder does not contain %q", expected)
		}
	}
	for _, expected := range []string{
		"CONFIG_BLK_DEV_SD=y",
		"CONFIG_ATA=y",
		"CONFIG_SATA_AHCI=y",
		"CONFIG_E1000=y",
	} {
		if !strings.Contains(string(kernelConfig), expected) {
			t.Errorf("kernel configuration does not contain %q", expected)
		}
	}
}

func TestBuildScriptsHaveValidBashSyntax(t *testing.T) {
	scripts := []string{
		"native/sources/resources/download-sources.sh",
		"native/cross-toolchain/resources/build-cross-toolchain.sh",
		"native/temporary-system/resources/build-temporary-system.sh",
		"native/chroot-system/resources/build-chroot-system.sh",
		"native/final-sources/resources/download-final-sources.sh",
		"native/final-system/resources/build-final-system.sh",
		"native/bootable-system/resources/build-bootable-system.sh",
		"native/provisioned-system/resources/download-provisioning-sources.sh",
		"native/provisioned-system/resources/build-provisioned-system.sh",
		"native/nocloud-agent/resources/xbee-nocloud",
		"native/cloud-image/resources/build-cloud-image.sh",
		"native/uefi-system/resources/build-uefi-system.sh",
		"native/release-system/resources/build-release-system.sh",
		"native/release-system/resources/smoke-test.sh",
		"native/package-manager/resources/xbpkg",
		"native/package-manager/resources/build-trust-root.sh",
		"native/package-template/resources/build-xbpkg.sh",
		"native/package-repository/resources/build-package-repository.sh",
		"native/package-system-tools/resources/build-package-system.sh",
		"native/package-system/resources/smoke-test.sh",
		"native/package-uefi-system/resources/build-package-uefi-system.sh",
		"native/package-release-system/resources/build-package-release-system.sh",
		"native/package-release-system/resources/verify-release.sh",
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
	validateSourceManifest(t, "native/final-sources/resources/sources.tsv", 70)
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
if [[ "$url" == https://mirrors.kernel.org/gnu/* ]]; then
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
		"https://mirrors.kernel.org/gnu/test/test.tar.xz",
		"",
	}, "\n")
	if string(attempts) != expectedAttempts {
		t.Fatalf("unexpected mirror attempts:\n%s", attempts)
	}
}

func TestXbpkgVerifiesThresholdTrustRoot(t *testing.T) {
	manager, err := filepath.Abs("native/package-manager/resources/xbpkg")
	if err != nil {
		t.Fatal(err)
	}
	builder, err := filepath.Abs(
		"native/package-manager/resources/build-trust-root.sh",
	)
	if err != nil {
		t.Fatal(err)
	}
	repositoryPackage := buildTestPackage(
		t, "trusted-policy", "", "usr/bin/trusted-policy",
	)
	repository := buildTestRepository(t, repositoryPackage)
	publicDER, err := exec.Command(
		"openssl", "pkey", "-pubin",
		"-in", filepath.Join(repository, "trusted-key.pem"),
		"-outform", "DER",
	).Output()
	if err != nil {
		t.Fatal(err)
	}
	repositoryKeyID := fmt.Sprintf("%x", sha256.Sum256(publicDER))
	keysDir := t.TempDir()
	privateKeys := make([]string, 3)
	for index := range privateKeys {
		privateKeys[index] = filepath.Join(keysDir, fmt.Sprintf("root-%d.pem", index))
		if output, err := exec.Command(
			"openssl", "genpkey", "-algorithm", "Ed25519",
			"-out", privateKeys[index],
		).CombinedOutput(); err != nil {
			t.Fatalf("creating root key failed: %v\n%s", err, output)
		}
	}
	policyOutput := t.TempDir()
	command := exec.Command(
		"bash", builder, policyOutput, "1",
		time.Now().UTC().Add(24*time.Hour).Format("2006-01-02T15:04:05Z"),
		repositoryKeyID, "", "",
	)
	command.Env = append(
		os.Environ(),
		"XBPKG_ROOT_SIGNING_KEYS="+strings.Join(privateKeys, ":"),
		"XBPKG_ROOT_THRESHOLD=2",
	)
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("building TRUST-ROOT failed: %v\n%s", err, output)
	}
	root := filepath.Join(t.TempDir(), "root")
	trustDir := filepath.Join(root, "etc/xbpkg")
	if err := os.MkdirAll(trustDir, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{
		"TRUST-ROOT", "TRUST-ROOT.signatures", "root-keys",
	} {
		if output, err := exec.Command(
			"cp", "-a", filepath.Join(policyOutput, name), trustDir,
		).CombinedOutput(); err != nil {
			t.Fatalf("installing trust policy failed: %v\n%s", err, output)
		}
	}
	if output, err := exec.Command(
		"bash", manager, "--root", root, "trust", "accept",
	).CombinedOutput(); err != nil {
		t.Fatalf("TRUST-ROOT verification failed: %v\n%s", err, output)
	}
	if output, err := exec.Command(
		"bash", manager,
		"--root", root,
		"--repository", repository,
		"--trusted-key", filepath.Join(repository, "trusted-key.pem"),
		"--dry-run", "install", "trusted-policy",
	).CombinedOutput(); err != nil {
		t.Fatalf("delegated repository verification failed: %v\n%s", err, output)
	}
	signatures, err := filepath.Glob(
		filepath.Join(trustDir, "TRUST-ROOT.signatures", "*.sig"),
	)
	if err != nil || len(signatures) != 3 {
		t.Fatalf("unexpected root signatures: %v %v", signatures, err)
	}
	if err := os.Remove(signatures[0]); err != nil {
		t.Fatal(err)
	}
	if output, err := exec.Command(
		"bash", manager, "--root", root, "trust",
	).CombinedOutput(); err != nil {
		t.Fatalf("2-of-3 TRUST-ROOT verification failed: %v\n%s", err, output)
	}
	if err := os.Remove(signatures[1]); err != nil {
		t.Fatal(err)
	}
	output, err := exec.Command(
		"bash", manager, "--root", root, "trust",
	).CombinedOutput()
	if err == nil || !strings.Contains(
		string(output), "signature threshold not met",
	) {
		t.Fatalf("under-threshold TRUST-ROOT was not rejected:\n%s", output)
	}
}

func TestXbpkgEnforcesDependencies(t *testing.T) {
	manager, err := filepath.Abs("native/package-manager/resources/xbpkg")
	if err != nil {
		t.Fatal(err)
	}
	root := filepath.Join(t.TempDir(), "root")
	base := buildTestPackage(t, "base", "", "usr/lib/libbase.so")
	application := buildTestPackage(t, "application", " base ", "usr/bin/application")

	runXbpkg := func(expectSuccess bool, arguments ...string) string {
		t.Helper()
		commandArguments := append([]string{"--root", root}, arguments...)
		output, err := exec.Command("bash", append([]string{manager}, commandArguments...)...).CombinedOutput()
		if expectSuccess && err != nil {
			t.Fatalf("xbpkg %v failed: %v\n%s", arguments, err, output)
		}
		if !expectSuccess && err == nil {
			t.Fatalf("xbpkg %v unexpectedly succeeded:\n%s", arguments, output)
		}
		return string(output)
	}

	output := runXbpkg(false, "install", application)
	if !strings.Contains(output, "missing dependency for application: base") {
		t.Fatalf("unexpected missing-dependency error: %s", output)
	}
	runXbpkg(true, "install", base)
	runXbpkg(true, "install", application)

	output = runXbpkg(false, "remove", "base")
	if !strings.Contains(output, "cannot remove base: required by application") {
		t.Fatalf("unexpected reverse-dependency error: %s", output)
	}
	runXbpkg(true, "remove", "application")
	runXbpkg(true, "remove", "base")
}

func TestReleaseArtifactVerification(t *testing.T) {
	verifier, err := filepath.Abs(
		"native/package-release-system/resources/verify-release.sh",
	)
	if err != nil {
		t.Fatal(err)
	}
	release := t.TempDir()
	artifactPath := filepath.Join(release, "system-release.tar.zst")
	artifact := []byte("signed release artifact\n")
	if err := os.WriteFile(artifactPath, artifact, 0o644); err != nil {
		t.Fatal(err)
	}
	freshness := []byte(fmt.Sprintf(
		"schema-version: 1\npublished-at: %q\nexpires-at: %q\n",
		time.Now().UTC().Add(-time.Hour).Format("2006-01-02T15:04:05Z"),
		time.Now().UTC().Add(24*time.Hour).Format("2006-01-02T15:04:05Z"),
	))
	if err := os.WriteFile(
		filepath.Join(release, "ARTIFACTS.release"), freshness, 0o644,
	); err != nil {
		t.Fatal(err)
	}
	privateKey := filepath.Join(t.TempDir(), "release-private.pem")
	publicKey := filepath.Join(release, "release-ed25519-public.pem")
	for _, command := range [][]string{
		{"genpkey", "-algorithm", "Ed25519", "-out", privateKey},
		{"pkey", "-in", privateKey, "-pubout", "-out", publicKey},
	} {
		if output, err := exec.Command("openssl", command...).CombinedOutput(); err != nil {
			t.Fatalf("creating release key failed: %v\n%s", err, output)
		}
	}
	publicDER, err := exec.Command(
		"openssl", "pkey", "-pubin", "-in", publicKey, "-outform", "DER",
	).Output()
	if err != nil {
		t.Fatal(err)
	}
	keyID := fmt.Sprintf("%x", sha256.Sum256(publicDER))
	if err := os.WriteFile(
		filepath.Join(release, "ARTIFACTS.keyid"),
		[]byte(keyID+"\n"), 0o644,
	); err != nil {
		t.Fatal(err)
	}
	manifest := fmt.Sprintf(
		"%x %d %s\n%x %d ARTIFACTS.release\n",
		sha256.Sum256(artifact), len(artifact), filepath.Base(artifactPath),
		sha256.Sum256(freshness), len(freshness),
	)
	manifestPath := filepath.Join(release, "ARTIFACTS")
	if err := os.WriteFile(manifestPath, []byte(manifest), 0o644); err != nil {
		t.Fatal(err)
	}
	if output, err := exec.Command(
		"openssl", "pkeyutl", "-sign", "-inkey", privateKey,
		"-rawin", "-in", manifestPath,
		"-out", filepath.Join(release, "ARTIFACTS.sig"),
	).CombinedOutput(); err != nil {
		t.Fatalf("signing release manifest failed: %v\n%s", err, output)
	}
	runVerifier := func(expectSuccess bool, arguments ...string) string {
		t.Helper()
		commandArguments := []string{verifier, release, publicKey}
		commandArguments = append(commandArguments, arguments...)
		output, err := exec.Command("bash", commandArguments...).CombinedOutput()
		if expectSuccess && err != nil {
			t.Fatalf("release verification failed: %v\n%s", err, output)
		}
		if !expectSuccess && err == nil {
			t.Fatalf("release verification unexpectedly succeeded:\n%s", output)
		}
		return string(output)
	}
	if output := runVerifier(true); !strings.Contains(
		output, "verified release artifacts",
	) {
		t.Fatalf("unexpected release verification output: %s", output)
	}

	revocations := filepath.Join(t.TempDir(), "revoked-keys")
	if err := os.WriteFile(revocations, []byte(keyID+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if output := runVerifier(false, revocations); !strings.Contains(
		output, "release signing key is revoked",
	) {
		t.Fatalf("unexpected release revocation error: %s", output)
	}
	if err := os.WriteFile(artifactPath, []byte("tampered\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if output := runVerifier(false); !strings.Contains(
		output, "size mismatch",
	) {
		t.Fatalf("unexpected tampered release error: %s", output)
	}
	if err := os.WriteFile(artifactPath, artifact, 0o644); err != nil {
		t.Fatal(err)
	}
	unexpected := filepath.Join(release, "unexpected")
	if err := os.WriteFile(unexpected, []byte("unexpected\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if output := runVerifier(false); !strings.Contains(
		output, "unexpected release artefact",
	) {
		t.Fatalf("unexpected extra artifact error: %s", output)
	}
}

func TestXbpkgSerializesMutations(t *testing.T) {
	manager, err := filepath.Abs("native/package-manager/resources/xbpkg")
	if err != nil {
		t.Fatal(err)
	}
	root := filepath.Join(t.TempDir(), "root")
	database := filepath.Join(root, "var/lib/xbpkg")
	if err := os.MkdirAll(database, 0o755); err != nil {
		t.Fatal(err)
	}
	lockPath := filepath.Join(database, "lock")
	readyPath := filepath.Join(t.TempDir(), "ready")
	holder := exec.Command(
		"flock", lockPath,
		"sh", "-c", `printf ready >"$1"; exec sleep 30`, "sh", readyPath,
	)
	if err := holder.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() {
		_ = holder.Process.Kill()
		_ = holder.Wait()
	}()
	for attempt := 0; attempt < 100; attempt++ {
		if _, err := os.Stat(readyPath); err == nil {
			break
		} else if attempt == 99 {
			t.Fatal("timed out waiting for the competing lock holder")
		}
		time.Sleep(10 * time.Millisecond)
	}

	archive := buildTestPackage(t, "locked", "", "usr/bin/locked")
	output, err := exec.Command(
		"bash", manager, "--root", root, "install", archive,
	).CombinedOutput()
	if err == nil {
		t.Fatalf("concurrent installation unexpectedly succeeded:\n%s", output)
	}
	if !strings.Contains(
		string(output), "another package operation is active",
	) {
		t.Fatalf("unexpected lock error: %s", output)
	}
	if _, err := os.Stat(filepath.Join(root, "usr/bin/locked")); !os.IsNotExist(err) {
		t.Fatal("rejected concurrent installation copied its payload")
	}
}

func TestXbpkgPrunesOnlyEmptyPackageDirectories(t *testing.T) {
	manager, err := filepath.Abs("native/package-manager/resources/xbpkg")
	if err != nil {
		t.Fatal(err)
	}
	root := filepath.Join(t.TempDir(), "root")
	prunable := buildTestPackage(
		t, "prunable", "", "usr/share/prunable/deep/payload",
	)
	shared := buildTestPackage(
		t, "shared", "", "opt/shared-package/deep/payload",
	)
	runXbpkg := func(arguments ...string) {
		t.Helper()
		output, err := exec.Command(
			"bash", manager, "--root", root,
			arguments[0], arguments[1],
		).CombinedOutput()
		if err != nil {
			t.Fatalf("xbpkg %v failed: %v\n%s", arguments, err, output)
		}
	}

	runXbpkg("install", prunable)
	runXbpkg("remove", "prunable")
	if _, err := os.Stat(
		filepath.Join(root, "usr/share/prunable"),
	); !os.IsNotExist(err) {
		t.Fatal("remove left the package-only directory tree behind")
	}
	if info, err := os.Stat(filepath.Join(root, "usr")); err != nil {
		t.Fatal("remove deleted the protected /usr directory")
	} else if !info.IsDir() {
		t.Fatal("protected /usr path is not a directory")
	}

	runXbpkg("install", shared)
	unmanaged := filepath.Join(root, "opt/shared-package/unmanaged")
	if err := os.WriteFile(unmanaged, []byte("keep\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runXbpkg("remove", "shared")
	if content, err := os.ReadFile(unmanaged); err != nil {
		t.Fatal("remove deleted an unmanaged file in a shared directory")
	} else if string(content) != "keep\n" {
		t.Fatalf("unexpected unmanaged content: %q", content)
	}
	if _, err := os.Stat(filepath.Join(root, "opt/shared-package/deep")); !os.IsNotExist(err) {
		t.Fatal("remove left an empty package subdirectory behind")
	}
}

func TestXbpkgRecoversPersistentTransactions(t *testing.T) {
	manager, err := filepath.Abs("native/package-manager/resources/xbpkg")
	if err != nil {
		t.Fatal(err)
	}
	root := filepath.Join(t.TempDir(), "root")
	recoverable := buildTestPackage(
		t, "recoverable", "", "opt/recovery/deep/payload",
	)
	committed := buildTestPackage(
		t, "committed", "", "usr/lib/committed-payload",
	)
	runXbpkg := func(expectSuccess bool, arguments ...string) string {
		t.Helper()
		commandArguments := append([]string{"--root", root}, arguments...)
		output, err := exec.Command(
			"bash", append([]string{manager}, commandArguments...)...,
		).CombinedOutput()
		if expectSuccess && err != nil {
			t.Fatalf("xbpkg %v failed: %v\n%s", arguments, err, output)
		}
		if !expectSuccess && err == nil {
			t.Fatalf("xbpkg %v unexpectedly succeeded:\n%s", arguments, output)
		}
		return string(output)
	}
	writeJournal := func(state, name, path string) {
		t.Helper()
		journal := filepath.Join(root, "var/lib/xbpkg/transactions/current")
		if err := os.MkdirAll(journal, 0o755); err != nil {
			t.Fatal(err)
		}
		for filename, content := range map[string]string{
			"state":     state + "\n",
			"packages":  name + "\n",
			"files":     path + "\n",
			"completed": "",
		} {
			if err := os.WriteFile(
				filepath.Join(journal, filename), []byte(content), 0o644,
			); err != nil {
				t.Fatal(err)
			}
		}
	}

	runXbpkg(true, "install", recoverable)
	writeJournal("prepared", "recoverable", "/opt/recovery/deep/payload")
	if output := runXbpkg(false, "check"); !strings.Contains(
		output, "unfinished transaction journal",
	) {
		t.Fatalf("check did not report the unfinished transaction:\n%s", output)
	}
	if output := runXbpkg(false, "remove", "recoverable"); !strings.Contains(
		output, "unfinished transaction",
	) {
		t.Fatalf("mutation was not blocked by the journal:\n%s", output)
	}
	if output := runXbpkg(true, "recover"); output != "recovered unfinished transaction\n" {
		t.Fatalf("unexpected recovery output: %s", output)
	}
	if _, err := os.Stat(filepath.Join(root, "opt/recovery")); !os.IsNotExist(err) {
		t.Fatal("recovery left its payload directory behind")
	}
	if _, err := os.Stat(
		filepath.Join(root, "var/lib/xbpkg/installed/recoverable"),
	); !os.IsNotExist(err) {
		t.Fatal("recovery left its package database entry behind")
	}

	runXbpkg(true, "install", committed)
	writeJournal("committed", "committed", "/usr/lib/committed-payload")
	if output := runXbpkg(true, "recover"); output != "finalized committed transaction\n" {
		t.Fatalf("unexpected committed recovery output: %s", output)
	}
	if _, err := os.Stat(filepath.Join(root, "usr/lib/committed-payload")); err != nil {
		t.Fatal("committed recovery removed the installed payload")
	}
	if output := runXbpkg(true, "recover"); output != "no unfinished transaction\n" {
		t.Fatalf("unexpected empty recovery output: %s", output)
	}
}

func TestXbpkgChecksInstalledState(t *testing.T) {
	manager, err := filepath.Abs("native/package-manager/resources/xbpkg")
	if err != nil {
		t.Fatal(err)
	}
	root := filepath.Join(t.TempDir(), "root")
	base := buildTestPackage(t, "base", "", "usr/lib/libbase.so")
	configured := buildTestPackageVersionWithConffiles(
		t, "configured", "1.0.0", "base", "etc/configured.conf",
		[]string{"/etc/configured.conf"},
	)
	runXbpkg := func(expectSuccess bool, arguments ...string) string {
		t.Helper()
		commandArguments := append([]string{"--root", root}, arguments...)
		output, err := exec.Command(
			"bash", append([]string{manager}, commandArguments...)...,
		).CombinedOutput()
		if expectSuccess && err != nil {
			t.Fatalf("xbpkg %v failed: %v\n%s", arguments, err, output)
		}
		if !expectSuccess && err == nil {
			t.Fatalf("xbpkg %v unexpectedly succeeded:\n%s", arguments, output)
		}
		return string(output)
	}

	runXbpkg(true, "install", base)
	runXbpkg(true, "install", configured)
	if output := runXbpkg(true, "check"); output != "checked 2 packages\n" {
		t.Fatalf("unexpected consistency report: %s", output)
	}

	configPath := filepath.Join(root, "etc/configured.conf")
	if err := os.WriteFile(configPath, []byte("local configuration\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(configPath+".xbpkg-new", []byte("new configuration\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	output := runXbpkg(true, "check")
	if !strings.Contains(output, "modified configuration /etc/configured.conf") ||
		!strings.Contains(output, "pending configuration /etc/configured.conf.xbpkg-new") ||
		!strings.Contains(output, "checked 2 packages") {
		t.Fatalf("configuration state was not reported correctly:\n%s", output)
	}

	basePath := filepath.Join(root, "usr/lib/libbase.so")
	if err := os.WriteFile(basePath, []byte("corrupted\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	output = runXbpkg(false, "check")
	if !strings.Contains(output, "immutable payload checksum mismatch") ||
		!strings.Contains(output, "consistency check failed") {
		t.Fatalf("immutable corruption was not detected:\n%s", output)
	}
	if err := os.WriteFile(basePath, []byte("base 1.0.0\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.RemoveAll(filepath.Join(root, "var/lib/xbpkg/installed/base")); err != nil {
		t.Fatal(err)
	}
	output = runXbpkg(false, "check")
	if !strings.Contains(output, "missing dependency for configured: base") {
		t.Fatalf("missing dependency was not detected:\n%s", output)
	}

	cycleRoot := filepath.Join(t.TempDir(), "root")
	cycleA := buildTestPackage(t, "cycle-a", "", "usr/lib/cycle-a")
	cycleB := buildTestPackage(t, "cycle-b", "", "usr/lib/cycle-b")
	for _, archive := range []string{cycleA, cycleB} {
		output, err := exec.Command(
			"bash", manager, "--root", cycleRoot, "install", archive,
		).CombinedOutput()
		if err != nil {
			t.Fatalf("installing cycle fixture failed: %v\n%s", err, output)
		}
	}
	for name, dependency := range map[string]string{
		"cycle-a": "cycle-b",
		"cycle-b": "cycle-a",
	} {
		manifestPath := filepath.Join(
			cycleRoot, "var/lib/xbpkg/installed", name, "manifest.yaml",
		)
		content, err := os.ReadFile(manifestPath)
		if err != nil {
			t.Fatal(err)
		}
		content = []byte(strings.Replace(
			string(content), `dependencies: ""`,
			fmt.Sprintf(`dependencies: "%s"`, dependency), 1,
		))
		if err := os.WriteFile(manifestPath, content, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	outputBytes, err := exec.Command(
		"bash", manager, "--root", cycleRoot, "check",
	).CombinedOutput()
	if err == nil || !strings.Contains(
		string(outputBytes), "dependency cycle detected",
	) {
		t.Fatalf("dependency cycle was not detected:\n%s", outputBytes)
	}
}

func TestXbpkgUpgrade(t *testing.T) {
	manager, err := filepath.Abs("native/package-manager/resources/xbpkg")
	if err != nil {
		t.Fatal(err)
	}
	root := filepath.Join(t.TempDir(), "root")
	baseV1 := buildTestPackageVersion(
		t, "base", "1.0.0", "", "usr/lib/libbase-old.so",
	)
	baseV2 := buildTestPackageVersion(
		t, "base", "2.0.0", "", "usr/lib/libbase-new.so",
	)
	sameVersion := buildTestPackageVersion(
		t, "base", "2.0.0", "", "usr/lib/libbase-newer.so",
	)
	missingDependency := buildTestPackageVersion(
		t, "base", "3.0.0", "missing", "usr/lib/libbase-v3.so",
	)
	other := buildTestPackageVersion(
		t, "other", "1.0.0", "", "usr/bin/shared-path",
	)
	collision := buildTestPackageVersion(
		t, "base", "3.0.0", "", "usr/bin/shared-path",
	)

	runXbpkg := func(expectSuccess bool, arguments ...string) string {
		t.Helper()
		commandArguments := append([]string{"--root", root}, arguments...)
		output, err := exec.Command(
			"bash", append([]string{manager}, commandArguments...)...,
		).CombinedOutput()
		if expectSuccess && err != nil {
			t.Fatalf("xbpkg %v failed: %v\n%s", arguments, err, output)
		}
		if !expectSuccess && err == nil {
			t.Fatalf("xbpkg %v unexpectedly succeeded:\n%s", arguments, output)
		}
		return string(output)
	}

	runXbpkg(true, "install", baseV1)
	output := runXbpkg(true, "upgrade", baseV2)
	if !strings.Contains(output, "upgraded base 1.0.0 -> 2.0.0") {
		t.Fatalf("unexpected upgrade output: %s", output)
	}
	if _, err := os.Stat(filepath.Join(root, "usr/lib/libbase-old.so")); !os.IsNotExist(err) {
		t.Fatal("upgrade did not remove the obsolete payload")
	}
	if content, err := os.ReadFile(filepath.Join(root, "usr/lib/libbase-new.so")); err != nil {
		t.Fatal(err)
	} else if string(content) != "base 2.0.0\n" {
		t.Fatalf("unexpected upgraded payload: %q", content)
	}
	runXbpkg(true, "verify", "base")

	for _, test := range []struct {
		archive string
		error   string
	}{
		{sameVersion, "already at version 2.0.0"},
		{missingDependency, "missing dependency for base: missing"},
	} {
		output = runXbpkg(false, "upgrade", test.archive)
		if !strings.Contains(output, test.error) {
			t.Fatalf("unexpected upgrade rejection: %s", output)
		}
	}

	runXbpkg(true, "install", other)
	output = runXbpkg(false, "upgrade", collision)
	if !strings.Contains(output, "is owned by other") {
		t.Fatalf("unexpected collision rejection: %s", output)
	}
	runXbpkg(true, "verify", "base")
	if !strings.Contains(runXbpkg(true, "list"), "base 2.0.0") {
		t.Fatal("failed upgrade changed the installed version")
	}
}

func TestXbpkgUpdatesSystemTransactionally(t *testing.T) {
	manager, err := filepath.Abs("native/package-manager/resources/xbpkg")
	if err != nil {
		t.Fatal(err)
	}
	root := filepath.Join(t.TempDir(), "root")
	baseV1 := buildTestPackageVersion(
		t, "base", "1.0.0", "", "usr/lib/libbase-old.so",
	)
	applicationV1 := buildTestPackageVersion(
		t, "application", "1.0.0", "base >= 1.0.0", "usr/bin/application-old",
	)
	baseV2 := buildTestPackageVersion(
		t, "base", "2.0.0", "", "usr/lib/libbase-new.so",
	)
	applicationV2 := buildTestPackageVersion(
		t, "application", "2.0.0", "base >= 2.0.0", "usr/bin/application-new",
	)
	other := buildTestPackageVersion(
		t, "other", "1.0.0", "", "usr/bin/application-new",
	)
	repository := buildTestRepository(t, baseV2, applicationV2, other)
	trustedKey := filepath.Join(repository, "trusted-key.pem")

	runXbpkg := func(expectSuccess bool, arguments ...string) string {
		t.Helper()
		commandArguments := append([]string{"--root", root}, arguments...)
		output, err := exec.Command(
			"bash", append([]string{manager}, commandArguments...)...,
		).CombinedOutput()
		if expectSuccess && err != nil {
			t.Fatalf("xbpkg %v failed: %v\n%s", arguments, err, output)
		}
		if !expectSuccess && err == nil {
			t.Fatalf("xbpkg %v unexpectedly succeeded:\n%s", arguments, output)
		}
		return string(output)
	}
	updateArguments := []string{
		"--repository", repository, "--trusted-key", trustedKey,
	}

	runXbpkg(true, "install", baseV1)
	runXbpkg(true, "install", applicationV1)
	output := runXbpkg(
		true, append(updateArguments, "--dry-run", "update")...,
	)
	basePlan := strings.Index(output, "upgrade base 1.0.0 -> 2.0.0")
	applicationPlan := strings.Index(
		output, "upgrade application 1.0.0 -> 2.0.0",
	)
	if basePlan < 0 || applicationPlan < 0 || basePlan > applicationPlan {
		t.Fatalf("unexpected update plan: %s", output)
	}
	if !strings.Contains(runXbpkg(true, "list"), "base 1.0.0") {
		t.Fatal("dry-run changed installed packages")
	}

	output = runXbpkg(true, append(updateArguments, "update")...)
	if !strings.Contains(output, "upgraded base 1.0.0 -> 2.0.0") ||
		!strings.Contains(output, "upgraded application 1.0.0 -> 2.0.0") {
		t.Fatalf("unexpected update output: %s", output)
	}
	list := runXbpkg(true, "list")
	if !strings.Contains(list, "base 2.0.0") ||
		!strings.Contains(list, "application 2.0.0") {
		t.Fatalf("update did not install candidate versions: %s", list)
	}
	runXbpkg(true, "check")
	if content, err := os.ReadFile(
		filepath.Join(root, "var/lib/xbpkg/repositories/test"),
	); err != nil {
		t.Fatal(err)
	} else if !strings.Contains(string(content), "serial: 1") {
		t.Fatalf("repository state was not committed: %s", content)
	}

	rollbackRoot := filepath.Join(t.TempDir(), "root")
	runRollback := func(expectSuccess bool, arguments ...string) string {
		t.Helper()
		commandArguments := append(
			[]string{"--root", rollbackRoot}, arguments...,
		)
		output, err := exec.Command(
			"bash", append([]string{manager}, commandArguments...)...,
		).CombinedOutput()
		if expectSuccess && err != nil {
			t.Fatalf("rollback xbpkg %v failed: %v\n%s", arguments, err, output)
		}
		if !expectSuccess && err == nil {
			t.Fatalf(
				"rollback xbpkg %v unexpectedly succeeded:\n%s",
				arguments, output,
			)
		}
		return string(output)
	}
	runRollback(true, "install", baseV1)
	runRollback(true, "install", applicationV1)
	runRollback(true, "install", other)
	output = runRollback(false, append(updateArguments, "update")...)
	if !strings.Contains(output, "is owned by other") ||
		!strings.Contains(output, "rolling back") {
		t.Fatalf("unexpected failed update output: %s", output)
	}
	list = runRollback(true, "list")
	if !strings.Contains(list, "base 1.0.0") ||
		!strings.Contains(list, "application 1.0.0") {
		t.Fatalf("failed update was not rolled back: %s", list)
	}
	if _, err := os.Stat(
		filepath.Join(rollbackRoot, "usr/lib/libbase-old.so"),
	); err != nil {
		t.Fatal("rollback did not restore the old base payload")
	}
	if _, err := os.Stat(
		filepath.Join(rollbackRoot, "usr/lib/libbase-new.so"),
	); !os.IsNotExist(err) {
		t.Fatal("rollback retained the new base payload")
	}
	if _, err := os.Stat(
		filepath.Join(rollbackRoot, "var/lib/xbpkg/repositories/test"),
	); !os.IsNotExist(err) {
		t.Fatal("failed update committed repository state")
	}
	runRollback(true, "check")
}

func TestXbpkgPreservesConfigurations(t *testing.T) {
	manager, err := filepath.Abs("native/package-manager/resources/xbpkg")
	if err != nil {
		t.Fatal(err)
	}
	root := filepath.Join(t.TempDir(), "root")
	configV1 := buildTestPackageVersionWithConffiles(
		t, "configured", "1.0.0", "", "etc/configured.conf",
		[]string{"/etc/configured.conf"},
	)
	configV2 := buildTestPackageVersionWithConffiles(
		t, "configured", "2.0.0", "", "etc/configured.conf",
		[]string{"/etc/configured.conf"},
	)
	configV3 := buildTestPackageVersionWithConffiles(
		t, "configured", "3.0.0", "", "etc/configured.conf",
		[]string{"/etc/configured.conf"},
	)
	pristineV1 := buildTestPackageVersionWithConffiles(
		t, "pristine", "1.0.0", "", "etc/pristine.conf",
		[]string{"/etc/pristine.conf"},
	)
	pristineV2 := buildTestPackageVersionWithConffiles(
		t, "pristine", "2.0.0", "", "etc/pristine.conf",
		[]string{"/etc/pristine.conf"},
	)

	runXbpkg := func(expectSuccess bool, arguments ...string) string {
		t.Helper()
		commandArguments := append([]string{"--root", root}, arguments...)
		output, err := exec.Command(
			"bash", append([]string{manager}, commandArguments...)...,
		).CombinedOutput()
		if expectSuccess && err != nil {
			t.Fatalf("xbpkg %v failed: %v\n%s", arguments, err, output)
		}
		if !expectSuccess && err == nil {
			t.Fatalf("xbpkg %v unexpectedly succeeded:\n%s", arguments, output)
		}
		return string(output)
	}

	runXbpkg(true, "install", configV1)
	configPath := filepath.Join(root, "etc/configured.conf")
	if err := os.WriteFile(configPath, []byte("local configuration\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	output := runXbpkg(true, "upgrade", configV2)
	if !strings.Contains(output, "preserved modified configuration /etc/configured.conf") {
		t.Fatalf("upgrade did not report the preserved configuration: %s", output)
	}
	if content, err := os.ReadFile(configPath); err != nil {
		t.Fatal(err)
	} else if string(content) != "local configuration\n" {
		t.Fatalf("upgrade replaced the local configuration: %q", content)
	}
	newConfigPath := configPath + ".xbpkg-new"
	if content, err := os.ReadFile(newConfigPath); err != nil {
		t.Fatal(err)
	} else if string(content) != "configured 2.0.0\n" {
		t.Fatalf("unexpected maintainer configuration: %q", content)
	}
	output = runXbpkg(true, "verify", "configured")
	if !strings.Contains(output, "modified configuration /etc/configured.conf") {
		t.Fatalf("verify did not report the local configuration: %s", output)
	}

	output = runXbpkg(false, "upgrade", configV3)
	if !strings.Contains(output, "pending configuration update") {
		t.Fatalf("upgrade ignored the pending configuration: %s", output)
	}
	if !strings.Contains(runXbpkg(true, "list"), "configured 2.0.0") {
		t.Fatal("rejected configuration upgrade changed the installed version")
	}

	output = runXbpkg(true, "remove", "configured")
	if !strings.Contains(output, "preserved modified configuration /etc/configured.conf") {
		t.Fatalf("remove did not report the preserved configuration: %s", output)
	}
	if content, err := os.ReadFile(configPath); err != nil {
		t.Fatal(err)
	} else if string(content) != "local configuration\n" {
		t.Fatalf("remove deleted the local configuration: %q", content)
	}

	runXbpkg(true, "install", pristineV1)
	runXbpkg(true, "upgrade", pristineV2)
	pristinePath := filepath.Join(root, "etc/pristine.conf")
	if content, err := os.ReadFile(pristinePath); err != nil {
		t.Fatal(err)
	} else if string(content) != "pristine 2.0.0\n" {
		t.Fatalf("pristine configuration was not upgraded: %q", content)
	}
	if _, err := os.Stat(pristinePath + ".xbpkg-new"); !os.IsNotExist(err) {
		t.Fatal("pristine configuration unexpectedly produced .xbpkg-new")
	}
	runXbpkg(true, "verify", "pristine")
}

func TestXbpkgResolvesRepositoryDependencies(t *testing.T) {
	manager, err := filepath.Abs("native/package-manager/resources/xbpkg")
	if err != nil {
		t.Fatal(err)
	}
	base := buildTestPackage(t, "base", "", "usr/lib/libbase.so")
	middle := buildTestPackage(t, "middle", "base", "usr/lib/libmiddle.so")
	application := buildTestPackage(
		t, "application", "middle, base", "usr/bin/application",
	)
	repository := buildTestRepository(t, base, middle, application)
	root := filepath.Join(t.TempDir(), "root")

	runXbpkg := func(expectSuccess bool, targetRoot string, arguments ...string) string {
		t.Helper()
		commandArguments := []string{
			"--root", targetRoot,
			"--repository", repository,
			"--trusted-key", filepath.Join(repository, "trusted-key.pem"),
		}
		commandArguments = append(commandArguments, arguments...)
		output, err := exec.Command(
			"bash", append([]string{manager}, commandArguments...)...,
		).CombinedOutput()
		if expectSuccess && err != nil {
			t.Fatalf("xbpkg %v failed: %v\n%s", arguments, err, output)
		}
		if !expectSuccess && err == nil {
			t.Fatalf("xbpkg %v unexpectedly succeeded:\n%s", arguments, output)
		}
		return string(output)
	}

	output := runXbpkg(
		true, root, "--dry-run", "install", "application",
	)
	expectedPlan := "Plan:\n" +
		"  install base 1.0.0\n" +
		"  install middle 1.0.0\n" +
		"  install application 1.0.0\n"
	if output != expectedPlan {
		t.Fatalf("unexpected repository plan:\n%s", output)
	}
	if _, err := os.Stat(filepath.Join(root, "var/lib/xbpkg")); !os.IsNotExist(err) {
		t.Fatal("dry-run modified the package database")
	}
	if _, err := os.Stat(filepath.Join(root, "usr/lib/libbase.so")); !os.IsNotExist(err) {
		t.Fatal("dry-run copied package payload")
	}

	output = runXbpkg(true, root, "install", "application")
	basePosition := strings.Index(output, "installed base")
	middlePosition := strings.Index(output, "installed middle")
	applicationPosition := strings.Index(output, "installed application")
	if basePosition < 0 || middlePosition < basePosition ||
		applicationPosition < middlePosition {
		t.Fatalf("dependencies were not installed in order:\n%s", output)
	}
	if list := runXbpkg(true, root, "list"); len(strings.Fields(list)) != 6 {
		t.Fatalf("unexpected resolved package list:\n%s", list)
	}
	if output := runXbpkg(true, root, "install", "application"); output != "Plan:\n  nothing to do\n" {
		t.Fatalf("unexpected reinstall plan: %s", output)
	}

	collisionRoot := filepath.Join(t.TempDir(), "root")
	if err := os.MkdirAll(filepath.Join(collisionRoot, "usr/bin"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(
		filepath.Join(collisionRoot, "usr/bin/application"),
		[]byte("unmanaged\n"),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	output = runXbpkg(false, collisionRoot, "install", "application")
	if !strings.Contains(output, "file collision: /usr/bin/application") {
		t.Fatalf("unexpected planned collision error: %s", output)
	}
	if _, err := os.Stat(
		filepath.Join(collisionRoot, "usr/lib/libbase.so"),
	); !os.IsNotExist(err) {
		t.Fatal("preflight collision left a dependency payload behind")
	}
	if _, err := os.Stat(
		filepath.Join(collisionRoot, "var/lib/xbpkg/installed/base"),
	); !os.IsNotExist(err) {
		t.Fatal("preflight collision registered a dependency")
	}

	missing := buildTestPackage(
		t, "missing-user", "absent", "usr/bin/missing-user",
	)
	missingRepository := buildTestRepository(t, missing)
	repository = missingRepository
	output = runXbpkg(false, filepath.Join(t.TempDir(), "root"), "install", "missing-user")
	if !strings.Contains(output, "dependency not found in repository: absent") {
		t.Fatalf("unexpected missing dependency error: %s", output)
	}

	cycleA := buildTestPackage(t, "cycle-a", "cycle-b", "usr/lib/cycle-a")
	cycleB := buildTestPackage(t, "cycle-b", "cycle-a", "usr/lib/cycle-b")
	repository = buildTestRepository(t, cycleA, cycleB)
	output = runXbpkg(false, filepath.Join(t.TempDir(), "root"), "install", "cycle-a")
	if !strings.Contains(output, "dependency cycle detected at cycle-a") {
		t.Fatalf("unexpected dependency cycle error: %s", output)
	}

	tampered := buildTestPackage(t, "tampered", "", "usr/bin/tampered")
	repository = buildTestRepository(t, tampered)
	tamperedTarget := filepath.Join(
		repository, "packages", filepath.Base(tampered),
	)
	file, err := os.OpenFile(tamperedTarget, os.O_WRONLY|os.O_APPEND, 0)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := file.WriteString("tampered\n"); err != nil {
		file.Close()
		t.Fatal(err)
	}
	if err := file.Close(); err != nil {
		t.Fatal(err)
	}
	output = runXbpkg(false, filepath.Join(t.TempDir(), "root"), "install", "tampered")
	if !strings.Contains(output, "repository checksum mismatch") {
		t.Fatalf("unexpected repository checksum error: %s", output)
	}

	unsigned := buildTestPackage(t, "unsigned", "", "usr/bin/unsigned")
	repository = buildTestRepository(t, unsigned)
	if err := os.Remove(filepath.Join(repository, "SHA256SUMS.sig")); err != nil {
		t.Fatal(err)
	}
	output = runXbpkg(
		false, filepath.Join(t.TempDir(), "root"),
		"--dry-run", "install", "unsigned",
	)
	if !strings.Contains(output, "unsigned repository") {
		t.Fatalf("unexpected unsigned repository error: %s", output)
	}
	commandArguments := []string{
		manager,
		"--root", filepath.Join(t.TempDir(), "root"),
		"--repository", repository,
		"--allow-unsigned", "--dry-run", "install", "unsigned",
	}
	if outputBytes, err := exec.Command("bash", commandArguments...).CombinedOutput(); err != nil {
		t.Fatalf("explicit unsigned repository failed: %v\n%s", err, outputBytes)
	}

	signed := buildTestPackage(t, "signed", "", "usr/bin/signed")
	repository = buildTestRepository(t, signed)
	signaturePath := filepath.Join(repository, "SHA256SUMS.sig")
	signature, err := os.ReadFile(signaturePath)
	if err != nil {
		t.Fatal(err)
	}
	signature[0] ^= 0xff
	if err := os.WriteFile(signaturePath, signature, 0o644); err != nil {
		t.Fatal(err)
	}
	output = runXbpkg(
		false, filepath.Join(t.TempDir(), "root"),
		"--dry-run", "install", "signed",
	)
	if !strings.Contains(output, "repository signature verification failed") {
		t.Fatalf("unexpected invalid signature error: %s", output)
	}
}

func TestXbpkgDiscoversAndRefreshesConfiguredHTTPRepository(t *testing.T) {
	manager, err := filepath.Abs("native/package-manager/resources/xbpkg")
	if err != nil {
		t.Fatal(err)
	}
	archive := buildTestPackage(t, "application", "", "usr/bin/application")
	repository := buildTestRepository(t, archive)
	server := httptest.NewServer(http.FileServer(http.Dir(repository)))
	defer server.Close()
	if _, err := exec.LookPath("wget"); err == nil {
		t.Setenv("XBPKG_DOWNLOADER", "wget")
	}

	root := filepath.Join(t.TempDir(), "root")
	configDirectory := filepath.Join(root, "etc/xbpkg/repositories.d")
	if err := os.MkdirAll(configDirectory, 0o755); err != nil {
		t.Fatal(err)
	}
	config := fmt.Sprintf(
		"schema-version: 1\nname: test\nlocation: %q\n"+
			"enabled: true\nkey: %q\n",
		server.URL, filepath.Join(repository, "trusted-key.pem"),
	)
	if err := os.WriteFile(
		filepath.Join(configDirectory, "test.conf"), []byte(config), 0o644,
	); err != nil {
		t.Fatal(err)
	}
	run := func(arguments ...string) string {
		t.Helper()
		commandArguments := append([]string{"--root", root}, arguments...)
		output, err := exec.Command(
			"bash", append([]string{manager}, commandArguments...)...,
		).CombinedOutput()
		if err != nil {
			t.Fatalf("xbpkg %v failed: %v\n%s", arguments, err, output)
		}
		return string(output)
	}
	if output := run("refresh"); !strings.Contains(
		output, "refreshed repository test",
	) {
		t.Fatalf("unexpected refresh output: %s", output)
	}
	run("install", "application")
	if _, err := os.Stat(filepath.Join(root, "usr/bin/application")); err != nil {
		t.Fatal("configured repository package was not installed")
	}
}

func TestXbpkgEnforcesVersionedDependencies(t *testing.T) {
	manager, err := filepath.Abs("native/package-manager/resources/xbpkg")
	if err != nil {
		t.Fatal(err)
	}

	directRoot := filepath.Join(t.TempDir(), "root")
	baseV1 := buildTestPackageVersion(
		t, "versioned-base", "1.0.0", "", "usr/lib/versioned-base",
	)
	baseV2 := buildTestPackageVersion(
		t, "versioned-base", "2.0.0", "", "usr/lib/versioned-base",
	)
	consumer := buildTestPackage(
		t, "versioned-consumer", "versioned-base >= 2.0.0",
		"usr/bin/versioned-consumer",
	)
	runDirect := func(expectSuccess bool, arguments ...string) string {
		t.Helper()
		commandArguments := append([]string{"--root", directRoot}, arguments...)
		output, err := exec.Command(
			"bash", append([]string{manager}, commandArguments...)...,
		).CombinedOutput()
		if expectSuccess && err != nil {
			t.Fatalf("xbpkg %v failed: %v\n%s", arguments, err, output)
		}
		if !expectSuccess && err == nil {
			t.Fatalf("xbpkg %v unexpectedly succeeded:\n%s", arguments, output)
		}
		return string(output)
	}
	runDirect(true, "install", baseV1)
	output := runDirect(false, "install", consumer)
	if !strings.Contains(output, "dependency version mismatch") {
		t.Fatalf("direct version constraint was not enforced:\n%s", output)
	}
	runDirect(true, "upgrade", baseV2)
	runDirect(true, "install", consumer)
	runDirect(true, "check")
	output = runDirect(false, "upgrade", baseV1)
	if !strings.Contains(output, "would violate dependency for versioned-consumer") {
		t.Fatalf("incompatible dependency downgrade was not rejected:\n%s", output)
	}

	sharedV1 := buildTestPackageVersion(
		t, "shared-version", "1.0.0", "", "usr/lib/shared-version",
	)
	sharedV2 := buildTestPackageVersion(
		t, "shared-version", "2.0.0", "", "usr/lib/shared-version",
	)
	sharedV3 := buildTestPackageVersion(
		t, "shared-version", "3.0.0", "", "usr/lib/shared-version",
	)
	application := buildTestPackage(
		t, "bounded-application", "shared-version < 3.0.0",
		"usr/bin/bounded-application",
	)
	repository := buildTestRepository(
		t, sharedV1, sharedV2, sharedV3, application,
	)
	resolvedRoot := filepath.Join(t.TempDir(), "root")
	commandArguments := []string{
		manager,
		"--root", resolvedRoot,
		"--repository", repository,
		"--trusted-key", filepath.Join(repository, "trusted-key.pem"),
		"--dry-run", "install", "bounded-application",
	}
	outputBytes, err := exec.Command("bash", commandArguments...).CombinedOutput()
	if err != nil {
		t.Fatalf("bounded resolution failed: %v\n%s", err, outputBytes)
	}
	output = string(outputBytes)
	if !strings.Contains(output, "install shared-version 2.0.0") ||
		strings.Contains(output, "install shared-version 3.0.0") {
		t.Fatalf("resolver did not select the newest admissible version:\n%s", output)
	}

	conflictA := buildTestPackage(
		t, "conflict-a", "shared-version >= 3.0.0", "usr/lib/conflict-a",
	)
	conflictB := buildTestPackage(
		t, "conflict-b", "shared-version < 3.0.0", "usr/lib/conflict-b",
	)
	conflicted := buildTestPackage(
		t, "conflicted", "conflict-a, conflict-b", "usr/bin/conflicted",
	)
	repository = buildTestRepository(
		t, sharedV1, sharedV2, sharedV3, conflictA, conflictB, conflicted,
	)
	conflictRoot := filepath.Join(t.TempDir(), "root")
	outputBytes, err = exec.Command(
		"bash", manager,
		"--root", conflictRoot,
		"--repository", repository,
		"--trusted-key", filepath.Join(repository, "trusted-key.pem"),
		"install", "conflicted",
	).CombinedOutput()
	if err == nil || !strings.Contains(
		string(outputBytes), "incompatible dependency constraints",
	) {
		t.Fatalf("transitive version conflict was not detected:\n%s", outputBytes)
	}
	if _, err := os.Stat(
		filepath.Join(conflictRoot, "usr/lib/shared-version"),
	); !os.IsNotExist(err) {
		t.Fatal("version conflict copied a dependency before failing")
	}
}

func TestXbpkgRotatesAndRevokesRepositoryKeys(t *testing.T) {
	manager, err := filepath.Abs("native/package-manager/resources/xbpkg")
	if err != nil {
		t.Fatal(err)
	}
	archive := buildTestPackage(t, "rotation", "", "usr/bin/rotation")
	oldRepository := buildTestRepository(t, archive)
	newRepository := buildTestRepository(t, archive)
	keyring := filepath.Join(t.TempDir(), "trusted-keys")
	if err := os.Mkdir(keyring, 0o755); err != nil {
		t.Fatal(err)
	}
	for name, repository := range map[string]string{
		"old.pem": oldRepository,
		"new.pem": newRepository,
	} {
		content, err := os.ReadFile(filepath.Join(repository, "trusted-key.pem"))
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(keyring, name), content, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	runRepository := func(
		expectSuccess bool, repository string, extraArguments ...string,
	) string {
		t.Helper()
		arguments := []string{
			manager,
			"--root", filepath.Join(t.TempDir(), "root"),
			"--repository", repository,
			"--trusted-keyring", keyring,
		}
		arguments = append(arguments, extraArguments...)
		arguments = append(arguments, "--dry-run", "install", "rotation")
		output, err := exec.Command("bash", arguments...).CombinedOutput()
		if expectSuccess && err != nil {
			t.Fatalf("repository rotation failed: %v\n%s", err, output)
		}
		if !expectSuccess && err == nil {
			t.Fatalf("revoked repository unexpectedly succeeded:\n%s", output)
		}
		return string(output)
	}
	runRepository(true, oldRepository)
	runRepository(true, newRepository)

	oldKeyID, err := os.ReadFile(filepath.Join(oldRepository, "SHA256SUMS.keyid"))
	if err != nil {
		t.Fatal(err)
	}
	revocations := filepath.Join(t.TempDir(), "revoked-keys")
	if err := os.WriteFile(revocations, oldKeyID, 0o644); err != nil {
		t.Fatal(err)
	}
	output := runRepository(
		false, oldRepository, "--revoked-keys", revocations,
	)
	if !strings.Contains(output, "repository signing key is revoked") {
		t.Fatalf("unexpected revoked key error: %s", output)
	}
	runRepository(true, newRepository, "--revoked-keys", revocations)
	if err := os.Remove(filepath.Join(keyring, "old.pem")); err != nil {
		t.Fatal(err)
	}
	runRepository(true, newRepository, "--revoked-keys", revocations)
}

func TestXbpkgRejectsRepositoryDowngrades(t *testing.T) {
	manager, err := filepath.Abs("native/package-manager/resources/xbpkg")
	if err != nil {
		t.Fatal(err)
	}
	archive := buildTestPackage(t, "monotonic", "", "usr/bin/monotonic")
	repository := buildTestRepository(t, archive)
	root := filepath.Join(t.TempDir(), "root")
	runRepository := func(expectSuccess bool, extraArguments ...string) string {
		t.Helper()
		arguments := []string{
			manager,
			"--root", root,
			"--repository", repository,
			"--trusted-key", filepath.Join(repository, "trusted-key.pem"),
		}
		arguments = append(arguments, extraArguments...)
		arguments = append(arguments, "install", "monotonic")
		output, err := exec.Command("bash", arguments...).CombinedOutput()
		if expectSuccess && err != nil {
			t.Fatalf("repository release command failed: %v\n%s", err, output)
		}
		if !expectSuccess && err == nil {
			t.Fatalf("repository release unexpectedly succeeded:\n%s", output)
		}
		return string(output)
	}

	setTestRepositoryRelease(t, repository, 2, "2.0.0")
	runRepository(true)
	setTestRepositoryRelease(t, repository, 1, "1.0.0")
	output := runRepository(false, "--dry-run")
	if !strings.Contains(output, "repository downgrade refused") {
		t.Fatalf("downgrade was not rejected: %s", output)
	}
	runRepository(true, "--allow-downgrade", "--dry-run")

	setTestRepositoryRelease(t, repository, 2, "2.0.0-reused")
	output = runRepository(false, "--dry-run")
	if !strings.Contains(output, "serial 2 was reused with different content") {
		t.Fatalf("serial reuse was not rejected: %s", output)
	}
	setTestRepositoryRelease(t, repository, 3, "3.0.0")
	runRepository(true)
	state, err := os.ReadFile(
		filepath.Join(root, "var/lib/xbpkg/repositories/test"),
	)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(state), "serial: 3") {
		t.Fatalf("new repository serial was not persisted: %s", state)
	}

	setTestRepositoryReleaseDates(
		t, repository, 4, "4.0.0-expired",
		time.Now().UTC().Add(-48*time.Hour),
		time.Now().UTC().Add(-24*time.Hour),
	)
	output = runRepository(false, "--dry-run")
	if !strings.Contains(output, "repository metadata expired") {
		t.Fatalf("expired repository was not rejected: %s", output)
	}
	runRepository(true, "--ignore-expiration", "--dry-run")
	setTestRepositoryReleaseDates(
		t, repository, 4, "4.0.0-future",
		time.Now().UTC().Add(48*time.Hour),
		time.Now().UTC().Add(72*time.Hour),
	)
	output = runRepository(false, "--dry-run")
	if !strings.Contains(output, "publication date is in the future") {
		t.Fatalf("future repository was not rejected: %s", output)
	}
	runRepository(true, "--ignore-expiration", "--dry-run")
}

func setTestRepositoryRelease(
	t *testing.T, repository string, serial int, version string,
) {
	t.Helper()
	setTestRepositoryReleaseDates(
		t, repository, serial, version,
		time.Now().UTC().Add(-time.Hour),
		time.Now().UTC().Add(24*time.Hour),
	)
}

func setTestRepositoryReleaseDates(
	t *testing.T,
	repository string,
	serial int,
	version string,
	publishedAt time.Time,
	expiresAt time.Time,
) {
	t.Helper()
	release := fmt.Sprintf(
		"schema-version: 1\nrepository: test\nserial: %d\nversion: %q\n"+
			"published-at: %q\nexpires-at: %q\n",
		serial, version,
		publishedAt.UTC().Format("2006-01-02T15:04:05Z"),
		expiresAt.UTC().Format("2006-01-02T15:04:05Z"),
	)
	if err := os.WriteFile(
		filepath.Join(repository, "RELEASE"), []byte(release), 0o644,
	); err != nil {
		t.Fatal(err)
	}
	checksumPath := filepath.Join(repository, "SHA256SUMS")
	content, err := os.ReadFile(checksumPath)
	if err != nil {
		t.Fatal(err)
	}
	var checksums strings.Builder
	for _, line := range strings.Split(strings.TrimSpace(string(content)), "\n") {
		fields := strings.Fields(line)
		if len(fields) != 2 {
			t.Fatalf("invalid test checksum line: %q", line)
		}
		payload, err := os.ReadFile(filepath.Join(repository, fields[1]))
		if err != nil {
			t.Fatal(err)
		}
		fmt.Fprintf(&checksums, "%x  %s\n", sha256.Sum256(payload), fields[1])
	}
	if err := os.WriteFile(checksumPath, []byte(checksums.String()), 0o644); err != nil {
		t.Fatal(err)
	}
	command := exec.Command(
		"openssl", "pkeyutl", "-sign",
		"-inkey", filepath.Join(repository, "signing-key.pem"),
		"-rawin", "-in", checksumPath,
		"-out", filepath.Join(repository, "SHA256SUMS.sig"),
	)
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("resigning test repository failed: %v\n%s", err, output)
	}
}

func buildTestRepository(t *testing.T, archives ...string) string {
	t.Helper()
	repository := t.TempDir()
	packages := filepath.Join(repository, "packages")
	if err := os.Mkdir(packages, 0o755); err != nil {
		t.Fatal(err)
	}
	var checksums strings.Builder
	for _, archive := range archives {
		name := filepath.Base(archive)
		target := filepath.Join(packages, name)
		content, err := os.ReadFile(archive)
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(target, content, 0o644); err != nil {
			t.Fatal(err)
		}
		fmt.Fprintf(
			&checksums,
			"%x  packages/%s\n",
			sha256.Sum256(content),
			name,
		)
	}
	for filename, content := range map[string]string{
		"index.yaml": "schema-version: 1\nrepository: test\n",
		"RELEASE": fmt.Sprintf(
			"schema-version: 1\nrepository: test\nserial: 1\n"+
				"version: \"1.0.0\"\npublished-at: %q\nexpires-at: %q\n",
			time.Now().UTC().Add(-time.Hour).Format("2006-01-02T15:04:05Z"),
			time.Now().UTC().Add(24*time.Hour).Format("2006-01-02T15:04:05Z"),
		),
	} {
		if err := os.WriteFile(
			filepath.Join(repository, filename), []byte(content), 0o644,
		); err != nil {
			t.Fatal(err)
		}
		fmt.Fprintf(
			&checksums, "%x  %s\n",
			sha256.Sum256([]byte(content)), filename,
		)
	}
	if err := os.WriteFile(
		filepath.Join(repository, "SHA256SUMS"),
		[]byte(checksums.String()),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	privateKey := filepath.Join(repository, "signing-key.pem")
	publicKey := filepath.Join(repository, "trusted-key.pem")
	for _, command := range [][]string{
		{"genpkey", "-algorithm", "Ed25519", "-out", privateKey},
		{"pkey", "-in", privateKey, "-pubout", "-out", publicKey},
		{
			"pkeyutl", "-sign", "-inkey", privateKey, "-rawin",
			"-in", filepath.Join(repository, "SHA256SUMS"),
			"-out", filepath.Join(repository, "SHA256SUMS.sig"),
		},
	} {
		if output, err := exec.Command("openssl", command...).CombinedOutput(); err != nil {
			t.Fatalf("signing test repository failed: %v\n%s", err, output)
		}
	}
	publicDER, err := exec.Command(
		"openssl", "pkey", "-pubin", "-in", publicKey, "-outform", "DER",
	).Output()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(
		filepath.Join(repository, "SHA256SUMS.keyid"),
		[]byte(fmt.Sprintf("%x\n", sha256.Sum256(publicDER))),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	return repository
}

func buildTestPackage(t *testing.T, name, dependencies, payloadPath string) string {
	t.Helper()
	return buildTestPackageVersion(
		t, name, "1.0.0", dependencies, payloadPath,
	)
}

func buildTestPackageVersion(
	t *testing.T,
	name string,
	version string,
	dependencies string,
	payloadPath string,
) string {
	t.Helper()
	return buildTestPackageVersionWithConffiles(
		t, name, version, dependencies, payloadPath, nil,
	)
}

func buildTestPackageVersionWithConffiles(
	t *testing.T,
	name string,
	version string,
	dependencies string,
	payloadPath string,
	conffiles []string,
) string {
	t.Helper()
	packageRoot := filepath.Join(t.TempDir(), name)
	metadata := filepath.Join(packageRoot, ".XBPKG")
	rootfs := filepath.Join(packageRoot, "rootfs")
	payload := filepath.Join(rootfs, payloadPath)
	if err := os.MkdirAll(filepath.Dir(payload), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(metadata, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(
		payload,
		[]byte(name+" "+version+"\n"),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	manifest := fmt.Sprintf(`schema-version: 1
name: "%s"
version: "%s"
architecture: x86_64
dependencies: "%s"
payload: rootfs
files: .XBPKG/files
checksums: .XBPKG/files.sha256
conffiles: .XBPKG/conffiles
`, name, version, dependencies)
	if err := os.WriteFile(
		filepath.Join(metadata, "manifest.yaml"),
		[]byte(manifest),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(
		filepath.Join(metadata, "files"),
		[]byte("/"+payloadPath+"\n"),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	conffileContent := ""
	if len(conffiles) > 0 {
		conffileContent = strings.Join(conffiles, "\n") + "\n"
	}
	if err := os.WriteFile(
		filepath.Join(metadata, "conffiles"),
		[]byte(conffileContent),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	checksum := fmt.Sprintf("%x", sha256File(t, payload))
	if err := os.WriteFile(
		filepath.Join(metadata, "files.sha256"),
		[]byte(checksum+"  ./"+payloadPath+"\n"),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	archive := filepath.Join(
		t.TempDir(),
		name+"-"+version+"-x86_64.xbpkg.tar.zst",
	)
	command := exec.Command(
		"tar", "--zstd", "-C", packageRoot, "-cf", archive, ".XBPKG", "rootfs",
	)
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("creating test package failed: %v\n%s", err, output)
	}
	return archive
}

func sha256File(t *testing.T, path string) [32]byte {
	t.Helper()
	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return sha256.Sum256(content)
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
