<#
.SYNOPSIS
Batch process multiple markdown files with Obsidian integration and enhanced timeout handling

.NOTES
1. Processes all full.md files in current directory and subdirectories
2. Requires PowerShell 7.2+ and Python 3.10+
3. Configuration via .env file or environment variables
#>

# Load .env file if it exists
function Import-DotEnv {
    param(
        [string]$EnvFile = ".env"
    )
    
    if (Test-Path $EnvFile) {
        Write-Host "Loading configuration from $EnvFile"
        Get-Content $EnvFile | ForEach-Object {
            if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                # Remove quotes if present
                if ($value -match '^["''](.*)["'']$') {
                    $value = $matches[1]
                }
                [Environment]::SetEnvironmentVariable($key, $value)
            }
        }
    }
}

# Load environment variables
Import-DotEnv

# Configuration with environment variable fallbacks
$config = @{
    BaseDir         = (Get-Location).Path
    ProcessSuffix   = "_process"
    KnowledgeBase   = $env:KNOWLEDGE_BASE_PATH ?? "E:\Knowledge\Study\dp_know\undo"
    PythonExe       = $env:PYTHON_EXE ?? "python.exe"
    ChunkSize       = [int]($env:CHUNK_SIZE ?? 3000)
    Temperature     = [double]($env:TEMPERATURE ?? 0.5)
    MaxTokens       = [int]($env:MAX_TOKENS ?? 8192)
    ProcessedLog    = "processed.log"
    SearchPath      = $env:SEARCH_PATH ?? "E:\Knowledge\Study\dp_know"
}

$SCHEDULE_CONFIG = @{
    StartDelayHours = [double]($env:START_DELAY_HOURS ?? 5.2)
    TimeoutHours    = [double]($env:TIMEOUT_HOURS ?? 8)
    CheckInterval   = [int]($env:CHECK_INTERVAL ?? 30)
    MaxCycles       = [int]($env:MAX_CYCLES ?? 1000)
}

# LLM Provider Configuration
$LLM_PROVIDER = $env:LLM_PROVIDER ?? "deepseek"

# Multi-provider LLM Configuration
$LLM_CONFIG = @{
    Provider = $LLM_PROVIDER
    Temperature = $config.Temperature
    MaxTokens = $config.MaxTokens
}

# Configure provider-specific settings
switch ($LLM_PROVIDER) {
    "deepseek" {
        $LLM_CONFIG["BaseURL"] = $env:DEEPSEEK_ENDPOINT ?? "https://api.deepseek.com/v1/chat/completions"
        $LLM_CONFIG["ApiKey"] = $env:DEEPSEEK_API_KEY ?? ""
        $LLM_CONFIG["Model"] = $env:DEEPSEEK_MODEL ?? "deepseek-reasoner"
    }
    "openai" {
        $LLM_CONFIG["BaseURL"] = $env:OPENAI_ENDPOINT ?? "https://api.openai.com/v1"
        $LLM_CONFIG["ApiKey"] = $env:OPENAI_API_KEY ?? ""
        $LLM_CONFIG["Model"] = $env:OPENAI_MODEL ?? "gpt-4o"
    }
    "anthropic" {
        $LLM_CONFIG["BaseURL"] = "https://api.anthropic.com"
        $LLM_CONFIG["ApiKey"] = $env:ANTHROPIC_API_KEY ?? ""
        $LLM_CONFIG["Model"] = $env:ANTHROPIC_MODEL ?? "claude-3-5-sonnet-20241022"
    }
    "google" {
        $LLM_CONFIG["ApiKey"] = $env:GOOGLE_API_KEY ?? ""
        $LLM_CONFIG["Model"] = $env:GOOGLE_MODEL ?? "gemini-2.0-flash-exp"
    }
    "mistral" {
        $LLM_CONFIG["BaseURL"] = $env:MISTRAL_ENDPOINT ?? "https://api.mistral.ai/v1"
        $LLM_CONFIG["ApiKey"] = $env:MISTRAL_API_KEY ?? ""
        $LLM_CONFIG["Model"] = $env:MISTRAL_MODEL ?? "mistral-large-latest"
    }
    "azure_openai" {
        $LLM_CONFIG["BaseURL"] = $env:AZURE_OPENAI_ENDPOINT ?? ""
        $LLM_CONFIG["ApiKey"] = $env:AZURE_OPENAI_API_KEY ?? ""
        $LLM_CONFIG["Model"] = $env:AZURE_OPENAI_MODEL ?? "gpt-4o"
        $LLM_CONFIG["ApiVersion"] = $env:AZURE_OPENAI_API_VERSION ?? "2025-01-01-preview"
    }
    default {
        Write-Host "Unknown LLM provider: $LLM_PROVIDER. Defaulting to DeepSeek." -ForegroundColor Yellow
        $LLM_CONFIG["Provider"] = "deepseek"
        $LLM_CONFIG["BaseURL"] = $env:DEEPSEEK_ENDPOINT ?? "https://api.deepseek.com/v1/chat/completions"
        $LLM_CONFIG["ApiKey"] = $env:DEEPSEEK_API_KEY ?? ""
        $LLM_CONFIG["Model"] = $env:DEEPSEEK_MODEL ?? "deepseek-reasoner"
    }
}

# Validate API key
if ([string]::IsNullOrWhiteSpace($LLM_CONFIG["ApiKey"])) {
    $providerName = $LLM_CONFIG["Provider"].ToUpper()
    $envVarName = "${providerName}_API_KEY"
    
    Write-Host "ERROR: No API key found for $($LLM_CONFIG["Provider"])!" -ForegroundColor Red
    Write-Host "Please set a valid API key in your .env file or environment variable:" -ForegroundColor Yellow
    Write-Host "$envVarName=your-api-key-here" -ForegroundColor Yellow
    
    # Prompt user for API key
    $apiKey = Read-Host "Enter your $($LLM_CONFIG["Provider"]) API key to continue"
    
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        Write-Host "No API key provided. Exiting script." -ForegroundColor Red
        exit 1
    }
    
    # Set the API key
    $LLM_CONFIG["ApiKey"] = $apiKey
    [Environment]::SetEnvironmentVariable($envVarName, $apiKey)
    
    # Update .env file
    $envPath = Join-Path (Get-Location) ".env"
    $envContent = Get-Content $envPath -Raw
    $pattern = "(?m)^$envVarName=.*$"
    
    if ($envContent -match $pattern) {
        $envContent = $envContent -replace $pattern, "$envVarName=$apiKey"
    } else {
        $envContent += "`n$envVarName=$apiKey"
    }
    
    Set-Content -Path $envPath -Value $envContent -Encoding UTF8
    Write-Host "API key saved to .env file." -ForegroundColor Green
}

# Set API key for backward compatibility
if ($LLM_PROVIDER -eq "deepseek") {
    $env:DEEPSEEK_API_KEY = $LLM_CONFIG.ApiKey
}

# System Optimization
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
[System.Threading.ThreadPool]::SetMinThreads(100, 100) | Out-Null

function Start-CountdownTimer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0, 2147483647)]
        [int]$Seconds,
        
        [string]$Message = "Countdown"
    )

    $endTime = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $endTime) {
        $remaining = $endTime - (Get-Date)
        $percentComplete = ($Seconds - $remaining.TotalSeconds)/$Seconds*100
        Write-Progress -Activity $Message `
            -Status "Remaining: $($remaining.ToString('hh\:mm\:ss'))" `
            -PercentComplete $percentComplete `
            -SecondsRemaining $remaining.TotalSeconds
        Start-Sleep -Seconds 1
    }
    Write-Progress -Activity $Message -Completed
}

function Initialize-Processing {
    param(
        [System.IO.FileInfo]$MarkdownFile
    )
    
    $processingEnv = @{
        WorkingDir  = $MarkdownFile.DirectoryName
        ProcessDir  = Join-Path $MarkdownFile.DirectoryName ($MarkdownFile.BaseName + $config.ProcessSuffix)
        OutputFile  = Join-Path $MarkdownFile.DirectoryName ($MarkdownFile.BaseName + "_adjusted.md")
    }

    New-Item -Path $processingEnv.ProcessDir -ItemType Directory -Force | Out-Null
    
    return $processingEnv
}

function Split-MarkdownFile {
    param(
        [System.IO.FileInfo]$InputFile,
        [string]$ProcessDir
    )

    $pythonScript = @"
import os
import re
from pathlib import Path

def split_markdown():
    input_path = Path(r'$($InputFile.FullName)')
    output_dir = Path(r'$ProcessDir')
    output_dir.mkdir(exist_ok=True)
    
    with open(input_path, 'r', encoding='utf-8', buffering=2097152) as f:
        content = f.read()
    
    paragraphs = re.split(r'(\n\s*\n+)', content)
    current_chunk = []
    current_count = 0
    chunk_num = 1
    
    for i in range(0, len(paragraphs), 2):
        para = paragraphs[i]
        if not para.strip():
            continue
        para_word_count = len(para.split())
        
        if current_count + para_word_count > $($config.ChunkSize) and current_count > 0:
            write_chunk(output_dir, chunk_num, current_chunk)
            chunk_num += 1
            current_chunk = []
            current_count = 0
            
        current_chunk.append(para + (paragraphs[i+1] if i+1 < len(paragraphs) else ''))
        current_count += para_word_count
    
    if current_chunk:
        write_chunk(output_dir, chunk_num, current_chunk)

def write_chunk(output_dir, chunk_num, chunk_content):
    chunk_file = output_dir / f"chunk_{chunk_num:03d}.md"
    with open(chunk_file, 'w', encoding='utf-8', buffering=2097152) as f:
        f.write("".join(chunk_content).strip())
        f.write("\n")

if __name__ == "__main__":
    split_markdown()
"@

    $tempScript = [System.IO.Path]::GetTempFileName() + ".py"
    try {
        $pythonScript | Out-File $tempScript -Encoding utf8
        & $config.PythonExe $tempScript
        if (-not $?) { throw "Python splitting failed with exit code $LASTEXITCODE" }
    }
    finally {
        Remove-Item $tempScript -ErrorAction SilentlyContinue
    }
}

function Invoke-LLMProcessing {
    param(
        [string]$ProcessDir
    )

    $modifiedScript = Get-Content 'Generate-Documentation.ps1' -Raw
    
    # Update configuration in the script
    $modifiedScript = $modifiedScript -replace 
        '(?<=Temperature\s*=\s*)(\d+\.?\d*)', 
        $config.Temperature.ToString()
    $modifiedScript = $modifiedScript -replace 
        '(?<=StartDelayHours\s*=\s*)(\d+\.?\d*)', 
        '0'
    $modifiedScript = $modifiedScript -replace
        '(?<=MaxTokens\s*=\s*)(\d+)',
        $config.MaxTokens.ToString()
    
    # Create Python script for multi-provider LLM processing
    $pythonLLMScript = @"
import os
import sys
import json
import requests
from pathlib import Path

# LLM Configuration
LLM_CONFIG = {
    "provider": "$($LLM_CONFIG.Provider)",
    "temperature": $($LLM_CONFIG.Temperature),
    "max_tokens": $($LLM_CONFIG.MaxTokens),
    "model": "$($LLM_CONFIG.Model)",
    "api_key": "$($LLM_CONFIG.ApiKey)",
    "base_url": "$($LLM_CONFIG.BaseURL)"
}

# Add API version for Azure
$(if ($LLM_CONFIG.Provider -eq "azure_openai") { "LLM_CONFIG['api_version'] = '$($LLM_CONFIG.ApiVersion)'" })

def process_chunk(chunk_path):
    with open(chunk_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Create the prompt
    prompt = """
Completely decompose and structure the knowledge points in this md document, and output them in md format supported by obisidian, in which the core knowledge points are labelled with Obisidian's backlink format [[]]. Do not output anything other than the original text and the requested "Obisidian's backlink format [[]]" .

Rules:
1. Only markup, no content changes
2. Skip conventional names (products/companies/time/individual names)
3. Output full content in md
4. Remove duplicate concepts, No repetitive labeling of the singular and plural forms of a word, Only the singular one is labeled if it contains two or more of the same word; if there is only one word in a core word and the other core words contain that word, the core word of that single word is not labeled.
5. Ignore references
"""

    # Process with the appropriate LLM provider
    result = call_llm_api(prompt, content)
    
    # Write the result
    output_path = chunk_path.parent / f"processed_{chunk_path.name}"
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(result)
    
    return output_path

def call_llm_api(prompt, content):
    provider = LLM_CONFIG["provider"]
    
    if provider == "deepseek":
        return call_deepseek_api(prompt, content)
    elif provider == "openai":
        return call_openai_api(prompt, content)
    elif provider == "anthropic":
        return call_anthropic_api(prompt, content)
    elif provider == "google":
        return call_google_api(prompt, content)
    elif provider == "mistral":
        return call_mistral_api(prompt, content)
    elif provider == "azure_openai":
        return call_azure_openai_api(prompt, content)
    else:
        raise ValueError(f"Unsupported provider: {provider}")

def call_deepseek_api(prompt, content):
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {LLM_CONFIG['api_key']}"
    }
    
    data = {
        "model": LLM_CONFIG["model"],
        "messages": [
            {"role": "system", "content": prompt},
            {"role": "user", "content": content}
        ],
        "temperature": LLM_CONFIG["temperature"],
        "max_tokens": LLM_CONFIG["max_tokens"]
    }
    
    response = requests.post(
        f"{LLM_CONFIG['base_url']}",
        headers=headers,
        json=data
    )
    
    if response.status_code != 200:
        raise Exception(f"DeepSeek API error: {response.status_code} - {response.text}")
    
    return response.json()["choices"][0]["message"]["content"]

def call_openai_api(prompt, content):
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {LLM_CONFIG['api_key']}"
    }
    
    data = {
        "model": LLM_CONFIG["model"],
        "messages": [
            {"role": "system", "content": prompt},
            {"role": "user", "content": content}
        ],
        "temperature": LLM_CONFIG["temperature"],
        "max_tokens": LLM_CONFIG["max_tokens"]
    }
    
    response = requests.post(
        f"{LLM_CONFIG['base_url']}/chat/completions",
        headers=headers,
        json=data
    )
    
    if response.status_code != 200:
        raise Exception(f"OpenAI API error: {response.status_code} - {response.text}")
    
    return response.json()["choices"][0]["message"]["content"]

def call_anthropic_api(prompt, content):
    headers = {
        "Content-Type": "application/json",
        "x-api-key": LLM_CONFIG["api_key"],
        "anthropic-version": "2023-06-01"
    }
    
    data = {
        "model": LLM_CONFIG["model"],
        "messages": [
            {"role": "user", "content": f"{prompt}\n\n{content}"}
        ],
        "temperature": LLM_CONFIG["temperature"],
        "max_tokens": LLM_CONFIG["max_tokens"]
    }
    
    response = requests.post(
        f"{LLM_CONFIG['base_url']}/v1/messages",
        headers=headers,
        json=data
    )
    
    if response.status_code != 200:
        raise Exception(f"Anthropic API error: {response.status_code} - {response.text}")
    
    return response.json()["content"][0]["text"]

def call_google_api(prompt, content):
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {LLM_CONFIG['api_key']}"
    }
    
    data = {
        "contents": [
            {"role": "user", "parts": [{"text": f"{prompt}\n\n{content}"}]}
        ],
        "generationConfig": {
            "temperature": LLM_CONFIG["temperature"],
            "maxOutputTokens": LLM_CONFIG["max_tokens"]
        }
    }
    
    response = requests.post(
        f"https://generativelanguage.googleapis.com/v1/models/{LLM_CONFIG['model']}:generateContent",
        headers=headers,
        json=data
    )
    
    if response.status_code != 200:
        raise Exception(f"Google API error: {response.status_code} - {response.text}")
    
    return response.json()["candidates"][0]["content"]["parts"][0]["text"]

def call_mistral_api(prompt, content):
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {LLM_CONFIG['api_key']}"
    }
    
    data = {
        "model": LLM_CONFIG["model"],
        "messages": [
            {"role": "system", "content": prompt},
            {"role": "user", "content": content}
        ],
        "temperature": LLM_CONFIG["temperature"],
        "max_tokens": LLM_CONFIG["max_tokens"]
    }
    
    response = requests.post(
        f"{LLM_CONFIG['base_url']}/chat/completions",
        headers=headers,
        json=data
    )
    
    if response.status_code != 200:
        raise Exception(f"Mistral API error: {response.status_code} - {response.text}")
    
    return response.json()["choices"][0]["message"]["content"]

def call_azure_openai_api(prompt, content):
    headers = {
        "Content-Type": "application/json",
        "api-key": LLM_CONFIG["api_key"]
    }
    
    data = {
        "messages": [
            {"role": "system", "content": prompt},
            {"role": "user", "content": content}
        ],
        "temperature": LLM_CONFIG["temperature"],
        "max_tokens": LLM_CONFIG["max_tokens"]
    }
    
    response = requests.post(
        f"{LLM_CONFIG['base_url']}/openai/deployments/{LLM_CONFIG['model']}/chat/completions?api-version={LLM_CONFIG['api_version']}",
        headers=headers,
        json=data
    )
    
    if response.status_code != 200:
        raise Exception(f"Azure OpenAI API error: {response.status_code} - {response.text}")
    
    return response.json()["choices"][0]["message"]["content"]

def main():
    process_dir = Path(r'$ProcessDir')
    chunk_files = sorted(list(process_dir.glob("chunk_*.md")))
    
    for chunk_file in chunk_files:
        print(f"Processing {chunk_file.name}...")
        try:
            output_path = process_chunk(chunk_file)
            print(f"Successfully processed: {output_path}")
        except Exception as e:
            print(f"Error processing {chunk_file.name}: {str(e)}")
            sys.exit(1)

if __name__ == "__main__":
    main()
"@

    $tempPyScript = Join-Path $ProcessDir "llm_processor.py"
    try {
        $pythonLLMScript | Out-File $tempPyScript -Encoding utf8
        
        Write-Host "Starting LLM processing with provider: $($LLM_CONFIG.Provider)" -ForegroundColor Cyan
        Write-Host "Using model: $($LLM_CONFIG.Model)" -ForegroundColor Cyan
        
        & $config.PythonExe $tempPyScript
        if (-not $?) { throw "LLM processing failed with exit code $LASTEXITCODE" }
        
        # Rename processed files to match expected format for merging
        Get-ChildItem -Path $ProcessDir -Filter "processed_chunk_*.md" | ForEach-Object {
            $newName = $_.Name -replace "^processed_", ""
            Rename-Item -Path $_.FullName -NewName $newName -Force
        }
    }
    catch {
        Write-Host "Error in LLM processing: $_" -ForegroundColor Red
        throw
    }
    finally {
        # Clean up temporary files
        Remove-Item $tempPyScript -ErrorAction SilentlyContinue
    }
}

function Merge-Files {
    param(
        [string]$ProcessDir,
        [string]$OutputFile
    )
    
    Remove-Item $OutputFile -ErrorAction SilentlyContinue
    
    $baseName = (Split-Path -Leaf $ProcessDir) -replace '_process$',''
    $headerPattern = "^# $([regex]::Escape($baseName))$"
    $isFirstChunk = $true
    
    Get-ChildItem $ProcessDir\*.md | 
        Sort-Object { [int][regex]::Match($_.Name, '\d+').Value } |
        ForEach-Object {
            $content = Get-Content $_.FullName -Encoding UTF8
            
            if (-not $isFirstChunk) {
                # Remove preprocessing headers and empty lines
                $content = $content | Where-Object { 
                    $_ -notmatch $headerPattern -and
                    $_ -notmatch '^# Generated by DeepSeek Reasoner'
                }
                
                # Trim redundant empty lines between chunks
                if ($content[0] -eq '') {
                    $content = $content[1..($content.Count-1)]
                }
            }
            else {
                $isFirstChunk = $false
            }
            
            # Normalize line endings and empty lines
            $content -join "`r`n" | 
                Add-Content $OutputFile -Encoding UTF8 -NoNewline
            
            # Add proper paragraph spacing
            Add-Content $OutputFile -Value "`r`n`r`n" -Encoding UTF8 -NoNewline
        }
    
    # Final cleanup of trailing whitespace
    (Get-Content $OutputFile -Raw) -replace '(?ms)\s+$', '' | 
        Set-Content $OutputFile -Encoding UTF8 -NoNewline
}

function Create-ObsidianNotes {
    param(
        [string]$InputFile
    )
    
    $content = Get-Content $InputFile -Raw -Encoding UTF8
    $pattern = '(?s)\[\[([^\[\]]+)\]\]'  # Strict capture between brackets

    $matches = [regex]::Matches($content, $pattern)
    
    $matches | ForEach-Object {
        $baseName = $_.Groups[1].Value.Trim()
        if (-not [string]::IsNullOrWhiteSpace($baseName)) {
            # Remove special characters and normalize
            $safeName = $baseName -replace '[\\/:*?"<>|£$%^]', ''
            $safeName = $safeName.Trim() -replace '\s+', ' '
            
            # Handle long filenames
            if ($safeName.Length -gt 128) {
                $hash = (Get-FileHash -Algorithm SHA256 -InputStream (
                    [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($baseName))
                )).Hash.Substring(0,8)
                $safeName = $safeName.Substring(0,120) + "_$hash"
            }
            
            # Ensure valid filename
            $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
            $safeName = $safeName -replace "[$([Regex]::Escape($invalidChars -join ''))]", ""
            
            $targetFile = Join-Path $config.KnowledgeBase "$safeName.md"
            if (-not (Test-Path $targetFile)) {
                $null = New-Item -Path $targetFile -ItemType File -Force
                Set-Content $targetFile -Value "# $baseName" -Encoding utf8 -NoNewline
            }
        }
    } | Sort-Object -Unique
}

# Main execution flow with enhanced timeout handling
try {
    # Initialize processed log
    $processedLog = Join-Path $config.BaseDir $config.ProcessedLog
    if (-not (Test-Path $processedLog)) {
        New-Item -Path $processedLog -ItemType File -Force | Out-Null
    }
    $processedFiles = Get-Content $processedLog -ErrorAction SilentlyContinue | Where-Object { $_ -ne "" }

    if ($SCHEDULE_CONFIG.StartDelayHours -gt 0) {
        $delaySeconds = $SCHEDULE_CONFIG.StartDelayHours * 3600
        Write-Host "Delaying start for $($SCHEDULE_CONFIG.StartDelayHours) hours..."
        Start-CountdownTimer -Seconds $delaySeconds -Message "Initial Delay"
    }

    $isFirstCycle = $true
    $cycleCount = 0
    $completed = $false

    while ($cycleCount -lt $SCHEDULE_CONFIG.MaxCycles -and -not $completed) {
        $cycleCount++
        $currentTimeout = if ($isFirstCycle) { $SCHEDULE_CONFIG.TimeoutHours } else { 8 }
        $isFirstCycle = $false

        $cycleStart = Get-Date
        $timeoutDeadline = $cycleStart.AddHours($currentTimeout)
        Write-Host @"
`n[PROCESSING CYCLE $cycleCount]
Start Time:    $($cycleStart.ToString('yyyy-MM-dd HH:mm:ss'))
Timeout After: $currentTimeout hours
Deadline:      $($timeoutDeadline.ToString('yyyy-MM-dd HH:mm:ss'))
"@

        # Get unprocessed files
        $allFiles = Get-ChildItem -Path $config.BaseDir -Filter "full.md" -File -Recurse
        $pendingFiles = $allFiles | Where-Object { $_.FullName -notin $processedFiles }

        if (-not $pendingFiles) {
            Write-Host "All files already processed."
            $completed = $true
            break
        }

        Write-Host "Files remaining: $($pendingFiles.Count)"

        foreach ($mdFile in $pendingFiles) {
            $currentTime = Get-Date
            if ($currentTime -ge $timeoutDeadline) {
                Write-Host "[TIMEOUT] Cycle deadline reached at $($currentTime.ToString('HH:mm:ss'))"
                Write-Host "Suspending operations for 24 hours..."
                Start-CountdownTimer -Seconds (16*3600) -Message "Suspension Period"
                break
            }

            $timeRemaining = $timeoutDeadline - $currentTime
            Write-Host "`nProcessing $($mdFile.Name) [Remaining: $($timeRemaining.ToString('hh\:mm\:ss'))]"

            try {
                $processingEnv = Initialize-Processing $mdFile
                
                # Phase 1: File splitting
                Split-MarkdownFile -InputFile $mdFile -ProcessDir $processingEnv.ProcessDir
                
                # Phase 2: API Processing
                Invoke-LLMProcessing -ProcessDir $processingEnv.ProcessDir
                
                # Phase 3: File merging
                Merge-Files -ProcessDir $processingEnv.ProcessDir -OutputFile $processingEnv.OutputFile
                
                # Phase 4: Obsidian integration
                Create-ObsidianNotes -InputFile $processingEnv.OutputFile
                
                # Mark as processed
                $mdFile.FullName | Add-Content $processedLog -Encoding UTF8
                Write-Host "Successfully processed: $($mdFile.FullName)"
            }
            catch {
                Write-Host "Error processing $($mdFile.FullName): $_" -ForegroundColor Red
                $errorLog = @{
                    File        = $mdFile.FullName
                    Error       = $_.Exception.Message
                    Timestamp   = Get-Date -Format 'o'
                }
                $errorLog | ConvertTo-Json | Out-File "processing_errors.log" -Append
            }

            # Post-processing timeout check
            if ((Get-Date) -ge $timeoutDeadline) {
                Write-Host "[TIMEOUT] Post-processing timeout reached"
                Write-Host "Suspending operations for 24 hours..."
                Start-CountdownTimer -Seconds (16*3600) -Message "Suspension Period"
                break
            }
        }

        # Check completion status
        $remainingFiles = Get-ChildItem -Path $config.BaseDir -Filter "full.md" -File -Recurse |
            Where-Object { $_.FullName -notin (Get-Content $processedLog) }
        
        if (-not $remainingFiles) {
            Write-Host "`n[COMPLETION] All files processed successfully"
            $completed = $true
            
            # Run duplicate file deletion after successful completion
            Write-Host "`n[STARTING] Duplicate file cleanup in knowledge base"
            
            # Duplicate file detection and deletion logic
            $kbPath = $config.KnowledgeBase
            $kbFiles = @(Get-ChildItem -Path $kbPath -File -Filter *.md)
            $kbFilesToDelete = New-Object System.Collections.Generic.HashSet[string]
            
            # Plural Handling
            $kbFileNameLookup = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
            $kbFiles | ForEach-Object { [void]$kbFileNameLookup.Add($_.BaseName) }
            
            foreach ($file in $kbFiles) {
                $currentName = $file.BaseName
                $isPlural = $false
                
                if ($currentName.EndsWith('s', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $singularTest1 = $currentName.Substring(0, $currentName.Length - 1)
                    if ($kbFileNameLookup.Contains($singularTest1)) {
                        [void]$kbFilesToDelete.Add($file.FullName)
                        $isPlural = $true
                    }
                    
                    if (-not $isPlural -and $currentName.EndsWith('es', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $singularTest2 = $currentName.Substring(0, $currentName.Length - 2)
                        if ($kbFileNameLookup.Contains($singularTest2)) {
                            [void]$kbFilesToDelete.Add($file.FullName)
                            $isPlural = $true
                        }
                    }
                }
                
                if (-not $isPlural -and $currentName.EndsWith('ies', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $singularTest3 = $currentName.Substring(0, $currentName.Length - 3) + 'y'
                    if ($kbFileNameLookup.Contains($singularTest3)) {
                        [void]$kbFilesToDelete.Add($file.FullName)
                    }
                }
            }
            
            # Symbol Normalization Check
            $symbolGroups = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[string]]' ([System.StringComparer]::OrdinalIgnoreCase)
            
            foreach ($file in $kbFiles) {
                if ($kbFilesToDelete.Contains($file.FullName)) { continue }
                
                # Advanced text normalization
                $processedName = $file.BaseName -replace '-', ' ' -replace '[^\p{L}\p{N} ]', ''
                $processedName = $processedName -creplace '(?<=\p{Ll})(\p{Lu})', ' $1'    # camelCase
                $processedName = $processedName -creplace '(?<=\p{Lu})(\p{Lu}\p{Ll})', ' $1'  # PascalCase
                $processedName = $processedName -creplace '(\p{L})(\p{N})', '$1 $2'    # Letter-Number
                $processedName = $processedName -creplace '(\p{N})(\p{L})', '$1 $2'      # Number-Letter
                $processedName = $processedName.Trim() -replace '\s+', ' '
            
                # Remove duplicate words
                $words = $processedName -split ' '
                $seenWords = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
                $uniqueWords = [System.Collections.ArrayList]::new()
                
                foreach ($word in $words) {
                    $trimmedWord = $word.Trim()
                    if (-not [string]::IsNullOrWhiteSpace($trimmedWord)) {
                        if ($seenWords.Add($trimmedWord)) {
                            [void]$uniqueWords.Add($trimmedWord)
                        }
                    }
                }
                $normalized = $uniqueWords -join ' '
            
                if ([string]::IsNullOrEmpty($normalized)) {
                    $normalized = "EMPTY_FILENAME"
                }
            
                if (-not $symbolGroups.ContainsKey($normalized)) {
                    $symbolGroups[$normalized] = New-Object System.Collections.Generic.List[string]
                }
                $symbolGroups[$normalized].Add($file.FullName)
            }
            
            foreach ($group in $symbolGroups.Values) {
                if ($group.Count -gt 1) {
                    # Keep shortest filename, oldest creation time as tiebreaker
                    $sorted = $group | Sort-Object @{
                        Expression = {
                            [tuple]::Create(
                                (Get-Item $_).Name.Length,
                                (Get-Item $_).CreationTime
                            )
                        }
                    }
                    
                    if ($sorted.Count -gt 1) {
                        $sorted[1..($sorted.Count-1)] | ForEach-Object { 
                            [void]$kbFilesToDelete.Add($_) 
                        }
                    }
                }
            }
            
            # Multi-Word Containment Check
            $wordIndex = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.HashSet[string]]' ([System.StringComparer]::OrdinalIgnoreCase)
            
            foreach ($file in $kbFiles) {
                if ($kbFilesToDelete.Contains($file.FullName)) { continue }
                
                $words = $file.BaseName -split '\s+'
                foreach ($word in $words) {
                    if (-not $wordIndex.ContainsKey($word)) {
                        $wordIndex[$word] = New-Object System.Collections.Generic.HashSet[string]
                    }
                    [void]$wordIndex[$word].Add($file.FullName)
                }
            }
            
            foreach ($file in $kbFiles) {
                if ($kbFilesToDelete.Contains($file.FullName)) { continue }
                
                $currentWords = $file.BaseName -split '\s+'
                if ($currentWords.Count -lt 2) { continue }
            
                $candidateMatches = New-Object System.Collections.Generic.HashSet[string]
                foreach ($word in $currentWords) {
                    if ($wordIndex.ContainsKey($word)) {
                        $candidateMatches.UnionWith($wordIndex[$word])
                    }
                }
            
                foreach ($candidate in $candidateMatches) {
                    if ($candidate -eq $file.FullName) { continue }
                    $candidateFile = Get-Item $candidate
                    $candidateWords = $candidateFile.BaseName -split '\s+'
                    
                    $commonWords = [System.Linq.Enumerable]::Intersect(
                        [string[]]$currentWords,
                        [string[]]$candidateWords,
                        [System.StringComparer]::OrdinalIgnoreCase
                    )
                    
                    if ($commonWords.Count -ge 2 -and $file.Name.Length -lt $candidateFile.Name.Length) {
                        [void]$kbFilesToDelete.Add($file.FullName)
                        break
                    }
                }
            }
            
            # Single-Word Containment Check
            $singleWordFiles = $kbFiles | Where-Object {
                ($_.BaseName -split '\s+').Count -eq 1 -and
                -not $kbFilesToDelete.Contains($_.FullName)
            }
            
            foreach ($swFile in $singleWordFiles) {
                $searchWord = [regex]::Escape($swFile.BaseName)
                $containingFiles = $kbFiles | Where-Object {
                    $_.BaseName -match "\b$searchWord\b" -and
                    ($_.BaseName -split '\s+').Count -gt 1 -and
                    -not $kbFilesToDelete.Contains($_.FullName)
                }
                
                if ($containingFiles.Count -gt 0) {
                    [void]$kbFilesToDelete.Add($swFile.FullName)
                }
            }
            
            # Deletion Execution
            if ($kbFilesToDelete.Count -gt 0) {
                Write-Host "Found $($kbFilesToDelete.Count) duplicate files to delete"
                $kbFilesToDelete | ForEach-Object {
                    try {
                        Remove-Item $_ -Force -ErrorAction Stop
                        Write-Output "[DELETED] $_"
                    }
                    catch {
                        Write-Warning "[ERROR] $_ : $($_.Exception.Message)"
                    }
                }
            }
            else {
                Write-Output "No duplicate files found in knowledge base"
            }
        }
    }

    if (-not $completed) {
        Write-Host "`n[TERMINATION] Maximum cycles reached ($($SCHEDULE_CONFIG.MaxCycles))" -ForegroundColor Yellow
    }

    # Execute the DeleteDuplicates.ps1 script
    Write-Host "`n[STARTING] Running external duplicate cleanup script"
    try {
        # Run DeleteDuplicates.ps1 from the current directory
        & ".\DeleteDuplicates.ps1"
        Write-Host "[COMPLETED] External duplicate cleanup script executed successfully"
    }
    catch {
        Write-Host "[ERROR] Failed to execute external duplicate cleanup script: $_" -ForegroundColor Red
    }

    Write-Host "`n[FINAL STATUS]"
    Write-Host "Total files processed: $(@(Get-Content $processedLog).Count)"
    Write-Host "Errors logged in: processing_errors.log"

    exit 0
}
catch {
    Write-Host "Fatal error: $_" -ForegroundColor Red
    exit 1
}
