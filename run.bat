@echo off
REM ============================================================
REM  run.bat  — one-click build and simulate
REM  Usage:
REM     run.bat                    (default: sobel_x)
REM     run.bat gaussian
REM     run.bat sobel_x
REM     run.bat sobel_y
REM     run.bat laplacian
REM     run.bat box_blur
REM ============================================================

set KTYPE=%1
if "%KTYPE%"=="" set KTYPE=sobel_x

echo ============================================
echo   Kernel type: %KTYPE%
echo ============================================

echo [1/5] Preprocessing image...
cd tools
python preproccess.py
if errorlevel 1 goto :err

echo [2/5] Generating kernel: %KTYPE%
python kernal_generation.py %KTYPE%
if errorlevel 1 goto :err

echo [3/5] Running golden model...
python golden_model.py
if errorlevel 1 goto :err

echo [4/5] Compiling and simulating with ModelSim...
cd ..\rtl
vlib work
vlog rtl.v tb.v
if errorlevel 1 goto :err
vsim -c tb -do "run -all; quit"
if errorlevel 1 goto :err

echo [5/5] Comparing and showing results...
cd ..\tools
python show.py
goto :eof

:err
echo.
echo [ERROR] something failed. Check messages above.
pause