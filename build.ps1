# build.ps1 — 在 Windows 上用 LLVM clang + ld64.lld 交叉编译 iOS tweak dylib
#
# 依赖：
#   C:\Program Files\LLVM\bin\clang.exe  (clang 23 + ld64.lld)
#   .\toolchain\iPhoneOS16.5.sdk         (theos/sdks)
#
# 用法： pwsh -File build.ps1 [-Arch arm64,arm64e] [-Sdk <path>]
param(
    [string[]]$Arch = @('arm64','arm64e'),
    [string]$Sdk = "",
    [string]$Name = "qmvcam",
    [switch]$Probe,
    [string]$MinIOS = "16.0"
)

$ErrorActionPreference = 'Continue'
# 从 -File 传进来的 "-Arch arm64,arm64e" 会被当成单个字符串，这里拆开
$Arch = @($Arch | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
if ($Probe) { $Name = "qmprobe" }
$probeDef = if ($Probe) { "-DQMV_PROBE_ONLY=1" } else { "-DQMV_PROBE_ONLY=0" }
$root   = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcDir = Join-Path $root 'src'
$outDir = Join-Path $root 'build'
$dist   = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $outDir, $dist | Out-Null

$clang = 'C:\Program Files\LLVM\bin\clang.exe'
if (-not (Test-Path $clang)) { throw "clang not found: $clang" }

if (-not $Sdk) {
    $cand = Join-Path (Split-Path -Parent $root) 'qm\toolchain\iPhoneOS16.5.sdk'
    if (Test-Path $cand) { $Sdk = $cand }
    else { $Sdk = Join-Path $root 'toolchain\iPhoneOS16.5.sdk' }
}
if (-not (Test-Path $Sdk)) { throw "iOS SDK not found: $Sdk" }

$allSources = @(Get-ChildItem $srcDir -Filter *.m | ForEach-Object { $_.FullName })
$probeSources = @("$srcDir\main.m", "$srcDir\vcam_state.m")
if ($Probe -eq $true) {
    $sources = $probeSources
} else {
    $sources = $allSources
}
$frameworks = @(
    'Foundation','UIKit','AVFoundation','CoreMedia','CoreVideo','VideoToolbox',
    'CoreImage','Metal','QuartzCore','IOSurface','Security','IOKit','Vision',
    'Accelerate','PhotosUI','ImageIO','CoreGraphics'
)
if ($Probe) { $frameworks = @('Foundation','CoreFoundation','IOKit') }

Write-Host ("PROBE=" + $Probe + " SOURCES=" + ($sources.Count) + " files")
$common = @(
    "-isysroot", $Sdk,
    '-fobjc-arc', '-O2', '-DNDEBUG',
    '-fno-exceptions', '-fobjc-runtime=ios-16.0',
    '-I', $srcDir,
    '-I', (Join-Path $srcDir 'shim'),
    '-Wall', '-Wno-unused-variable', '-Wno-unused-function', '-Wno-deprecated-declarations',
    '-Wno-nullability-completeness', '-Wno-objc-method-access'
)

$slices = @()
foreach ($a in $Arch) {
    $objDir = Join-Path $outDir "obj-$a"
    New-Item -ItemType Directory -Force -Path $objDir | Out-Null
    $objs = @()
    foreach ($s in $sources) {
        $o = Join-Path $objDir ((Split-Path -Leaf $s) -replace '\.m$', '.o')
        $a1 = @('-target', "$a-apple-ios$MinIOS", '-c', $s, '-o', $o) + $common
        $a1 += $probeDef
        if ($a -eq 'arm64e') { $a1 += @('-fno-ptrauth-objc-isa','-fno-ptrauth-objc-class-ro') }
        & $clang @a1
        if ($LASTEXITCODE -ne 0) { throw "compile failed: $s ($a)" }
        $objs += $o
    }
    $out = Join-Path $outDir "$Name-$a.dylib"
    $lnk = @('-target', "$a-apple-ios$MinIOS", '-dynamiclib', '-o', $out)
    $lnk += $objs
    $lnk += @('-isysroot', $Sdk)
    $lnk += @("-Wl,-install_name,@rpath/$Name.dylib",
              '-Wl,-undefined,dynamic_lookup',
              '-Wl,-dead_strip',
              '-Wl,-adhoc_codesign')
    foreach ($fw in $frameworks) { $lnk += @('-framework', $fw) }
$lnk += @('-L', (Join-Path $root 'stub'), '-lCydiaSubstrate')
$lnk += @('-Wl,-rpath,@loader_path/.jbroot/Library/Frameworks',
          '-Wl,-rpath,@loader_path/.jbroot/usr/lib',
          '-Wl,-rpath,@loader_path/Library/Frameworks',
          '-Wl,-rpath,@loader_path/usr/lib')
    if ($a -eq 'arm64e') { $lnk += @('-fno-ptrauth-objc-isa') }
    & $clang @lnk
    if ($LASTEXITCODE -ne 0) { throw "link failed ($a)" }
    Write-Host "built $out  ($((Get-Item $out).Length) bytes)"
    $slices += $out
}

# 单 slice 直接作为产物；多 slice 用 tools/makefat.py 合并
if ($slices.Count -gt 1) {
    $fatPath = Join-Path $outDir ($Name + '.dylib')
    $pyargs = @((Join-Path $root 'tools\makefat.py'), $fatPath) + $slices
    & python @pyargs
    Write-Host "fat: $fatPath"
}
Write-Host ("slices: " + ($slices -join ', '))