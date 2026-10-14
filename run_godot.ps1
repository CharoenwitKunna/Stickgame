param(
    [ValidateSet('play', 'test', 'preview', 'smoke', 'bench', 'live', 'profile', 'bake', 'allocbench')]
    [string]$Mode = 'play'
)
$ErrorActionPreference = 'Stop'
$engine = Get-Command 'Godot*.exe' -ErrorAction SilentlyContinue |
    Where-Object { $_.Source -like '*console.exe' } |
    Select-Object -First 1
if (-not $engine) {
    $engine = Get-Command 'Godot*.exe', 'godot.exe', 'godot4.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1
}
if (-not $engine) {
    Write-Error 'Godot 4 was not found on PATH. Open project.godot in your Godot editor instead.'
    exit 1
}
$arguments = @('--path', $PSScriptRoot)

switch ($Mode) {
    'test' { $arguments += @('--headless', '--script', 'res://tests/test_game.gd') }
    'preview' { $arguments += @('--script', 'res://tests/render_smoke.gd') }
    'bench' { $arguments += @('--script', 'res://tests/benchmark.gd') }
    'allocbench' { $arguments += @('--headless', '--script', 'res://tests/test_allocation_reuse.gd', '--', '--bench') }
    'live' { $arguments += @('--script', 'res://tests/benchmark_live.gd') }
    'profile' { $arguments += @('--script', 'res://tests/profile_hotspots.gd') }
    'bake' { $arguments += @('--script', 'res://tools/bake_soldiers.gd') }
    'smoke' { $arguments += @('--quit-after', '180', '--fixed-fps', '60') }
}
& $engine.Source @arguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ($Mode -eq 'test') {
    & $engine.Source --path $PSScriptRoot --headless --script res://tests/test_optimization.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $engine.Source --path $PSScriptRoot --headless --script res://tests/test_atlas.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $engine.Source --path $PSScriptRoot --headless --script res://tests/test_allocation_reuse.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $engine.Source --path $PSScriptRoot --headless --script res://tests/test_endless.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $engine.Source --path $PSScriptRoot --headless --script res://tests/test_performance_fixes.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $engine.Source --path $PSScriptRoot --headless --script res://tests/test_hotpath_fixes.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $engine.Source --path $PSScriptRoot --headless --script res://tests/test_vm_hotpaths.gd
}
exit $LASTEXITCODE
