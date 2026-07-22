# Agent guidance

## Installer, shell, and terminal changes

- Preserve shell data-flow semantics. Do not suppress or replace stdin in a way that rewrites or steals input from a pipeline; shell precedence is part of the installer contract.
- Keep interactive and non-interactive execution explicit. A piped launcher may use the controlling terminal for prompts only when one exists. Fully headless usage must fail clearly or select an explicit non-interactive mode.
- Changes involving bootstrap, command execution, TTY/stdin handling, or installer ordering require a regression test covering the affected boundary. Include pipeline input, shell redirection, terminal fallback, and platform-specific process-launcher cases as applicable.
- For those changes, build the CLI and reproduce the reported invocation against the compiled binary in a pseudo-terminal. From a fixture directory containing `dot.toml`, use the host's PTY tool; on Linux, for example:

```bash
script -qec 'printf "mise\n" | ./dist/dot' /dev/null
printf "mise\n" | ./dist/dot
./dist/dot </dev/null
```

Assert that the first form permits prompt interaction and preserves the selected command's pipeline input, the second follows the piped-launcher behavior, and the final headless form fails clearly or uses an explicit non-interactive mode.

## Verification

Run the focused tests and compiled build:

```bash
bun test tests/installer.test.ts tests/integration.test.ts tests/terminal.test.ts
make build
```

When a change touches platform-specific launching, run `make build-all` when the required targets are available. Cross-platform targets that cannot run on the current host are compile-only; state that honestly in the change summary and still run the focused runtime checks locally.

Use the existing README for normal CLI usage and `Makefile` targets rather than duplicating project behavior here.
