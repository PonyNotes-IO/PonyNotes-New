@echo off

REM Store the current working directory
set "original_dir=%CD%"

REM Change the current working directory to the script's location
cd /d "%~dp0"

REM Navigate to the project root
cd ..\..\..\appflowy_flutter

REM Navigate to the appflowy_flutter directory and generate files
echo Generating files for appflowy_flutter
echo Running flutter pub get...
call flutter pub get
if errorlevel 1 ( echo Error: flutter pub get failed & exit /b 1 )
call dart run build_runner clean
if errorlevel 1 ( echo Error: build_runner clean failed & exit /b 1 )
call dart run build_runner build -d
if errorlevel 1 ( echo Error: build_runner build failed & exit /b 1 )
echo Done generating files for appflowy_flutter

echo Generating files for packages
cd packages
for /D %%d in (*) do (
    REM Navigate into the subdirectory
    cd "%%d"

    REM Check if the subdirectory contains a pubspec.yaml file
    if exist "pubspec.yaml" (
        echo Generating freezed files in %%d...
        echo Please wait while we clean the project and fetch the dependencies.
        call flutter pub get
        if errorlevel 1 ( echo Error: flutter pub get failed in %%d & cd .. & cd /d "%original_dir%" & exit /b 1 )
        call dart run build_runner clean
        if errorlevel 1 ( echo Warning: build_runner clean failed in %%d, continuing... )
        call dart run build_runner build -d
        if errorlevel 1 ( echo Error: build_runner build failed in %%d & cd .. & cd /d "%original_dir%" & exit /b 1 )
        echo Done running build command in %%d
    ) else (
        echo No pubspec.yaml found in %%d, it can't be a Dart project. Skipping.
    )

    REM Navigate back to the packages directory
    cd ..
)

REM Return to the original directory
cd /d "%original_dir%"
