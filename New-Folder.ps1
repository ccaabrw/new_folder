[CmdletBinding()]
param(
    [string]$TemplatePath,
    [string]$DestinationPath,
    [string]$FolderNameTemplate = '{Name}',
    [string]$ShortcutPath
)

function New-FolderFromTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TemplatePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Description,
        [string]$FolderNameTemplate = '{Name}'
    )

    $namePattern = $FolderNameTemplate.Replace('{Name}', '').Replace('{Description}', '')
    if ($namePattern -match '[{}]') {
        throw 'Only {Name} and {Description} are supported in the folder name template.'
    }
    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw 'Enter a name.'
    }
    if ($FolderNameTemplate.Contains('{Description}') -and [string]::IsNullOrWhiteSpace($Description)) {
        throw 'Enter a description when using {Description} in the folder name template.'
    }
    $values = @{ Name = $Name.Trim(); Description = $Description.Trim() }
    $folderName = [regex]::Replace($FolderNameTemplate, '\{(Name|Description)\}', {
        param($match)
        $values[$match.Groups[1].Value]
    })
    if ([string]::IsNullOrWhiteSpace($folderName) -or
        $folderName -match '[<>:"/\\|?*\x00-\x1f]' -or
        $folderName -match '[. ]$' -or
        $folderName -match '^(CON|PRN|AUX|NUL|COM[1-9\u00b9\u00b2\u00b3]|LPT[1-9\u00b9\u00b2\u00b3])(\.|$)') {
        throw 'The resulting folder name is not a valid Windows folder name.'
    }

    $template = Get-Item -LiteralPath $TemplatePath -Force -ErrorAction Stop
    $destination = Get-Item -LiteralPath $DestinationPath -Force -ErrorAction Stop
    if (-not ($template -is [System.IO.DirectoryInfo]) -or
        -not ($destination -is [System.IO.DirectoryInfo])) {
        throw 'Select existing template and destination directories.'
    }
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $templateRoot = $template.FullName.TrimEnd($separator) + $separator
    $destinationRoot = $destination.FullName.TrimEnd($separator) + $separator
    if ($destinationRoot.StartsWith($templateRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'The destination must not be the template directory or one of its subdirectories.'
    }
    foreach ($directory in @($template, $destination)) {
        for ($ancestor = $directory; $null -ne $ancestor; $ancestor = $ancestor.Parent) {
            if ($ancestor.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                throw 'Template and destination paths must not pass through symbolic links or junctions.'
            }
        }
    }
    # Reject links and junctions so copying cannot escape the selected template.
    $linkedItem = @($template) + @(Get-ChildItem -LiteralPath $template.FullName -Recurse -Force -ErrorAction Stop) |
        Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint } |
        Select-Object -First 1
    if ($linkedItem) {
        throw 'The template must not contain symbolic links or junctions.'
    }

    $folderPath = Join-Path -Path $destination.FullName -ChildPath $folderName
    if (Test-Path -LiteralPath $folderPath) {
        throw "The destination already exists: $folderPath"
    }
    New-Item -ItemType Directory -Path $folderPath -ErrorAction Stop | Out-Null
    try {
        Get-ChildItem -LiteralPath $template.FullName -Force -ErrorAction Stop |
            Copy-Item -Destination $folderPath -Recurse -Force -ErrorAction Stop
    }
    catch {
        throw "Copy failed. A partial folder may remain at '$folderPath'. $($_.Exception.Message)"
    }
    return $folderPath
}

function New-FolderShortcut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FolderPath,
        [Parameter(Mandatory = $true)][string]$ShortcutPath
    )

    $location = Get-Item -LiteralPath $ShortcutPath -Force -ErrorAction Stop
    if (-not ($location -is [System.IO.DirectoryInfo])) {
        throw 'Select an existing shortcut directory.'
    }
    $linkPath = Join-Path $location.FullName ((Split-Path $FolderPath -Leaf) + '.lnk')
    if (Test-Path -LiteralPath $linkPath) {
        throw "A shortcut already exists: $linkPath"
    }
    $shell = New-Object -ComObject WScript.Shell -ErrorAction Stop
    try {
        $link = $shell.CreateShortcut($linkPath)
        $link.TargetPath = $FolderPath
        $link.WorkingDirectory = $FolderPath
        $link.Save()
    }
    finally {
        if ($null -ne $link) {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($link) | Out-Null
        }
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
    }
}

function Show-NewFolderForm {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'The form requires Windows. Use Windows PowerShell with -STA.'
    }
    if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        throw 'Start PowerShell with -STA to use the folder selection dialogs.'
    }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Create folder from template'
    $form.ClientSize = New-Object System.Drawing.Size(660, 340)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.StartPosition = 'CenterScreen'
    $form.AutoScaleMode = 'Font'
    $fields = @{}
    $labels = @('Name', 'Description', 'Folder name template', 'Template directory', 'Destination directory', 'Shortcut directory')
    $keys = @('Name', 'Description', 'FolderNameTemplate', 'TemplatePath', 'DestinationPath', 'ShortcutPath')
    $defaults = @('', '', $FolderNameTemplate, $TemplatePath, $DestinationPath, $ShortcutPath)
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $labels[$i]
        $label.SetBounds(12, (18 + $i * 40), 155, 23)
        $form.Controls.Add($label)
        $textBox = New-Object System.Windows.Forms.TextBox
        $textBox.SetBounds(170, (15 + $i * 40), 380, 23)
        $textBox.Text = $defaults[$i]
        $fields[$keys[$i]] = $textBox
        $form.Controls.Add($textBox)
        if ($i -ge 3) {
            $browse = New-Object System.Windows.Forms.Button
            $browse.Text = 'Browse...'
            $browse.SetBounds(560, (13 + $i * 40), 88, 27)
            $browse.Tag = $textBox
            $browse.Add_Click({
                param($sender, $eventArgs)
                $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
                try {
                    $dialog.SelectedPath = $sender.Tag.Text
                    if ($dialog.ShowDialog($form) -eq 'OK') {
                        $sender.Tag.Text = $dialog.SelectedPath
                    }
                }
                finally {
                    $dialog.Dispose()
                }
            })
            $form.Controls.Add($browse)
        }
    }
    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = 'Use {Name} and/or {Description}. Leave shortcut directory blank to skip.'
    $hint.SetBounds(12, 258, 636, 25)
    $form.Controls.Add($hint)
    $create = New-Object System.Windows.Forms.Button
    $create.Text = 'Create'
    $create.SetBounds(460, 297, 90, 30)
    $form.Controls.Add($create)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Close'
    $cancel.DialogResult = 'Cancel'
    $cancel.SetBounds(558, 297, 90, 30)
    $form.Controls.Add($cancel)
    $form.AcceptButton = $create
    $form.CancelButton = $cancel
    $create.Add_Click({
        $create.Enabled = $false
        try {
            $arguments = @{}
            foreach ($key in @('Name', 'Description', 'FolderNameTemplate', 'TemplatePath', 'DestinationPath')) {
                $arguments[$key] = $fields[$key].Text
            }
            $createdPath = New-FolderFromTemplate @arguments
            if (-not [string]::IsNullOrWhiteSpace($fields.ShortcutPath.Text)) {
                try {
                    New-FolderShortcut -FolderPath $createdPath -ShortcutPath $fields.ShortcutPath.Text
                }
                catch {
                    [System.Windows.Forms.MessageBox]::Show($form,
                        "Folder created at '$createdPath', but the shortcut could not be saved: $($_.Exception.Message)",
                        'Shortcut failed', 'OK', 'Warning') | Out-Null
                    return
                }
            }
            [System.Windows.Forms.MessageBox]::Show($form, "Folder created at '$createdPath'.",
                'Folder created', 'OK', 'Information') | Out-Null
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message,
                'Unable to create folder', 'OK', 'Error') | Out-Null
        }
        finally {
            $create.Enabled = $true
        }
    })
    try {
        $form.ShowDialog() | Out-Null
    }
    finally {
        $form.Dispose()
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Show-NewFolderForm
}
