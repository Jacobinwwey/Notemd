@echo off
REM PowerShell Installation
echo Installing PowerShell 7.2.13...
msiexec.exe /i env\downloads\PowerShell-7.2.13.msi /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1

REM Python Installation
echo Installing Python 3.10.11...
env\downloads\python-3.10.11.exe /quiet InstallAllUsers=1 PrependPath=1

REM Python Package Installation
echo Installing Python packages...
python -m ensurepip --upgrade
python -m pip install --no-index --find-links=env\downloads pip wheel setuptools
python -m pip install --no-index --find-links=env\downloads requests pathlib regex

REM Environment Setup
echo Creating .env file...
echo KNOWLEDGE_BASE_PATH=path_to_your_knowledge_base > .env
echo SEARCH_PATH=path_to_search_directory >> .env
echo PYTHON_EXE=python.exe >> .env
echo CHUNK_SIZE=3000 >> .env
echo TEMPERATURE=0.5 >> .env
echo MAX_TOKENS=8192 >> .env

REM Verification
echo Verifying installations...
pwsh --version
python --version
pip list

pause
