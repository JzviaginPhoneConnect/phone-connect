#!/bin/zsh
# ask_question.sh "Question" "Button A" "Button B" -> prints the chosen button (empty on Cancel)
# A small dialog with the app's own button labels (MessageBox only offers Yes/No).
source "${0:A:h}/_windows.sh"
PC_TEXT="$1" PC_B1="$2" PC_B2="$3" run_ps '
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object System.Windows.Forms.Form
$form.Text = "PhoneConnect $env:APP_VERSION"
$form.FormBorderStyle = "FixedDialog"
$form.StartPosition = "CenterScreen"
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.TopMost = $true
$form.AutoSize = $true
$form.AutoSizeMode = "GrowAndShrink"
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$ico = Join-Path $env:PC_APP_DIR "PhoneConnect.ico"
if ($env:PC_APP_DIR -and (Test-Path $ico)) { try { $form.Icon = New-Object System.Drawing.Icon $ico } catch {} }

$outer = New-Object System.Windows.Forms.FlowLayoutPanel
$outer.FlowDirection = "TopDown"
$outer.AutoSize = $true
$outer.AutoSizeMode = "GrowAndShrink"
$outer.Padding = New-Object System.Windows.Forms.Padding(16)

$label = New-Object System.Windows.Forms.Label
$label.Text = $env:PC_TEXT
$label.AutoSize = $true
$label.MaximumSize = New-Object System.Drawing.Size(400, 0)
$label.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 16)
$outer.Controls.Add($label)

$buttons = New-Object System.Windows.Forms.FlowLayoutPanel
$buttons.FlowDirection = "LeftToRight"
$buttons.AutoSize = $true
$buttons.AutoSizeMode = "GrowAndShrink"
$buttons.Anchor = "Right"
foreach ($caption in @("Cancel", $env:PC_B1, $env:PC_B2)) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $caption
  $b.AutoSize = $true
  $b.MinimumSize = New-Object System.Drawing.Size(100, 32)
  $b.Add_Click({ $f = $this.FindForm(); $f.Tag = $this.Text; $f.Close() })
  $buttons.Controls.Add($b)
  if ($caption -eq $env:PC_B2) { $form.AcceptButton = $b }
  if ($caption -eq "Cancel") { $form.CancelButton = $b }
}
$outer.Controls.Add($buttons)
$form.Controls.Add($outer)
$form.Add_Shown({ $this.Activate() })
[void]$form.ShowDialog()
$answer = [string]$form.Tag
$form.Dispose()
if ($answer -ne "Cancel") { [Console]::Out.Write($answer) }'
