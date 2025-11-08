param(
  [string]$OutDir = "_snapshot",
  [int]$KeepLast = 2,          # how many latest snapshots to keep
  [int]$MaxKB    = 256         # skip any single file larger than this
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Get-Location).Path

# Ensure snapshot dir
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# Prune old snapshots (keep newest $KeepLast)
$existing = Get-ChildItem -Path $OutDir -Filter 'codebase_snapshot_*.md' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending
if ($existing.Count -gt $KeepLast) {
  $existing | Select-Object -Skip $KeepLast | Remove-Item -Force
}

$stamp  = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$outFile = Join-Path $OutDir "codebase_snapshot_$stamp.md"

# Map extensions → code fence hints
$extToFence = @{
  '.lua' = 'lua'
  '.ts'  = 'ts'
  '.tsx' = 'tsx'
  '.js'  = 'js'
  '.json'= 'json'
  '.md'  = 'md'
  '.txt' = ''
  '.cfg' = ''
}

# Folders to exclude from recursion
$excludeDirs = @(
  '.git', $OutDir, 'node_modules', 'dist', 'build', 'Packages', '.vscode', '.idea', '.next', 'coverage'
)

# Collect eligible files
$files = Get-ChildItem -Recurse -File -Force |
  Where-Object {
    $rel = $_.FullName.Substring($repoRoot.Length).TrimStart('\','/')
    $inExcluded = $false
    foreach ($d in $excludeDirs) {
      if ($rel -match "^(?:$([regex]::Escape($d)))($|[\\/])") { $inExcluded = $true; break }
    }
    -not $inExcluded -and $extToFence.ContainsKey($_.Extension.ToLower())
  } |
  Sort-Object FullName

# Build markdown
$sb = [System.Text.StringBuilder]::new()
$null = $sb.AppendLine("# Steve-Lebron — codebase snapshot ($stamp)")
$null = $sb.AppendLine()
$null = $sb.AppendLine("> Auto-generated Markdown bundle of source files for quick reading/searching.")
$null = $sb.AppendLine()

$sizeSum = ($files | Measure-Object Length -Sum).Sum
$null = $sb.AppendLine("**Summary**")
$null = $sb.AppendLine("- Files included: $($files.Count)")
$null = $sb.AppendLine("- Total size (raw): {0:N0} bytes" -f $sizeSum)
$null = $sb.AppendLine()

$null = $sb.AppendLine("## Table of contents")
foreach ($f in $files) {
  $rel = Resolve-Path -Relative -LiteralPath $f.FullName
  $anchor = ($rel -replace '[^A-Za-z0-9 -/]','' -replace '[ /]','-').ToLower()
  $null = $sb.AppendLine("- [$rel](#$anchor)")
}
$null = $sb.AppendLine()

$maxBytes = $MaxKB * 1KB

foreach ($f in $files) {
  $rel = Resolve-Path -Relative -LiteralPath $f.FullName
  $fence = $extToFence[$f.Extension.ToLower()]
  $anchor = ($rel -replace '[^A-Za-z0-9 -/]','' -replace '[ /]','-').ToLower()

  $null = $sb.AppendLine("## $rel")
  $null = $sb.AppendLine()

  if ($f.Length -gt $maxBytes) {
    $null = $sb.AppendLine("> Skipped (size $([math]::Round($f.Length/1KB,1)) KB > $MaxKB KB).")
    $null = $sb.AppendLine()
    continue
  }

  $content = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue
  if ($null -eq $content) { $content = '' }

  $null = $sb.AppendLine("```$fence")
  $null = $sb.AppendLine($content.Replace("`r`n","`n"))
  $null = $sb.AppendLine("```")
  $null = $sb.AppendLine()
}

[IO.File]::WriteAllText($outFile, $sb.ToString(), [System.Text.Encoding]::UTF8)

Write-Host "Snapshot written to $outFile"
Write-Host "Done."

