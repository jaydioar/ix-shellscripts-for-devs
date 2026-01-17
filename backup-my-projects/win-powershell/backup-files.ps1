# Parse command-line arguments in --key=value format
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$RemainingArgs
)

# Function to validate directory exists and is valid
function Test-DirectoryParameter {
    param(
        [string]$ParameterName,
        [string]$Path,
        [bool]$CreateIfNotExists = $false
    )
    
    if (-not $Path) {
        Write-Host "ERROR: $ParameterName parameter is required" -ForegroundColor Red
        exit 1
    }
    
    if (-not (Test-Path $Path)) {
        if ($CreateIfNotExists) {
            Write-Host "INFO: $ParameterName path does not exist, creating: $Path" -ForegroundColor Yellow
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
            Write-Host "SUCCESS: $ParameterName directory created: $Path" -ForegroundColor Green
        }
        else {
            Write-Host "ERROR: $ParameterName path does not exist: $Path" -ForegroundColor Red
            exit 1
        }
    }
    elseif (-not (Test-Path $Path -PathType Container)) {
        Write-Host "ERROR: $ParameterName path is not a directory: $Path" -ForegroundColor Red
        exit 1
    }
    else {
        Write-Host "SUCCESS: $ParameterName directory is valid: $Path" -ForegroundColor Green
    }
}

# Function to validate blacklist file
function Test-BlacklistFile {
    param(
        [string]$Path
    )
    
    if (-not $Path) {
        Write-Host "ERROR: --blacklist parameter is required" -ForegroundColor Red
        exit 1
    }
    
    if (-not (Test-Path $Path)) {
        Write-Host "INFO: Blacklist file does not exist, creating: $Path" -ForegroundColor Yellow
        
        $defaultContent = @"
# default for node.js projects
node_modules/*
.git/*
*.log
tmp/*
.env
.*.env
.env.*
dist/*
*.cache/*
*.bak

# default for nextjs projects
.next/*

# default for astro projects
.astro/*

# default for python projects
__pycache__/*
"@
        
        Set-Content -Path $Path -Value $defaultContent -Encoding UTF8
        Write-Host "SUCCESS: Blacklist file created with default rules: $Path" -ForegroundColor Green
    }
    else {
        Write-Host "SUCCESS: blacklist file exists: $Path" -ForegroundColor Green
    }
}

$src = $null
$dst = $null
$tmp = $null
$blacklist = $null
$dstPattern = $null
$dstRotation = $null
$requirePassword = $false
$pathTo7Zip = $null

# Debug: Show what arguments were received
Write-Host "DEBUG - Received arguments:" -ForegroundColor Magenta
for ($idx = 0; $idx -lt $RemainingArgs.Count; $idx++) {
    Write-Host "  [$idx] = '$($RemainingArgs[$idx])'" -ForegroundColor Magenta
}
Write-Host "" -ForegroundColor Magenta

# Parse arguments - handle multi-part values
$i = 0
while ($i -lt $RemainingArgs.Count) {
    $arg = $RemainingArgs[$i]
    
    if ($arg -match '^--src=(.+)$') {
        $src = $matches[1]
    }
    elseif ($arg -match '^--dst=(.+)$') {
        $dst = $matches[1]
    }
    elseif ($arg -match '^--tmp=(.+)$') {
        $tmp = $matches[1]
    }
    elseif ($arg -match '^--blacklist=(.+)$') {
        $blacklist = $matches[1]
    }
    elseif ($arg -match '^--dstPattern=(.+)$') {
        $dstPattern = $matches[1]
    }
    elseif ($arg -match '^--dstRotation=(.+)$') {
        $dstRotation = [int]$matches[1]
    }
    elseif ($arg -eq '--requirePassword') {
        $requirePassword = $true
    }
    elseif ($arg -match '^--pathTo7Zip=(.*)$') {
        $value = $matches[1]
        # Collect subsequent arguments that don't start with -- (they're part of this path)
        while (($i + 1) -lt $RemainingArgs.Count -and $RemainingArgs[$i + 1] -notmatch '^--') {
            $i++
            $value += " " + $RemainingArgs[$i]
        }
        $pathTo7Zip = $value
    }
    
    $i++
}

# Convert paths to absolute
if ($src) { $src = (Resolve-Path -Path $src -ErrorAction SilentlyContinue).Path }
if ($dst) { $dst = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($dst) }
if ($tmp) { $tmp = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($tmp) }
else {
    # If tmp is not defined, create a "tmp" folder in the current directory
    $tmp = Join-Path -Path $PWD -ChildPath "tmp"
}
if ($blacklist) { $blacklist = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($blacklist) }

# Set default dstPattern if not provided
if (-not $dstPattern -and $src) {
    $dstPattern = Split-Path -Path $src -Leaf
}

# Set default dstRotation
if (-not $dstRotation) {
    $dstRotation = 1000
}

# Store base pattern before adding timestamp
$basePattern = $dstPattern

# Add the current datetime to dstPattern
if ($dstPattern) {
    $datetimeSuffix = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $dstPattern = "$dstPattern-$datetimeSuffix.bak"
}

# Display parsed parameters
Write-Host "Parsed Parameters:" -ForegroundColor Cyan
Write-Host "  --src             = $src" -ForegroundColor Green
Write-Host "  --dst             = $dst" -ForegroundColor Green
Write-Host "  --tmp             = $tmp" -ForegroundColor Green
Write-Host "  --blacklist       = $blacklist" -ForegroundColor Green
Write-Host "  --dstPattern      = $dstPattern" -ForegroundColor Green
Write-Host "  --dstRotation     = $dstRotation" -ForegroundColor Green
Write-Host "  --requirePassword = $requirePassword" -ForegroundColor Green
Write-Host "  --pathTo7Zip    = $pathTo7Zip" -ForegroundColor Green

# Validate password requirement and 7-Zip
if ($requirePassword) {
    if (-not $pathTo7Zip) {
        Write-Host "ERROR: --pathTo7Zip parameter is required when --requirePassword is enabled" -ForegroundColor Red
        exit 1
    }
    
    # Convert pathTo7Zip to absolute path
    $pathTo7Zip = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($pathTo7Zip)
    
    # Check if 7-Zip directory exists
    if (-not (Test-Path ${pathTo7Zip})) {
        Write-Host "ERROR: 7-Zip directory does not exist: ${pathTo7Zip}" -ForegroundColor Red
        exit 1
    }
    
    # Check if 7z.exe exists
    ${pathToSevenZipExe} = Join-Path -Path ${pathTo7Zip} -ChildPath "7z.exe"
    if (-not (Test-Path ${pathToSevenZipExe})) {
        Write-Host "ERROR: 7z.exe not found in directory: ${pathTo7Zip}" -ForegroundColor Red
        exit 1
    }
        
    # Prompt for password
    Write-Host "`n`nGoing to use 7-ZIP with Password Protection Enabled`n`n" -ForegroundColor Yellow

    $securePassword = Read-Host "Please enter a password for the new 7-ZIP archive" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    
    if ([string]::IsNullOrEmpty($password)) {
        Write-Host "ERROR: Password cannot be empty" -ForegroundColor Red
        exit 1
    }
}

# Start timing
$totalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Validate directories
Write-Host "`nValidating directories..." -ForegroundColor Cyan
Test-DirectoryParameter -ParameterName "--src" -Path $src
Test-DirectoryParameter -ParameterName "--dst" -Path $dst -CreateIfNotExists $true
Test-DirectoryParameter -ParameterName "--tmp" -Path $tmp -CreateIfNotExists $true

# Validate blacklist file
Write-Host "`nValidating blacklist file..." -ForegroundColor Cyan
Test-BlacklistFile -Path $blacklist

# Read blacklist patterns
Write-Host "`nReading blacklist patterns..." -ForegroundColor Cyan
$blacklistPatterns = Get-Content -Path $blacklist | Where-Object { 
    $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") 
}
Write-Host "Loaded $($blacklistPatterns.Count) exclusion pattern(s)" -ForegroundColor Green

# Function to check if a path matches any blacklist pattern
function Test-IsExcluded {
    param(
        [string]$Path,
        [string]$BasePath,
        [string[]]$Patterns
    )
    
    $relativePath = $Path.Replace($BasePath, "").TrimStart("\", "/").Replace("\", "/")
    
    foreach ($pattern in $Patterns) {
        # Normalize pattern to use forward slashes
        $normalizedPattern = $pattern.Replace("\", "/")
        
        # Convert wildcard pattern to regex pattern
        $regexPattern = '^' + [regex]::Escape($normalizedPattern).Replace('\*', '.*').Replace('\?', '.') + '$'
        
        # Direct match using regex
        if ($relativePath -match $regexPattern) {
            return $true
        }
        
        # Check if file is within an excluded directory
        # For patterns like "node_modules/*", check if path contains "node_modules/"
        if ($normalizedPattern -match '^(.+)/\*$') {
            $dirPattern = [regex]::Escape($matches[1])
            $dirRegex = "(^|.+/)" + $dirPattern + "/"
            if ($relativePath -match $dirRegex) {
                return $true
            }
        }
    }
    
    return $false
}

# Function to check if a directory should be excluded from traversal
function Test-IsDirectoryExcluded {
    param(
        [string]$DirPath,
        [string]$BasePath,
        [string[]]$Patterns
    )
    
    $relativePath = $DirPath.Replace($BasePath, "").TrimStart("\", "/").Replace("\", "/")
    
    foreach ($pattern in $Patterns) {
        # Normalize pattern to use forward slashes
        $normalizedPattern = $pattern.Replace("\", "/")
        
        # For patterns like "node_modules/*" or ".git/*", check if this directory matches
        if ($normalizedPattern -match '^(.+)/\*$') {
            $dirPattern = [regex]::Escape($matches[1])
            # Check if this is the exact directory or a subdirectory of it
            if ($relativePath -match "^$dirPattern(/.*)?$") {
                return $true
            }
        }
        
        # Check if the directory itself is directly excluded
        # Convert wildcard pattern to regex pattern
        $regexPattern = '^' + [regex]::Escape($normalizedPattern).Replace('\*', '.*').Replace('\?', '.') + '$'
        if ($relativePath -match $regexPattern) {
            return $true
        }
    }
    
    return $false
}

# Recursive function to copy files while respecting directory exclusions
function Copy-FilesRecursive {
    param(
        [string]$CurrentPath,
        [string]$BasePath,
        [string]$DestinationBase,
        [string[]]$Patterns,
        [ref]$FileCount,
        [ref]$ExcludedCount
    )
    
    # Get all items in the current directory (non-recursive)
    # Use -LiteralPath to handle special characters like [], (), etc.
    Get-ChildItem -LiteralPath $CurrentPath | ForEach-Object {
        if ($_.PSIsContainer) {
            # It's a directory - check if it should be excluded
            if (Test-IsDirectoryExcluded -DirPath $_.FullName -BasePath $BasePath -Patterns $Patterns) {
                # Skip this directory entirely - don't traverse into it
                Write-Host "  Skipping directory: $($_.FullName.Replace($BasePath, '').TrimStart('\'))" -ForegroundColor DarkYellow
            }
            else {
                # Recurse into this directory
                Copy-FilesRecursive -CurrentPath $_.FullName -BasePath $BasePath -DestinationBase $DestinationBase -Patterns $Patterns -FileCount $FileCount -ExcludedCount $ExcludedCount
            }
        }
        else {
            # It's a file - check if it should be excluded
            if (-not (Test-IsExcluded -Path $_.FullName -BasePath $BasePath -Patterns $Patterns)) {
                $relativePath = $_.FullName.Replace($BasePath, "").TrimStart("\")
                $destinationPath = Join-Path -Path $DestinationBase -ChildPath $relativePath
                
                Copy-FileWithTiming -SourcePath $_.FullName -DestinationPath $destinationPath -RelativePath $relativePath
                $FileCount.Value++
            }
            else {
                $ExcludedCount.Value++
            }
        }
    }
}

# Function to copy a file and display timing information
function Copy-FileWithTiming {
    param(
        [string]$SourcePath,
        [string]$DestinationPath,
        [string]$RelativePath
    )
    
    # Ensure destination directory exists
    $destDir = Split-Path -Path $DestinationPath -Parent
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    }
    
    # Measure copy time
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
    $stopwatch.Stop()
    
    $copyTime = $stopwatch.Elapsed.TotalMilliseconds
    Write-Host "  $RelativePath" -ForegroundColor Gray -NoNewline
    Write-Host " ($($copyTime.ToString('0.00')) ms)" -ForegroundColor DarkGray
}

# Iterate through source directory and copy files
Write-Host "`nCopying files..." -ForegroundColor Cyan
$fileCount = 0
$excludedCount = 0

# Use the recursive function to copy files while respecting directory exclusions
Copy-FilesRecursive -CurrentPath $src -BasePath $src -DestinationBase $tmp -Patterns $blacklistPatterns -FileCount ([ref]$fileCount) -ExcludedCount ([ref]$excludedCount)

# ZIP the tmp directory to the destination
Write-Host "`nCreating backup archive..." -ForegroundColor Cyan

if ($requirePassword) {
    # Use 7-Zip with password protection
    $zipPath = Join-Path -Path $dst -ChildPath "$dstPattern.7z"
    if (Test-Path $zipPath) {
        Remove-Item -Path $zipPath -Force
    }
    
    ${7ZipExe} = Join-Path -Path ${pathTo7Zip} -ChildPath "7z.exe"
    $tmpPath = Join-Path -Path $tmp -ChildPath "*"
    
    # Run 7-Zip with password protection
    $arguments = "a", "-t7z", "-p$password", "-mhe=on", $zipPath, $tmpPath
    $process = Start-Process -FilePath ${7ZipExe} -ArgumentList $arguments -NoNewWindow -Wait -PassThru
    
    if ($process.ExitCode -eq 0) {
        Write-Host "SUCCESS: Password-protected backup archive created: $zipPath" -ForegroundColor Green
    }
    else {
        Write-Host "ERROR: Failed to create 7-Zip archive (Exit Code: $($process.ExitCode))" -ForegroundColor Red
        exit 1
    }
}
else {
    # Use standard Windows compression
    $zipPath = Join-Path -Path $dst -ChildPath "$dstPattern.zip"
    if (Test-Path $zipPath) {
        Remove-Item -Path $zipPath -Force
    }
    Compress-Archive -Path (Join-Path -Path $tmp -ChildPath "*") -DestinationPath $zipPath
    Write-Host "SUCCESS: Backup archive created: $zipPath" -ForegroundColor Green
}

# Rotate old backups
Write-Host "`nRotating old backups..." -ForegroundColor Cyan
$fileExtension = if ($requirePassword) { "7z" } else { "zip" }
$existingBackups = Get-ChildItem -Path $dst -Filter "$basePattern-*.bak.$fileExtension" | Sort-Object LastWriteTime -Descending
$backupCount = $existingBackups.Count

if ($backupCount -gt $dstRotation) {
    $toRemoveCount = $backupCount - $dstRotation
    $backupsToRemove = $existingBackups | Select-Object -Last $toRemoveCount
    
    foreach ($backup in $backupsToRemove) {
        Remove-Item -Path $backup.FullName -Force
        Write-Host "  Removed: $($backup.Name)" -ForegroundColor Yellow
    }
    Write-Host "Removed $toRemoveCount old backup(s), keeping $dstRotation most recent" -ForegroundColor Green
}
else {
    Write-Host "No rotation needed. Current backup count: $backupCount (max: $dstRotation)" -ForegroundColor Green
}

# Stop timing and display results
$totalStopwatch.Stop()
$totalSeconds = $totalStopwatch.Elapsed.TotalSeconds

Write-Host "`nBackup Summary:" -ForegroundColor Cyan
Write-Host "  Files copied:   $fileCount" -ForegroundColor Green
Write-Host "  Files excluded: $excludedCount" -ForegroundColor Yellow
Write-Host "  Total time:     $($totalSeconds.ToString('0.00')) seconds" -ForegroundColor Green

# Clean up tmp directory
Write-Host "`nCleaning up temporary files..." -ForegroundColor Cyan
if (Test-Path $tmp) {
    Remove-Item -Path $tmp -Recurse -Force
    Write-Host "SUCCESS: Temporary directory cleaned up: $tmp" -ForegroundColor Green
}
