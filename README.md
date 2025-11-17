# shot

This is a rewrite of [try](https://github.com/tobi/try) and is almost completely compatible with try.

The only differences between try and shot are that the setup for shot is simpler, but has to be done manually (for now), and shot is missing `clone` and `new` as commands which I'll probably be adding in a bit.

Can't guarantee that shot will work on Windows, but it does work on Linux and macOS.

## Usage

```sh
shot [SEARCH_TERM] [--path PATH]
```

Just like in try, the default tries directory is `~/src/tries`, but it can be overwritten with the `--path` flag or the `TRY_PATH` environment variable.

Also check out the `--help` flag.

## Installation

Requirements:
- Having Zig 0.15.2 installed

### 1. Clone the repository

```sh
git clone https://github.com/gabrielmfern/shot
```

### 2. Install `shot-tui` into `/usr/local/bin`

This installs the TUI for shot, but doesn't let you use the `shot` command quite yet.

```sh
sudo zig build install --prefix /usr/local --release=fast
```

If you try to use `shot-tui` directly, it won't change your cwd to the directory you select.

### 3. Configure your shell

<details>
    <summary>bash | zsh</summary>

```sh
shot() {
  local cmd
  cmd="$(/usr/local/bin/shot-tui "$@" 2>/dev/tty)"
  eval "$cmd"
}
```
</details>
<details>
    <summary>fish</summary>

```fish
function shot 
  set -l cmd (/usr/local/bin/shot-tui $argv 2>/dev/tty | string collect)
  eval "$cmd"
end
```
</details>
