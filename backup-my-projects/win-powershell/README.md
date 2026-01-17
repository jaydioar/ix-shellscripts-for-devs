# Backup My Projects (Windows Powershell CLI tool)

This little utility helps you back up your projects by copying them to a specified backup directory. It supports multiple projects and can be easily configured.

## Features

- Simple command-line interface (for Windows PowerShell)
- Backup multiple projects at once
- Configurable backup directory
- Configurable exclusion patterns
- Zip compression of backups
- Rotation of old backups

## Usage

1. Open Windows Powershell
2. Navigate to the directory where `backup-my-projects.ps1` is located.
    ```powershell
    cd path\to\backup-my-projects\win-powershell
    ```
3. Run the script with the required parameters:
    ```powershell
    .\backup-my-projects.ps1 --src=C:\path\to\project51 --dst=D:\backups --dstPattern="project51-backup" --dstRotation=20 --requirePassword --pathTo7Zip="C:\Program Files\7-Zip"
    ```

## Parameters

| Param | Required | Default | Description |
|-------|----------|---------|-------------|
| `--src` | Yes | - | Source project directory to back up |
| `--dst` | Yes | - | Destination directory where backups will be stored |
| `--tmp` | No | `./tmp` | Temporary directory for file staging before compression |
| `--blacklist` | No | - | Path to blacklist file containing exclusion patterns. If not present then is generated with common rules for example to exclude `node_modules` and `*.tmp` files |
| `--dstPattern` | No | Last folder name of `--src` | Pattern for naming the backup files |
| `--dstRotation` | No | `3` | Number of backups to keep for each project |
| `--requirePassword` | No | `false` | Enable password protection for the archive (requires 7-Zip) |
| `--pathTo7Zip` | Maybe | - | Path to 7-Zip directory (required when `--requirePassword` is enabled as Powershells compress doesn't support password encryption) |
