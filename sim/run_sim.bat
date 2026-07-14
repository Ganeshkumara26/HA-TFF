@echo off
echo Compiling RTL and TB...
call "D:\softwares\AMD\2026.1\Vivado\bin\xvlog.bat" -sv ../rtl/*.v ../tb/tb_ha_tff_system_top.v
if %errorlevel% neq 0 exit /b %errorlevel%

echo Elaborating...
call "D:\softwares\AMD\2026.1\Vivado\bin\xelab.bat" -top tb_ha_tff_system_top -snapshot tb_snap --debug typical
if %errorlevel% neq 0 exit /b %errorlevel%

echo Simulating...
call "D:\softwares\AMD\2026.1\Vivado\bin\xsim.bat" tb_snap -R
if %errorlevel% neq 0 exit /b %errorlevel%

echo Simulation complete.
