@echo off
REM ============================================================
REM  run.bat — one-click build and simulate
REM  Usage:
REM     run.bat                    (default: sobel_x)
REM     run.bat gaussian
REM     run.bat sobel_x
REM     run.bat sobel_y
REM     run.bat laplacian
REM     run.bat box_blur
REM
REM  Can be run from ANY directory - all paths below are resolved
REM  relative to this script's own location (scripts\), not the
REM  caller's current directory.
REM ============================================================

set KTYPE=%1
if "%KTYPE%"=="" set KTYPE=sobel_x

REM ---- Resolve project root (one level above this script) ----
set ROOT=%~dp0..
set PY_TOOLS=%ROOT%\py_tools
set GOLDEN=%ROOT%\golden_model
set RTL=%ROOT%\rtl
set TB=%ROOT%\tb
set BUILD=%ROOT%\build

echo ============================================
echo   Kernel type: %KTYPE%
echo ============================================

echo [1/5] Preprocessing image...
pushd "%PY_TOOLS%"
python preproccess.py
if errorlevel 1 goto :err
popd

echo [2/5] Generating kernel: %KTYPE%
pushd "%PY_TOOLS%"
python kernal_generation.py %KTYPE%
if errorlevel 1 goto :err
popd

echo [3/5] Running golden model...
pushd "%GOLDEN%"
python golden_model.py
if errorlevel 1 goto :err
popd

echo [4/5] Compiling and simulating with ModelSim...
if not exist "%BUILD%" mkdir "%BUILD%"
pushd "%BUILD%"

vlib work
if errorlevel 1 (popd & goto :err)

REM Compile every RTL module (bottom-up order doesn't matter to vlog,
REM but listed here for readability), then the top-level integration
REM testbench - the one that streams the whole image through and is
REM expected to write out_hw.txt for show.py to compare/visualize.
vlog ^
    "%RTL%\line_buffer.v" ^
    "%RTL%\window_generator.v" ^
    "%RTL%\kernel_reg_file.v" ^
    "%RTL%\conv_mac_tree.v" ^
    "%RTL%\round_saturate_relu.v" ^
    "%RTL%\conv_accel_top.v" ^
    "%TB%\tb_conv_accel_top.v"
if errorlevel 1 (popd & goto :err)

vsim -c tb_conv_accel_top -do "run -all; quit"
if errorlevel 1 (popd & goto :err)

popd

echo [5/5] Comparing and showing results...
pushd "%PY_TOOLS%"
python show.py
popd
goto :eof

:err
echo.
echo [ERROR] something failed. Check messages above.
pause