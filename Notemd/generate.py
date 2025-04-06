import subprocess
import os

def main():
    script_path = os.path.join(os.path.dirname(__file__), 'scripts', 'Generate-Documentation.ps1')
    subprocess.run(['pwsh', '-File', script_path], check=True)

if __name__ == '__main__':
    main()
