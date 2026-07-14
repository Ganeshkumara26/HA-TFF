$ErrorActionPreference = "Stop"
Write-Host "Compiling RTL and TB..."
$files = Get-ChildItem -Path ..\rtl\*.v -Name | ForEach-Object { "..\rtl\$_" }
$files += "..\tb\tb_ha_tff_system_top.v"
& "D:\softwares\AMD\2026.1\Vivado\bin\xvlog.bat" -sv $files

Write-Host "Elaborating..."
& "D:\softwares\AMD\2026.1\Vivado\bin\xelab.bat" -top tb_ha_tff_system_top -snapshot tb_snap --debug typical

Write-Host "Simulating..."
& "D:\softwares\AMD\2026.1\Vivado\bin\xsim.bat" tb_snap -R

Write-Host "Simulation complete."
