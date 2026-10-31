#!/bin/zsh
# settings_form.sh "Text" "OK button" "Cancel button" "Label 1" "Default 1" "Bold item 1 (or "")"
#                  "Items 1 (one per line)" ["Label 2" ...]
#   -> the chosen item of each group, one per line (empty on Cancel)
# One window with a drop-down list per group.
source "${0:A:h}/_windows.sh"
typeset -i k=0
export PC_TEXT="$1" PC_OK="$2" PC_CANCEL="$3"
shift 3
while (( $# >= 4 )); do     # group k -> PC_LABEL_k, PC_DEFAULT_k, PC_BOLD_k, PC_ITEMS_k
  (( k++ ))
  export PC_LABEL_$k="$1" PC_DEFAULT_$k="$2" PC_BOLD_$k="$3" PC_ITEMS_$k="$4"
  shift 4
done
PC_COUNT=$k run_ps '
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
$label.MaximumSize = New-Object System.Drawing.Size(480, 0)
$label.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)
$outer.Controls.Add($label)

$grid = New-Object System.Windows.Forms.TableLayoutPanel
$grid.ColumnCount = 2
$grid.AutoSize = $true
$grid.AutoSizeMode = "GrowAndShrink"
$grid.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 16)
$boxes = @()
for ($k = 1; $k -le [int]$env:PC_COUNT; $k++) {
  $l = New-Object System.Windows.Forms.Label
  $l.Text = [Environment]::GetEnvironmentVariable("PC_LABEL_$k")
  $l.AutoSize = $true
  $l.Anchor = "Right"
  $grid.Controls.Add($l, 0, ($k - 1))
  $box = New-Object System.Windows.Forms.ComboBox
  $box.DropDownStyle = "DropDownList"
  $box.Width = 380
  $box.Font = $form.Font
  # owner-drawn, so the bold item can be bold
  $box.Tag = [Environment]::GetEnvironmentVariable("PC_BOLD_$k")
  $box.DrawMode = "OwnerDrawFixed"
  $box.Add_DrawItem({
    param($s, $e)
    $e.DrawBackground()
    if ($e.Index -ge 0) {
      $text = [string]$s.Items[$e.Index]
      $font = $e.Font
      if ($s.Tag -and $text -eq [string]$s.Tag) { $font = New-Object System.Drawing.Font($e.Font, [System.Drawing.FontStyle]::Bold) }
      [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $text, $font, $e.Bounds, $e.ForeColor, [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::Left)
    }
    $e.DrawFocusRectangle()
  })
  $items = @([Environment]::GetEnvironmentVariable("PC_ITEMS_$k") -split "`n")
  $box.Items.AddRange([object[]]$items)
  $box.SelectedItem = [Environment]::GetEnvironmentVariable("PC_DEFAULT_$k")
  if ($box.SelectedIndex -lt 0) { $box.SelectedIndex = 0 }
  $box.Margin = New-Object System.Windows.Forms.Padding(8, 4, 0, 4)
  $grid.Controls.Add($box, 1, ($k - 1))
  $boxes += $box
}
$outer.Controls.Add($grid)

$buttons = New-Object System.Windows.Forms.FlowLayoutPanel
$buttons.FlowDirection = "LeftToRight"
$buttons.AutoSize = $true
$buttons.AutoSizeMode = "GrowAndShrink"
$buttons.Anchor = "Right"
foreach ($caption in @($env:PC_CANCEL, $env:PC_OK)) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $caption
  $b.AutoSize = $true
  $b.MinimumSize = New-Object System.Drawing.Size(100, 32)
  $b.Add_Click({ $f = $this.FindForm(); $f.Tag = $this.Text; $f.Close() })
  $buttons.Controls.Add($b)
  if ($caption -eq $env:PC_OK) { $form.AcceptButton = $b } else { $form.CancelButton = $b }
}
$outer.Controls.Add($buttons)
$form.Controls.Add($outer)
$form.Add_Shown({ $this.Activate() })
[void]$form.ShowDialog()
$answer = [string]$form.Tag
$form.Dispose()
if ($answer -eq $env:PC_OK) {
  [Console]::Out.Write((($boxes | ForEach-Object { [string]$_.SelectedItem }) -join "`n"))
}'
