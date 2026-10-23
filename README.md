# hollywood-sh

A Bash terminal spectacle inspired by [Hollywood](https://github.com/dustinkirkland/hollywood). It uses tmux to create a changing grid of independently running panes, with each pane showing real local system data or output from a Linux utility.

**IMPORTANT**: This script may display sensitive information. Consider to not record this on video or run the original utility on a container instead. This script was made because I can't really be bothered to pull a whole docker image just to do something silly in front of my friends.

## Requirements

- Bash
- tmux
- Common Linux command-line tools such as `find`, `shuf`, `watch`, `stat`, and `nice`

Optional tools add their own panels or richer output: `bmon`, `htop`, `atop`, `cmatrix`, `tree`, `bat`/`batcat`, `hexdump`, `journalctl`, `iostat`, and `systemctl`. When an optional tool is unavailable, its pane uses another live local source where possible.

## Run

```bash
./hollywood.sh
```

The standalone launch creates one tmux window in a `hollywood` session. If started from an existing tmux session, it opens one `hollywood` window there. Press **Ctrl-C in any pane** to stop the display. Pane workers run at low CPU scheduling priority with `nice -n 19`.

Options:

```bash
./hollywood.sh --splits 8       # pane count: 1–16 (default: 6)
./hollywood.sh --delay 20       # rebuild interval in seconds (default: 10)
./hollywood.sh --help
```

## Pane sources

- Process activity: `htop` or `top`
- Kernel and system logs: `journalctl`, `dmesg`, or readable files under `/var/log`
- Hex dumps of installed executables and source files found under `/usr` and `/opt`
- Network counters from `/proc/net/dev` and live graphs from `bmon`
- Local SSH public-key fingerprints, route tables, and socket listings
- Disk I/O, running services, and process data
- `cmatrix`, `atop`, and a depth-limited view of `/`
- Random section 1 man pages and metadata for paths under `/sys` and `/dev`

The script does not generate fake log entries, network scans, or transfer rates. Some panels are visual tools, such as `cmatrix`; the rest display local system information.

## Shell alias

To run it as `hollywood`, add an alias with the path to your checkout:

```zsh
alias hollywood='/path/to/hollywood-sh/hollywood.sh'
```
