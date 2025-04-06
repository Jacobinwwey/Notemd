# FileDeletionAutomation.ps1
# Usage: powershell -ExecutionPolicy Bypass -File FileDeletionAutomation.ps1

# Load .env file if it exists
function Import-DotEnv {
    param(
        [string]$EnvFile = ".env"
    )
    
    if (Test-Path $EnvFile) {
        Write-Host "Loading configuration from $EnvFile..." -ForegroundColor Cyan
        $envContent = Get-Content $EnvFile
        $totalLines = $envContent.Count
        $currentLine = 0
        
        foreach ($line in $envContent) {
            $currentLine++
            Write-Progress -Activity "Loading Environment Variables" -Status "Processing line $currentLine of $totalLines" -PercentComplete (($currentLine / $totalLines) * 100)
            
            if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                # Remove quotes if present
                if ($value -match '^["''](.*)["'']$') {
                    $value = $matches[1]
                }
                [Environment]::SetEnvironmentVariable($key, $value)
                Write-Verbose "Set environment variable: $key"
            }
        }
        Write-Progress -Activity "Loading Environment Variables" -Completed
        Write-Host "Configuration loaded successfully." -ForegroundColor Green
    }
    else {
        Write-Host "No .env file found at $EnvFile" -ForegroundColor Yellow
    }
}

# Load environment variables
Import-DotEnv

# Require environment variables
if (-not $env:KNOWLEDGE_BASE_PATH -or -not $env:SEARCH_PATH) {
    Write-Error "Missing required environment variables. Please configure KNOWLEDGE_BASE_PATH and SEARCH_PATH in .env file"
    exit 1
}
$deletePath = $env:KNOWLEDGE_BASE_PATH
$searchPath = $env:SEARCH_PATH
$allFiles = @(Get-ChildItem -Path $searchPath -File -Filter *.md -Recurse)
$filesToDelete = New-Object System.Collections.Generic.HashSet[string]

# Only consider files in the delete path for deletion
$deletePathFiles = @(Get-ChildItem -Path $deletePath -File -Filter *.md)
$deletePathFileSet = New-Object System.Collections.Generic.HashSet[string]
$deletePathFiles | ForEach-Object { [void]$deletePathFileSet.Add($_.FullName) }

#region Exact Filename Matching
# Create a dictionary to group files by their exact basename (case-insensitive)
$filenameGroups = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[string]]' ([System.StringComparer]::OrdinalIgnoreCase)

foreach ($file in $allFiles) {
    $basename = $file.BaseName
    if (-not $filenameGroups.ContainsKey($basename)) {
        $filenameGroups[$basename] = New-Object System.Collections.Generic.List[string]
    }
    $filenameGroups[$basename].Add($file.FullName)
}

# Check each file in the delete path for exact matches
foreach ($file in $deletePathFiles) {
    $basename = $file.BaseName
    
    # If this filename exists elsewhere in the search path
    if ($filenameGroups.ContainsKey($basename) -and $filenameGroups[$basename].Count -gt 1) {
        # Check if there's at least one file with the same name outside the delete path
        $filesOutsideDeletePath = $filenameGroups[$basename] | Where-Object { 
            $_ -ne $file.FullName -and -not $_.StartsWith($deletePath)
        }
        
        if ($filesOutsideDeletePath.Count -gt 0) {
            # Mark this file for deletion since it exists elsewhere
            [void]$filesToDelete.Add($file.FullName)
        }
    }
}
#endregion

#region Plural Handling with Dual ES Check
$fileNames = $allFiles | ForEach-Object { $_.BaseName }
$fileNameLookup = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$allFiles | ForEach-Object { [void]$fileNameLookup.Add($_.BaseName) }

foreach ($file in $deletePathFiles) {
    $currentName = $file.BaseName
    $isPlural = $false
    
    if ($currentName.EndsWith('s', [System.StringComparison]::OrdinalIgnoreCase)) {
        $singularTest1 = $currentName.Substring(0, $currentName.Length - 1)
        if ($fileNameLookup.Contains($singularTest1)) {
            [void]$filesToDelete.Add($file.FullName)
            $isPlural = $true
        }
        
        if (-not $isPlural -and $currentName.EndsWith('es', [System.StringComparison]::OrdinalIgnoreCase)) {
            $singularTest2 = $currentName.Substring(0, $currentName.Length - 2)
            if ($fileNameLookup.Contains($singularTest2)) {
                [void]$filesToDelete.Add($file.FullName)
                $isPlural = $true
            }
        }
    }
    
    if (-not $isPlural -and $currentName.EndsWith('ies', [System.StringComparison]::OrdinalIgnoreCase)) {
        $singularTest3 = $currentName.Substring(0, $currentName.Length - 3) + 'y'
        if ($fileNameLookup.Contains($singularTest3)) {
            [void]$filesToDelete.Add($file.FullName)
        }
    }
}
#endregion

#region Enhanced Symbol Normalization Check
$symbolGroups = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[string]]' ([System.StringComparer]::OrdinalIgnoreCase)

foreach ($file in $allFiles) {
    # Skip files that are already marked for deletion or not in delete path
    if ($filesToDelete.Contains($file.FullName) -or -not $deletePathFileSet.Contains($file.FullName)) { continue }
    
    # Advanced text normalization
    $processedName = $file.BaseName -replace '-', ' ' -replace '[^\p{L}\p{N} ]', ''
    $processedName = $processedName -creplace '(?<=\p{Ll})(\p{Lu})', ' $1'    # camelCase
    $processedName = $processedName -creplace '(?<=\p{Lu})(\p{Lu}\p{Ll})', ' $1'  # PascalCase
    $processedName = $processedName -creplace '(\p{L})(\p{N})', '$1 $2'    # Letter-Number
    $processedName = $processedName -creplace '(\p{N})(\p{L})', '$1 $2'      # Number-Letter
    $processedName = $processedName.Trim() -replace '\s+', ' '

    # Remove duplicate words (all occurrences after first)
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
        # Get files in the delete path that match this normalized group
        $deletePathMatches = $group | Where-Object { $deletePathFileSet.Contains($_) }
        
        foreach ($deleteFile in $deletePathMatches) {
            # Check if there's at least one file with the same normalized name outside the delete path
            $outsideMatches = $group | Where-Object { 
                $_ -ne $deleteFile -and -not $_.StartsWith($deletePath)
            }
            
            if ($outsideMatches.Count -gt 0) {
                [void]$filesToDelete.Add($deleteFile)
            }
        }
    }
}
#endregion

#region Multi-Word Containment Check
$wordIndex = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.HashSet[string]]' ([System.StringComparer]::OrdinalIgnoreCase)

foreach ($file in $allFiles) {
    $words = $file.BaseName -split '\s+'
    foreach ($word in $words) {
        if (-not $wordIndex.ContainsKey($word)) {
            $wordIndex[$word] = New-Object System.Collections.Generic.HashSet[string]
        }
        [void]$wordIndex[$word].Add($file.FullName)
    }
}

foreach ($file in $deletePathFiles) {
    if ($filesToDelete.Contains($file.FullName)) { continue }
    
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
        
        # Add error handling for missing files
        if (-not (Test-Path $candidate)) {
            Write-Warning "File not found: $candidate - skipping comparison"
            continue
        }
        
        $candidateFile = Get-Item $candidate
        $candidateWords = $candidateFile.BaseName -split '\s+'
        
        $commonWords = [System.Linq.Enumerable]::Intersect(
            [string[]]$currentWords,
            [string[]]$candidateWords,
            [System.StringComparer]::OrdinalIgnoreCase
        )
        
        if ($commonWords.Count -ge 2 -and $file.Name.Length -lt $candidateFile.Name.Length) {
            [void]$filesToDelete.Add($file.FullName)
            break
        }
    }
}
#endregion

#region Single-Word Containment Check
$singleWordFiles = $deletePathFiles | Where-Object {
    ($_.BaseName -split '\s+').Count -eq 1 -and
    -not $filesToDelete.Contains($_.FullName)
}

foreach ($swFile in $singleWordFiles) {
    $searchWord = [regex]::Escape($swFile.BaseName)
    $containingFiles = $allFiles | Where-Object {
        $_.BaseName -match "\b$searchWord\b" -and
        ($_.BaseName -split '\s+').Count -gt 1
    }
    
    if ($containingFiles.Count -gt 0) {
        [void]$filesToDelete.Add($swFile.FullName)
    }
}
#endregion

#region Deletion Execution
Write-Host "Starting duplicate file detection..." -ForegroundColor Cyan

Write-Host "[1/6] Loading files from search path..." -ForegroundColor Cyan
$allFiles = @(Get-ChildItem -Path $searchPath -File -Filter *.md -Recurse)
Write-Host "Found $($allFiles.Count) files in search path." -ForegroundColor Green

Write-Host "[2/6] Performing exact filename matching..." -ForegroundColor Cyan
Write-Host "Exact filename matching complete." -ForegroundColor Green

Write-Host "[3/6] Checking for plural variants..." -ForegroundColor Cyan
Write-Host "Plural variant checking complete." -ForegroundColor Green

Write-Host "[4/6] Performing symbol normalization checks..." -ForegroundColor Cyan
Write-Host "Symbol normalization complete." -ForegroundColor Green

Write-Host "[5/6] Checking multi-word containment..." -ForegroundColor Cyan
Write-Host "Multi-word containment checking complete." -ForegroundColor Green

Write-Host "[6/6] Checking single-word containment..." -ForegroundColor Cyan
Write-Host "Single-word containment checking complete." -ForegroundColor Green

#region Deletion Execution
Write-Host "Preparing to delete ${$filesToDelete.Count} duplicate files..." -ForegroundColor Yellow
if ($filesToDelete.Count -gt 0) {
    $totalFiles = $filesToDelete.Count
    $currentFile = 0
    
    $filesToDelete | ForEach-Object {
        $currentFile++
        $fileToDelete = $_
        Write-Progress -Activity "Deleting Duplicate Files" -Status "Processing file $currentFile of $totalFiles" -PercentComplete (($currentFile / $totalFiles) * 100)
        
        try {
            Remove-Item $fileToDelete -Force -ErrorAction Stop
            Write-Host "[DELETED] $fileToDelete" -ForegroundColor Green
        }
        catch {
            Write-Warning "[ERROR] $fileToDelete : $($_.Exception.Message)"
        }
    }
    Write-Progress -Activity "Deleting Duplicate Files" -Completed
    Write-Host "Deletion process complete. Removed $currentFile files." -ForegroundColor Green
}
else {
    Write-Host "No files required deletion" -ForegroundColor Green
}
#endregion
