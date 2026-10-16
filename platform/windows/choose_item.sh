#!/bin/zsh
# choose_item.sh "Question" "Default item" "Item 1" "Item 2"... -> prints the chosen item (empty on Cancel)
source "${0:A:h}/_windows.sh"
PC_TEXT="$1" PC_DEFAULT="$2" PC_ITEMS="${(pj:\n:)@[3,-1]}" run_ps '
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$items = @($env:PC_ITEMS -split "`n")
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
$label.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
$outer.Controls.Add($label)

$list = New-Object System.Windows.Forms.ListBox
$list.Name = "list"
$list.Font = $form.Font
$list.Width = 400
$list.IntegralHeight = $true
$list.Items.AddRange([object[]]$items)
$list.Height = [Math]::Min($items.Count, 10) * $list.ItemHeight + 6
$list.SelectedItem = $env:PC_DEFAULT
if ($list.SelectedIndex -lt 0) { $list.SelectedIndex = 0 }
$list.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 16)
$list.Add_DoubleClick({ $f = $this.FindForm(); $f.Tag = [string]$this.SelectedItem; $f.Close() })
$outer.Controls.Add($list)

$buttons = New-Object System.Windows.Forms.FlowLayoutPanel
$buttons.FlowDirection = "LeftToRight"
$buttons.AutoSize = $true
$buttons.AutoSizeMode = "GrowAndShrink"
$buttons.Anchor = "Right"
foreach ($caption in @("Cancel", "Connect")) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $caption
  $b.AutoSize = $true
  $b.MinimumSize = New-Object System.Drawing.Size(100, 32)
  if ($caption -eq "Connect") {
    $b.Add_Click({ $f = $this.FindForm(); $f.Tag = [string]$f.Controls.Find("list", $true)[0].SelectedItem; $f.Close() })
    $form.AcceptButton = $b
  } else {
    $b.Add_Click({ $f = $this.FindForm(); $f.Tag = ""; $f.Close() })
    $form.CancelButton = $b
  }
  $buttons.Controls.Add($b)
}
$outer.Controls.Add($buttons)
$form.Controls.Add($outer)
$form.Add_Shown({ $this.Activate() })
[void]$form.ShowDialog()
$answer = [string]$form.Tag
$form.Dispose()
[Console]::Out.Write($answer)'
