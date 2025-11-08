param([int]$KeepLast = 2)
$ErrorActionPreference = 'Stop'

$stamp  = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$outDir = '_snapshot'
$outFile = Join-Path $outDir ("codebase_snapshot_{0}.md" -f $stamp)

$exts = @('.lua','.luau','.ts','.tsx','.js','.json','.md','.txt')
$skip = '\\(\.git|_snapshot|node_modules|dist|build|Packages|\.vscode|\.idea|coverage)(\\|/|$)'

Write-Host "[1/5] Ensuring $outDir..."
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Write-Host "[2/5] Collecting files..."
$repoRoot = (Get-Location).Path
$files = Get-ChildItem -Recurse -File -Force |
  Where-Object {
    $exts -contains $_.Extension.ToLower() -and
    $_.FullName -notmatch $skip -and
    -not (($_.Attributes -band [IO.FileAttributes]::Offline) -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint))
  } |
  Sort-Object FullName

Write-Host ("      Found {0} files" -f $files.Count)

Write-Host "[3/5] Writing snapshot -> $outFile"
$header = "# Steve-Lebron — codebase snapshot ($stamp)`r`n`r`n## Table of contents`r`n"
Set-Content -Path $outFile -Encoding UTF8 $header

foreach ($f in $files) {
  $rel = $f.FullName.Substring($repoRoot.Length).TrimStart('\','/')
  $anc = ($rel -replace '[^A-Za-z0-9 -/]','' -replace '[ /]','-').ToLower()
  Add-Content -Path $outFile -Encoding UTF8 ("- [{0}](#{1})" -f $rel, $anc)
}

foreach ($f in $files) {
  if (-not (Test-Path -LiteralPath $f.FullName)) { continue }
  $rel  = $f.FullName.Substring($repoRoot.Length).TrimStart('\','/')
  $lang = $f.Extension.Trim('.').ToLower()
  Add-Content -Path $outFile -Encoding UTF8 "`r`n## $rel`r`n```$lang`r`n"
  Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue |
    Add-Content -Path $outFile -Encoding UTF8
  Add-Content -Path $outFile -Encoding UTF8 "`r`n```"
}

Write-Host "[4/5] Pruning older snapshots..."
Get-ChildItem -Path $outDir -Filter 'codebase_snapshot_*.md' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -Skip $KeepLast |
  Remove-Item -Force -ErrorAction SilentlyContinue

Write-Host "[5/5] Done -> $outFile"
