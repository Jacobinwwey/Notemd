# Notemd Installation Guide

## Offline Installation Steps

1. Install PowerShell 7.2.13:
```bash
msiexec.exe /i env\downloads\PowerShell-7.2.13.msi /quiet
```

2. Install Python 3.10.11:
```bash
env\downloads\python-3.10.11.exe /quiet InstallAllUsers=1 PrependPath=1
```

3. Install Python packages:
```bash
python -m pip install --no-index --find-links=env\downloads requests pathlib regex
```

4. Build and install Notemd package:
```bash
python setup.py sdist
pip install dist/Notemd-1.0.0.tar.gz
```

## Verification

Check installed components:
```bash
pwsh --version
python --version
pip list
```

## Usage

Available commands:
- `notemd-process`: Process PDF files
- `notemd-generate`: Generate documentation 
- `notemd-clean`: Remove duplicate files
