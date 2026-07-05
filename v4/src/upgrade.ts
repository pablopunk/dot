import { color } from "./ui";

function getPlatform(): { os: string; arch: string; ext: string } {
  const platform = process.platform;
  const arch = process.arch === "x64" ? "x64" : "arm64";
  let os: string;
  let ext = "";

  if (platform === "darwin") os = "darwin";
  else if (platform === "linux") os = "linux";
  else if (platform === "win32") { os = "windows"; ext = ".exe"; }
  else os = "linux";

  return { os, arch, ext };
}

export async function selfUpgrade(): Promise<void> {
  const { os, arch, ext } = getPlatform();
  const assetName = `dot-${os}-${arch}${ext}`;

  process.stdout.write(`${color("[upgrade]", "blue")} Checking for latest release...\n`);

  const apiResponse = await fetch(
    "https://api.github.com/repos/pablopunk/dot/releases/latest",
    { headers: { "Accept": "application/vnd.github.v3+json", "User-Agent": "dot" } }
  );

  if (!apiResponse.ok) {
    process.stderr.write(`${color("[error]", "red")} Failed to fetch release: ${apiResponse.status}\n`);
    process.exit(1);
  }

  const release = await apiResponse.json();
  const asset = release.assets.find((a: any) => a.name === assetName);

  if (!asset) {
    process.stderr.write(`${color("[error]", "red")} No binary found for ${assetName}\n`);
    process.exit(1);
  }

  const currentPath = process.execPath;
  const tmpPath = currentPath + ".new";

  process.stdout.write(`${color("[upgrade]", "blue")} Downloading ${release.tag_name}...\n`);

  const downloadResponse = await fetch(asset.browser_download_url);
  if (!downloadResponse.ok) {
    process.stderr.write(`${color("[error]", "red")} Download failed: ${downloadResponse.status}\n`);
    process.exit(1);
  }

  const blob = await downloadResponse.blob();
  await Bun.write(tmpPath, blob);

  if (process.platform === "win32") {
    const batPath = currentPath + ".upgrade.bat";
    await Bun.write(batPath,
      `@echo off\r\n` +
      `timeout /t 1 /nobreak >nul\r\n` +
      `move /y "${tmpPath}" "${currentPath}"\r\n` +
      `del "%~f0"\r\n`
    );
    Bun.spawnSync(["cmd", "/c", batPath], { detached: true });
  } else {
    Bun.spawnSync(["chmod", "+x", tmpPath]);
    Bun.spawnSync(["mv", tmpPath, currentPath]);
  }

  process.stdout.write(`${color("[upgrade]", "green")} Upgraded to ${release.tag_name}\n`);
}
