# XBee LFS system pack

This system pack uses the generic LFS 13.0 cloud root filesystem as an OCI
execution environment for XBee.

Reference it from another pack:

```yaml
require: ../lfs-system
```

Or select it explicitly from the CLI:

```bash
xbee --system ../lfs-system enter
```

The default execution user is `root`, the `xbee` administrator is available,
and the working directory is `/workspace`. The image also includes the
prototype `xbpkg` package manager:

```bash
xbpkg list
```
