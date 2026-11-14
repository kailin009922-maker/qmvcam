param([string[]]$Arch=@('arm64'),[string]$Name="qmvcam")
$outDir="D:\Backup\Documents\deepseek-harness\default-workspace\qm-vcam\build"
$fat = Join-Path $outDir "$Name.dylib"
Write-Host "NAME=[$Name] FAT=[$fat] OutDir=[$outDir]"
$slices=@(); $slices += (Join-Path $outDir 'qmvcam-arm64.dylib')
Write-Host "count=$($slices.Count) slice0=$($slices[0])"
$pyargs = @('x.py', $fat) + @($slices)
Write-Host "args: $($pyargs -join ' | ')"
