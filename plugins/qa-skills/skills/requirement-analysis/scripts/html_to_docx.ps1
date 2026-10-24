# Converts the HTML report to .docx using the installed Microsoft Word (COM).
# Usage: powershell -ExecutionPolicy Bypass -File html_to_docx.ps1 -HtmlPath report.html -DocxPath 1234_Questions.docx
param(
    [Parameter(Mandatory = $true)][string]$HtmlPath,
    [Parameter(Mandatory = $true)][string]$DocxPath
)
$ErrorActionPreference = 'Stop'

$html = (Resolve-Path -LiteralPath $HtmlPath).Path
$out = [System.IO.Path]::GetFullPath($DocxPath)
$outDir = Split-Path -Parent $out
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
try {
    # Open(FileName, ConfirmConversions, ReadOnly)
    $doc = $word.Documents.Open($html, $false, $true)
    try { $doc.ActiveWindow.View.Type = 3 } catch {}   # wdPrintView, so the docx doesn't open in Web Layout
    $doc.SaveAs2($out, 16)                             # wdFormatDocumentDefault (.docx)
    $doc.Close(0)
}
finally {
    $word.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
}
Write-Output "Saved: $out"
