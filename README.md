# new_folder

Create a folder from an existing directory template using a Windows PowerShell
form, optionally saving a Windows shortcut (`.lnk`) in another directory.

## Usage

Requires Windows and Windows PowerShell 5.1 (or PowerShell 7 on Windows).
Run from the repository directory:

```powershell
powershell.exe -STA -File .\New-Folder.ps1
```

You can prefill the paths and folder naming pattern:

```powershell
powershell.exe -STA -File .\New-Folder.ps1 `
    -TemplatePath 'C:\Templates\Project' `
    -DestinationPath 'C:\Projects' `
    -FolderNameTemplate '{Name} - {Description}' `
    -ShortcutPath 'C:\Users\Public\Desktop'
```

1. Enter a **Name** and, optionally, a **Description**.
2. Choose a **Folder name template**. The default is `{Name}`; for example,
   `{Name} - {Description}` produces `1234 - Office renovation`. Description
   is required when the pattern includes `{Description}`. Values are literal
   text, not PowerShell expressions.
3. Browse to an existing **Template directory** and **Destination directory**.
   The template's contents, including empty directories and hidden files, are
   copied into the new folder; the template itself is not modified.
4. Optionally select an existing **Shortcut directory**. Leave it blank to skip.
5. Click **Create**. The form reports the new folder's full path or an error.

Existing destination folders and shortcuts are never overwritten. Invalid Windows
folder names are rejected. The destination cannot be inside the template, and
templates containing symbolic links or junctions are rejected. Ensure you have
read access to the template and write access to the selected output directories.
Template and destination paths must not pass through symbolic links or junctions.
If copying fails, a partial folder may remain; inspect or remove it before
retrying. A shortcut failure does not delete the successfully created folder.

For command-line use without the form, dot-source the script and call its functions:

```powershell
. .\New-Folder.ps1
$folder = New-FolderFromTemplate -TemplatePath 'C:\Templates\Project' `
    -DestinationPath 'C:\Projects' -Name '1234' -Description 'Office renovation' `
    -FolderNameTemplate '{Name} - {Description}'
New-FolderShortcut -FolderPath $folder -ShortcutPath 'C:\Users\Public\Desktop'
```

There is no automated test framework configured in this repository. The folder
copying function can be exercised independently of the Windows-only form and
shortcut functionality.