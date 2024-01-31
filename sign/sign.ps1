param (
    [string]$versionTag
)

$baseURL = "https://github.com/wiresock/WireSockUI/releases/download/$versionTag/"
$files = @("WireSockUI-$versionTag-AnyCPU-no-uwp.zip", "WireSockUI-$versionTag-AnyCPU.zip", "WireSockUI-$versionTag-ARM64.zip")

foreach ($file in $files) {
    $downloadURL = $baseURL + $file
    $downloadPath = "./" + $file
    Invoke-WebRequest -Uri $downloadURL -OutFile $downloadPath

    # Correcting the folder name extraction
    $folderName = $file -replace ".zip", ""
    $extractPath = "./" + $folderName
    Expand-Archive -Path $downloadPath -DestinationPath $extractPath -Force
    Remove-Item -Path $downloadPath -Force

    $exePath = $extractPath + "/WireSockUI.exe"
    & signtool sign /fd sha1 /t http://timestamp.digicert.com /n "IP SMIRNOV VADIM VALERIEVICH" $exePath
    & signtool sign /as /td sha256 /fd sha256 /tr http://timestamp.digicert.com /n "IP SMIRNOV VADIM VALERIEVICH" $exePath

    # Change to the directory of the folder to be zipped
    Push-Location $extractPath

    # Get all items in the current directory (the extracted folder)
    $items = Get-ChildItem

    $zipPath = "../" + $folderName + ".zip"
    Compress-Archive -Path $items -DestinationPath $zipPath -Force

    # Return to the original directory
    Pop-Location
}
