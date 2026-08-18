# burn-dapla-deploy

Roswell/Consfigurator deploy of the service at `burn.dapla.net`.

## Repository Layout

```
burn-dapla-deploy.ros   Thin Roswell entry point
burn-dapla-deploy.asd   Umbrella ASDF system definition
qlfile         Qlot dependency pins
src/deploy.lisp  Consfigurator properties and DEFHOST
src/docs.lisp    40ants-doc sections
t/e2e.lisp       Post-deploy FiveAM smoke tests
docs.ros         Documentation generator
Makefile         build / test / doc / dist / clean
```

## Installation

```sh
ros install qlot
qlot install
./burn-dapla-deploy.ros
```

## Runbook

```sh
machinectl shell burn@ -- systemctl --user status
machinectl shell burn@ -- journalctl --user -f
machinectl shell burn@ -- podman auto-update
```

Redeploy by re-running `./burn-dapla-deploy.ros`. Idempotent.

## Playbook

### ZFS replication (rsync.net)

```sh
zfs snapshot storage/containers/burn@$(date +%Y%m%d)
zfs send -w storage/containers/burn@$(date +%Y%m%d) | \
  ssh user@rsync.net zfs receive backup/burn
```

Key files under `/etc/zfs-keys/` must be backed up separately.

## Decommission

```sh
machinectl shell burn@ -- systemctl --user stop burn
machinectl shell burn@ -- systemctl --user disable burn
zfs destroy -r storage/users/burn
zfs destroy -r storage/containers/burn
```

## License

BSD 3-Clause. See [LICENSE](LICENSE).
