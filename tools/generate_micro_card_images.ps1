$ErrorActionPreference = "Stop"

# Generate 84px-high PNG thumbnails for missing pic/*.png files into pic/micro/.
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $projectRoot "pic"
$outputDir = Join-Path $sourceDir "micro"
$targetHeight = 84

if (-not (Test-Path $sourceDir)) {
	throw "Source directory not found: $sourceDir"
}

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

Add-Type -AssemblyName System.Drawing

$sourceFiles = Get-ChildItem -Path $sourceDir -File -Filter *.png | Sort-Object Name
$scanned = $sourceFiles.Count
$generated = 0
$skippedExisting = 0

foreach ($file in $sourceFiles) {
	$outputPath = Join-Path $outputDir $file.Name
	if (Test-Path $outputPath) {
		$skippedExisting++
		continue
	}

	$image = [System.Drawing.Image]::FromFile($file.FullName)
	try {
		if ($image.Height -le 0) {
			throw "Invalid image height for $($file.Name)"
		}

		$targetWidth = [Math]::Max(1, [int][Math]::Round($image.Width * $targetHeight / $image.Height))
		$bitmap = New-Object System.Drawing.Bitmap($targetWidth, $targetHeight)
		try {
			$bitmap.SetResolution($image.HorizontalResolution, $image.VerticalResolution)
			$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
			try {
				$graphics.Clear([System.Drawing.Color]::Transparent)
				$graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
				$graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
				$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
				$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
				$graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
				$graphics.DrawImage($image, 0, 0, $targetWidth, $targetHeight)
			}
			finally {
				$graphics.Dispose()
			}

			$bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
			$generated++
		}
		finally {
			$bitmap.Dispose()
		}
	}
	finally {
		$image.Dispose()
	}
}

Write-Output ("scanned={0} skipped_existing={1} generated={2} output_dir={3}" -f $scanned, $skippedExisting, $generated, $outputDir)
