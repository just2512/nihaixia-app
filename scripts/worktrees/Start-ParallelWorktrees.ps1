[CmdletBinding()]
param(
    [string]$WorktreeRoot = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = (& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoRoot)) {
    throw "请先在 nihaixia-app 仓库目录或其子目录中运行此脚本。"
}
$repoRoot = $repoRoot.Trim()

if ([string]::IsNullOrWhiteSpace($WorktreeRoot)) {
    $parent = Split-Path -Parent $repoRoot
    $WorktreeRoot = Join-Path $parent "nihaixia-app-worktrees"
}

& git -C $repoRoot fetch origin
if ($LASTEXITCODE -ne 0) { throw "git fetch origin 失败。" }

$branches = @(
    "work/ziwei-fold-layout",
    "work/ai-unified-assistant",
    "work/tcm-knowledge-tools",
    "work/classic-case-provenance",
    "work/app-capability-audit"
)

New-Item -ItemType Directory -Force -Path $WorktreeRoot | Out-Null

foreach ($branch in $branches) {
    $folderName = $branch.Replace("/", "-")
    $path = Join-Path $WorktreeRoot $folderName

    if (Test-Path $path) {
        Write-Host "[SKIP] 工作目录已存在：$path"
        continue
    }

    & git -C $repoRoot show-ref --verify --quiet "refs/heads/$branch"
    $localBranchExists = ($LASTEXITCODE -eq 0)

    if ($localBranchExists) {
        & git -C $repoRoot worktree add $path $branch
    }
    else {
        & git -C $repoRoot worktree add --track -b $branch $path "origin/$branch"
    }

    if ($LASTEXITCODE -ne 0) {
        throw "创建 worktree 失败：$branch"
    }

    Write-Host "[OK] $branch -> $path"
}

Write-Host ""
Write-Host "五个隔离工作目录已准备。每个代理只在对应目录内修改，不要共用工作目录。"
Write-Host "集成目录仍由你单独检出 integration 分支后执行完整回归。"
