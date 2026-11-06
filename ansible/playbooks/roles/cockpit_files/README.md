# cockpit_files

Owns the file-server package layer and NFS exports on the two hosts that run
the 45Drives Cockpit add-ons: **`backup`** (LXC 101, 10.0.4.8) and **`docker`**
(VM 100, 10.0.4.10).

**Neither host is fully rebuildable from git.** On `backup` the host-side NTFS
mount is outside this repo; on `docker` the Samba shares live in an unmanageable
registry database. See "Outstanding" below.

## Why this exists

Both hosts were hand-built: a community script created the container, the
45Drives Cockpit add-ons were `dpkg -i`'d from downloaded `.deb` files, and the
exports were configured through the Cockpit web UI rather than in git.

`backup` matters more than its size suggests — it is the **single point of
failure for every backup in the cluster**. Five PersistentVolumes (`immich`,
`nextcloud`, `music-assistant`, `unifi`, `backrest`) share its one `/mnt/backup`
export with no `subPath`, so if that guest goes, all backups fail at once. See
AGENTS.md #1.

## The two hosts differ in every variable

Per-host values live in `vars/<hostname>.yml`, **not** in `defaults/`.
`tasks/main.yml` is host-agnostic and `defaults/` holds only shared fallbacks.
Each playbook names its own file via `cockpit_files_vars_file` and the role
loads it with `include_vars`. It is deliberately **not** a `host_vars/`
directory: `ansible.sh` invokes Ansible with `-i "$IP,"`, so
`inventory_hostname` is a bare IP (`10.0.4.8`, `10.0.4.10`) and never the
hostname. Ansible only auto-loads `host_vars/` that sits beside the playbook,
so a role-local one would never be found -- and an implicit lookup keyed on an
IP is the wrong key regardless.
Do not copy one host's values to another:

| | `backup` | `docker` |
|---|---|---|
| Type | LXC 101, unprivileged=false | VM 100 |
| OS | Debian 12 bookworm | Ubuntu 24.04 noble |
| Cockpit | 287.1 | 314 |
| `cockpit-file-sharing` | **4.2.10** | **4.2.12** |
| Data mount | `/mnt/backup`, NTFS, **propagated from `pve2`** | `/mnt/share`, ext4, **own fstab by UUID** |
| Exports | 1 (all five restic repos) | 4 (10 PVs + a photos dir + a read-only music library) |
| Samba shares | none defined | **in use, in the registry** |

The add-on versions are the sharp edge: the 4.2.10 debs would **downgrade**
`docker`'s 4.2.12. There is no `allow_downgrade`, so apt refuses rather than
silently breaking the plugin that owns that host's four exports.

## Scope: what this role owns

- the **package layer** — Cockpit, samba, nfs, and the three 45Drives add-ons
- an **assertion** that the NFS exports still match what each host's `vars` file
  records — see "The exports are asserted, never written" below

It does **not** mount data disks, and it does **not** manage Samba shares. Both
are one-way doors; see below.

Data mounts are only ever **asserted**, never mounted — they are established
outside Ansible on both hosts, in different ways. See the two sections below.

## Data mounts are asserted, never mounted

Both hosts assert their mountpoint is a real mount and fail loudly if it isn't,
because an unmounted data disk means the exports silently resolve to an empty
directory: every restic repo on `backup`, and ten cluster PVs on `docker`.

The check is a `findmnt` call with `check_mode: false`. That flag is load-bearing:
without it Ansible skips every `command` task under `--check`, so the assertion
would silently pass in CI's `check-playbooks` dry run — a green dry run over a
dead disk is exactly the failure the assertion exists to catch. The check
distinguishes `rc=1` ("not a mountpoint") from any other `rc` ("I could not
check", e.g. `findmnt` missing) so a broken check is never reported as a dead
disk. Verified present and behaving on both hosts.

### `docker`: ext4 from its own fstab — already declarative

`/mnt/share` is the 3.6T USB passthrough disk (AGENTS.md #11/#12 — do **not** add
a `disk` block for it in `docker.tf`, that creates a second volume). It is
mounted by the VM itself, from its own fstab:

```
UUID=ab9ee567-fa26-486d-873e-1e5b79033fec /mnt/share auto nosuid,nodev,nofail 0 0
```

So this is declarative already, which is why the role only asserts it. The
`docker` role has its own guard that fails the whole run, because 10 PVs and the
entire `redcloud` workload live on this disk.

### `backup`: NTFS propagated in from pve2

`/mnt/backup` is **not** mounted by the container and **cannot** be. It is an
NTFS filesystem mounted with **`ntfs-3g` on the Proxmox host `pve2`**, and that
mount is **propagated into the LXC's mount namespace**. There is no `mp0`
bind-mount entry and no mount unit to manage.

Three independent pieces of evidence, all from inside the container:

| Evidence | What it shows |
|---|---|
| `/dev` contains **no block devices at all** — `/dev/sda` does not exist | The container cannot reference the disk, let alone mount it. This is the decisive one. |
| `mountinfo` shows `shared:498 master:45` for `/mnt/backup`, while the container root is `shared:497` | The mount was inherited from the host namespace. The `master:` ID only appears on host-propagated mounts. |
| `systemctl cat mnt-backup.mount` → `No files found`, yet `list-units` shows it `loaded active mounted` | systemd synthesised a unit for an inherited mount that has no backing file. The contradiction is the tell. |

Also absent in-container, ruling out the in-container alternatives: no
`/lib/modules` (can't load the `ntfs3` kernel driver), no `/dev/fuse` (can't
use an ntfs-3g FUSE mount), and no `ntfs-3g` binary anywhere on the filesystem.
The fstype is `fuseblk` with `user_id=0`, `group_id=0`, `blksize=4096` — all
ntfs-3g signatures, matching a host-side mount.

The role does not attempt a mount: doing so would either fail or, worse, stack a
second filesystem over the live one.

**Implication for rebuilds:** the host-side `ntfs-3g` mount on `pve2` must exist
*before* the LXC starts, or the container comes up with no `/mnt/backup` and
this role fails. That mount lives on `pve2`, outside this repository and outside
what Terraform here manages, so it is the one piece of `backup` that git
cannot yet reconstruct.

## What it deliberately does NOT own

These are app-managed. Adopting any of them is a one-way door (AGENTS.md #12):

| Path | Why it's left alone |
|---|---|
| `/etc/exports.d/cockpit-file-sharing.exports` | The Cockpit UI generates and rewrites this on both hosts, carrying UI-invented `-fsid=<uuid>` values. **This role never writes any exports file.** It reads this one and fails if it disagrees with `vars/`. `exportfs(5)` reads every `*.exports` in the directory, so a second file alongside would mean two sources of truth and an export removed in the UI would stay exported anyway. |
| `/var/lib/samba/private/registry.tdb` | Samba shares live here because `smb.conf` has `include = registry`. Not templateable without migrating the shares out first. **Unused on `backup` (0 shares defined); in use on `docker`**, which is the main reason `docker` is not rebuildable. |
| `cockpit-identities` user database | Left strictly alone on both hosts. |
| data mounts | Asserted, never mounted — see above. |

## The exports are asserted, never written

`vars/<host>.yml` records the exports each host should have. The role compares
that record against the live UI-generated file and **fails if they differ**, so
drift shows up in CI rather than during an incident.

An earlier version of this role wrote its own
`/etc/exports.d/ansible-file-sharing.exports` next to the UI's. That was wrong.
`exportfs(5)` reads every `*.exports` file in the directory, so both were live at
once and the two silently fought: remove an export in the UI, and the next
`exportfs -ra` re-read the Ansible copy and **re-exported it**. The UI reported
success and the change did nothing.

**The cost of asserting instead of writing:** a rebuilt host comes up with no
exports file, and the role fails until they are recreated in the UI. That is
deliberate. A silent second file is worse than an explicit manual step, because
the manual step is visible and the silent file is not.

Comparison ignores exactly three things — comments, blank lines, `-fsid=<uuid>`
values, and the ordering of options within `(rw,async)`. None of those change
what is actually exported. Paths, client lists, and the option *set* are compared
verbatim, so a real difference still fails:

```
Exported by the UI but not recorded in git:
  /mnt/share/osxphotos 10.0.4.0/24(no_root_squash,no_subtree_check,ro)
Recorded in git but NOT currently exported:
  (none)
```

**`-fsid` is why this works at all.** The UI invents a fresh UUID per export. All
15 NFS PVs mount by `server` + `path`, so nothing in git references an `fsid` and
a rebuilt host generating new ones is invisible to the cluster.

Options differ per host and per path, and that is **reality, not an oversight** —
do not normalise one host against the other:

- `docker` has `no_root_squash` on 3 of 4 exports; `backup` has it on none
- `docker`'s `uptime-kuma-pv` is the only `sync` export
- `docker`'s music library export is `ro`
- `docker`'s `osxphotos` has no PV claiming it — it is consumed outside the cluster

## The vendored debs

The 45Drives add-ons are not in any apt repo on either host. They are vendored in
`files/debs/` (checksum-verified at apply time) so a rebuild needs no network
and no Ubuntu apt source on a Debian host.

Versions are **per host**, in `vars/`, and match what each host runs live:

| Package | `backup` | `docker` |
|---|---|---|
| `cockpit-file-sharing` | 4.2.10-3focal | 4.2.12-1focal |
| `cockpit-identities` | 0.1.12-1focal | 0.1.12-1focal |
| `cockpit-navigator` | 0.5.10-1focal | 0.5.10-1focal |

Adding a host means naming its `vars` file in that host's playbook, adding the
entry **and** vendoring its debs.

There is **no default** for `cockpit_files_addon_debs`. A default is a silent way
to install the wrong version on a host whose `vars/` entry was forgotten, which
would downgrade someone's working plugin. The role asserts each host declares
its own.

There is deliberately **no `allow_downgrade`**: if a host's installed version is
newer than what is vendored, apt refusing is the correct outcome, because it
means the vendored set is stale for that host and a human should look.

### The three-way split, from one `dpkg-query` read

The role reads what the host actually runs (`dpkg-query -W`) and sorts each
add-on into exactly one of three states:

| State | Meaning | What the role does |
|---|---|---|
| not installed | fresh or partially-built host | **installs** the vendored deb |
| installed, == pin | already correct | nothing |
| installed, != pin | a **working** add-on at another version | **fails**, for a human |

The middle case is why the add-on loop is empty on both live hosts today, and
why a green dry run proves the guards but not the install.

Not-installed used to **fail** rather than install. That made the install tasks
unreachable: the role asserted the add-ons existed and then had no way to put
them back, so a genuinely fresh host could never be rebuilt from git. It now
installs, which is the whole point of vendoring the debs.

The drift guard is unchanged and is the one that must never be relaxed —
installing over a working add-on is the failure mode that would break exports
and Samba shares.

### The role refuses to change a working add-on

Each `vars/<hostname>.yml` entry carries an explicit `version` alongside
`file` and `sha256`. Before installing anything the role reads what the host
actually runs (`dpkg-query -W`) and **fails if it differs from the pinned
version**, rather than proceeding. Verified identical on both hosts:

| Add-on | `backup` installed / pinned | `docker` installed / pinned |
|---|---|---|
| `cockpit-file-sharing` | 4.2.10-3focal | 4.2.12-1focal |
| `cockpit-identities` | 0.1.12-1focal | 0.1.12-1focal |
| `cockpit-navigator` | 0.5.10-1focal | 0.5.10-1focal |

Every `Depends` across all four debs (`cockpit-bridge`, `samba`, `sudo`,
`perl`, `rsync`, `zip`, `python3`, and the rest) is already `installed` on both
hosts, so on a real rebuild apt has nothing to pull in beyond the deb itself.

The version is compared against the explicit `version` var, **not** one parsed
out of the `.deb` filename — a filename regex was tried first and silently
never matched, which would have failed every host.

`cockpit_files_addon_debs` has **no default**. A default would be a silent way
to install the wrong version on a host whose `vars/` entry was forgotten, so the
role asserts each host declares its own set.

Source: [45Drives/cockpit-file-sharing](https://github.com/45Drives/cockpit-file-sharing),
[cockpit-identities](https://github.com/45Drives/cockpit-identities),
[cockpit-navigator](https://github.com/45Drives/cockpit-navigator).

## Outstanding: both hosts still have gaps

| Gap | Host | Why it is not fixed here |
|---|---|---|
| Host-side `ntfs-3g` mount on `pve2` | `backup` | Lives on the Proxmox host, outside this repo |
| Samba shares in `registry.tdb` | `docker` | `include = registry`; templating needs migration out of the registry first |
| NFS exports | both | Owned by the Cockpit UI; this role asserts, it does not deploy. A rebuild needs the exports recreated by hand in the UI before the drift check will pass. See "The exports are asserted, never written" above. |

### `backup`: the host-side mount is not in git

Two things would be needed, both on `pve2` and both currently tribal knowledge:

1. the exact `ntfs-3g` mount invocation for the 3.6T disk — **by `/dev/disk/by-id`
   path**, since the live container resolves it as `/dev/sda`, which is positional
   and re-enumerates across reboots
2. whatever makes that mount happen **before** the LXC starts (host fstab, or a
   systemd mount unit on `pve2`), so a recreated container inherits it

`terraform/backup.tf` needs **nothing** for the disk: no `device_passthrough`
block and no mountpoint entry, because the mount propagates in. An earlier
revision of this README claimed otherwise — it was wrong.

### `docker`: the Samba shares are not in git

`docker` is not rebuildable while its Samba shares live in `registry.tdb`. The
correct next step is **assertion** (fail CI when reality and git disagree), not
adoption — see AGENTS.md #12.

The role fails loudly when a data mount is missing, so a rebuild surfaces
immediately rather than quietly exporting an empty directory to five backup PVs
and ten app PVs.

## What CI does and does not prove

`check-playbooks` runs these playbooks with `--check` against the **live**
guests. For the add-on layer that means:

- **Proven:** both data mountpoints are real mounts; every add-on is installed
  at its pinned version; every vendored deb matches its recorded `sha256`; the
  live exports (as the UI has them today) match `vars/` exactly, ignoring
  `-fsid`, comments and option ordering.
- **Not proven:** the install. Both live hosts already run the pinned versions,
  so `cockpit_files_addons_to_install` is empty and the stage/install loop has
  nothing to iterate. The first real exercise will be a genuine rebuild. Also
  not proven: what happens on a genuine rebuild, where the UI's exports file
  does not exist yet — that path is only exercised by the "Fail if ... is
  missing" task actually firing, which it has not, on either host, as of this
  writing.

Two `--check` traps this role has already hit:

- `copy` does not write in check mode, so a following `apt` on the staged path
  fails with a misleading `No package matching ... is available`. The stage and
  install tasks are `when: not ansible_check_mode` for this reason — the message
  points at the package when the real problem is the check.
- A `command` task is skipped entirely under `--check`, so any assertion built
  from one needs `check_mode: false` or it passes silently.

The staging directory is created by the role. `copy` does not create a
destination directory and `/var/cache/cockpit-files-addons` exists on neither
host, so without an explicit `file: state=directory` the first rebuild died with
`Destination directory ... does not exist`.

## Never restart these services

There are no handlers in this role, on purpose. All NFS PVs on both hosts mount
with `hard`, so restarting `nfs-server` turns an export drop into an application
hang across immich, nextcloud, music assistant, unifi, and backrest at once — not
a visible error. `nfs-server` is only ever enabled, never started or restarted.

This role also no longer runs `exportfs -ra`. It used to, as the effect half of
deploying the exports file. Since the exports are asserted rather than written
there is nothing to re-export, and one fewer command running against the
single point of failure for every backup in the cluster.

Native packages use `state: present`, which installs if missing but **never
upgrades**. That is deliberate: the two hosts run different Cockpit majors and
both work, so converging them would mean picking a version for a host that is
currently fine. This role can restore a missing package; it cannot converge a
version.
