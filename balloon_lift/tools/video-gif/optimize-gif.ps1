[CmdletBinding()]
param(
    [string]$Source,
    [string]$Output,
    [ValidateRange(16, 4096)]
    [int]$Width = 720,
    [ValidateRange(16, 4096)]
    [int]$Height = 405,
    [ValidateRange(1, 50)]
    [int]$FrameRate = 7,
    [ValidateRange(1024, 2147483647)]
    [int]$MaxBytes = 2000000,
    [ValidateRange(0, 1000000)]
    [int]$SafetyBytes = 10000,
    [ValidateRange(2, 256)]
    [int]$ColorsPerScene = 96,
    [ValidateRange(1, 50)]
    [int]$SceneCount = 5,
    [ValidateRange(0.1, 10.0)]
    [double]$MinimumSceneSeconds = 0.5,
    [ValidateSet('bayer', 'none', 'sierra2_4a', 'floyd_steinberg')]
    [string]$Dither = 'bayer',
    [ValidateRange(0, 5)]
    [int]$BayerScale = 3,
    [ValidateRange(0, 10)]
    [double]$EdgeBlurSigma = 1.25,
    [ValidateRange(0, 1)]
    [double]$EdgeSharpRadius = 0.60,
    [ValidateRange(0.01, 1)]
    [double]$EdgeBlendWidth = 0.35,
    [ValidateRange(0, 1000)]
    [int]$MaximumLossiness = 400,
    [switch]$DisableEdgeReduction,
    [switch]$KeepWorkFiles,
    [switch]$Force,
    [string]$DependencyCache
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$invariantCulture = [Globalization.CultureInfo]::InvariantCulture

function Format-InvariantNumber {
    param([double]$Value)

    return $Value.ToString('0.######', $invariantCulture)
}

function Format-ByteCount {
    param([long]$Bytes)

    return ('{0:N0}' -f $Bytes)
}

function Invoke-NativeTool {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [string]$Description = 'Native tool'
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE."
    }
}

function Invoke-NativeToolQuietly {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [string]$Description = 'Native tool'
    )

    $messages = & $FilePath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $details = $messages -join [Environment]::NewLine
        throw "$Description failed with exit code $LASTEXITCODE.`n$details"
    }

    return $messages
}

function Save-RemoteFile {
    param(
        [Parameter(Mandatory)]
        [string]$Uri,
        [Parameter(Mandatory)]
        [string]$Destination
    )

    $destinationDirectory = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null

    $temporaryDownload = Join-Path $destinationDirectory (
        [IO.Path]::GetFileName($Destination) + '.' + [guid]::NewGuid().ToString('N') + '.download'
    )

    try {
        Write-Host "Downloading $Uri"
        Invoke-WebRequest -Uri $Uri -OutFile $temporaryDownload
        Move-Item -LiteralPath $temporaryDownload -Destination $Destination
    } finally {
        if (Test-Path -LiteralPath $temporaryDownload) {
            Remove-Item -LiteralPath $temporaryDownload -Force
        }
    }
}

function Get-FfmpegTools {
    param([Parameter(Mandatory)][string]$CacheRoot)

    $ffmpegRoot = Join-Path $CacheRoot 'ffmpeg-9.0.1'
    $ffmpeg = Get-ChildItem -LiteralPath $ffmpegRoot -Recurse -Filter 'ffmpeg.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName

    if ($null -eq $ffmpeg) {
        New-Item -ItemType Directory -Force -Path $ffmpegRoot | Out-Null
        $archive = Join-Path $CacheRoot 'downloads\ffmpeg-9.0.1-essentials_build.zip'
        if (-not (Test-Path -LiteralPath $archive)) {
            Save-RemoteFile `
                -Uri 'https://www.gyan.dev/ffmpeg/builds/packages/ffmpeg-9.0.1-essentials_build.zip' `
                -Destination $archive
        }

        $extractDirectory = Join-Path $ffmpegRoot ('extract-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $extractDirectory | Out-Null
        Write-Host 'Extracting FFmpeg...'
        Expand-Archive -LiteralPath $archive -DestinationPath $extractDirectory

        $ffmpeg = Get-ChildItem -LiteralPath $extractDirectory -Recurse -Filter 'ffmpeg.exe' |
            Select-Object -First 1 -ExpandProperty FullName
        if ($null -eq $ffmpeg) {
            throw "ffmpeg.exe was not found after extracting $archive."
        }
    }

    $ffprobe = Join-Path (Split-Path -Parent $ffmpeg) 'ffprobe.exe'
    if (-not (Test-Path -LiteralPath $ffprobe)) {
        throw "ffprobe.exe was not found next to $ffmpeg."
    }

    Invoke-NativeToolQuietly -FilePath $ffmpeg -Arguments @('-version') -Description 'FFmpeg version check' | Out-Null

    return [pscustomobject]@{
        Ffmpeg = $ffmpeg
        Ffprobe = $ffprobe
    }
}

function Get-GifsicleTool {
    param([Parameter(Mandatory)][string]$CacheRoot)

    $architecture = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    $gifsicleDirectory = Join-Path $CacheRoot 'gifsicle-1.93'
    $gifsicle = Join-Path $gifsicleDirectory 'gifsicle.exe'

    if (-not (Test-Path -LiteralPath $gifsicle)) {
        New-Item -ItemType Directory -Force -Path $gifsicleDirectory | Out-Null
        $uri = "https://raw.githubusercontent.com/imagemin/gifsicle-bin/v7.0.1/vendor/win/$architecture/gifsicle.exe"
        Save-RemoteFile -Uri $uri -Destination $gifsicle
    }

    Invoke-NativeToolQuietly -FilePath $gifsicle -Arguments @('--version') -Description 'Gifsicle version check' | Out-Null
    return $gifsicle
}

function Get-VideoDuration {
    param(
        [Parameter(Mandatory)][string]$Ffprobe,
        [Parameter(Mandatory)][string]$InputPath
    )

    $probeOutput = & $Ffprobe `
        -v error `
        -show_entries format=duration `
        -of json `
        $InputPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read video duration.`n$($probeOutput -join [Environment]::NewLine)"
    }

    $probe = ($probeOutput -join [Environment]::NewLine) | ConvertFrom-Json
    $durationText = [string]$probe.format.duration
    $duration = [double]::Parse($durationText, $invariantCulture)
    if ($duration -le 0) {
        throw "Invalid video duration: $durationText"
    }

    return $duration
}

function Get-SceneBoundaries {
    param(
        [Parameter(Mandatory)][string]$Ffmpeg,
        [Parameter(Mandatory)][string]$FramePattern,
        [Parameter(Mandatory)][int]$FramesPerSecond,
        [Parameter(Mandatory)][int]$FrameCount,
        [Parameter(Mandatory)][int]$NumberOfScenes,
        [Parameter(Mandatory)][double]$MinimumSeconds
    )

    if ($NumberOfScenes -eq 1) {
        return @()
    }
    if ($NumberOfScenes -gt $FrameCount) {
        throw "SceneCount ($NumberOfScenes) cannot exceed the number of GIF frames ($FrameCount)."
    }

    $detectArguments = @(
        '-hide_banner',
        '-loglevel', 'info',
        '-framerate', [string]$FramesPerSecond,
        '-start_number', '1',
        '-i', $FramePattern,
        '-vf', "select='gte(scene,0)',metadata=print",
        '-f', 'null',
        'NUL'
    )
    $detectOutput = & $Ffmpeg @detectArguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Scene detection failed.`n$($detectOutput -join [Environment]::NewLine)"
    }

    $scores = @()
    $currentFrame = -1
    foreach ($line in $detectOutput) {
        $text = [string]$line
        if ($text -match 'frame:(\d+)\s+pts:') {
            $currentFrame = [int]$Matches[1]
        } elseif ($currentFrame -ge 0 -and $text -match 'lavfi\.scene_score=([0-9.]+)') {
            $scores += [pscustomobject]@{
                Frame = $currentFrame
                Score = [double]::Parse($Matches[1], $invariantCulture)
            }
        }
    }

    $requiredCuts = $NumberOfScenes - 1
    $minimumFrames = [Math]::Max(2, [Math]::Floor($FramesPerSecond * $MinimumSeconds))
    $selected = New-Object 'System.Collections.Generic.List[int]'

    foreach ($candidate in ($scores | Sort-Object Score -Descending)) {
        if ($candidate.Frame -lt $minimumFrames) {
            continue
        }
        if (($FrameCount - $candidate.Frame) -lt $minimumFrames) {
            continue
        }

        $tooClose = $false
        foreach ($existing in $selected) {
            if ([Math]::Abs($existing - $candidate.Frame) -lt $minimumFrames) {
                $tooClose = $true
                break
            }
        }
        if ($tooClose) {
            continue
        }

        $selected.Add($candidate.Frame)
        if ($selected.Count -eq $requiredCuts) {
            break
        }
    }

    if ($selected.Count -ne $requiredCuts) {
        Write-Warning 'Scene detection did not find enough well-separated cuts; using equal-length scene groups.'
        $selected.Clear()
        for ($index = 1; $index -lt $NumberOfScenes; $index++) {
            $selected.Add([Math]::Round($FrameCount * $index / $NumberOfScenes))
        }
    }

    return @($selected | Sort-Object)
}

function Get-OptimizedGif {
    param(
        [Parameter(Mandatory)][string]$Gifsicle,
        [Parameter(Mandatory)][string]$InputGif,
        [Parameter(Mandatory)][string]$WorkDirectory,
        [Parameter(Mandatory)][int]$TargetBytes,
        [Parameter(Mandatory)][int]$MaximumAllowedLossiness
    )

    function Encode-Candidate {
        param([int]$Lossiness)

        $candidatePath = Join-Path $WorkDirectory ("candidate-lossy-$Lossiness.gif")
        if (-not (Test-Path -LiteralPath $candidatePath)) {
            $arguments = @('-O3')
            if ($Lossiness -gt 0) {
                $arguments += "--lossy=$Lossiness"
            }
            $arguments += @($InputGif, '-o', $candidatePath)
            Invoke-NativeToolQuietly `
                -FilePath $Gifsicle `
                -Arguments $arguments `
                -Description "Gifsicle candidate (lossy=$Lossiness)" | Out-Null
        }

        return [pscustomobject]@{
            Path = $candidatePath
            Lossiness = $Lossiness
            Bytes = (Get-Item -LiteralPath $candidatePath).Length
        }
    }

    $lossless = Encode-Candidate -Lossiness 0
    Write-Host "Lossless -O3: $(Format-ByteCount $lossless.Bytes) bytes"
    if ($lossless.Bytes -le $TargetBytes) {
        return $lossless
    }

    $maximum = Encode-Candidate -Lossiness $MaximumAllowedLossiness
    if ($maximum.Bytes -gt $TargetBytes) {
        throw (
            "The GIF is still $(Format-ByteCount $maximum.Bytes) bytes at lossy=$MaximumAllowedLossiness. " +
            'Lower Width, Height, FrameRate, or ColorsPerScene.'
        )
    }

    $low = 1
    $high = $MaximumAllowedLossiness
    $best = $maximum
    while ($low -le $high) {
        $middle = [Math]::Floor(($low + $high) / 2)
        $candidate = Encode-Candidate -Lossiness $middle
        Write-Host "  lossy=$middle -> $(Format-ByteCount $candidate.Bytes) bytes"

        if ($candidate.Bytes -le $TargetBytes) {
            $best = $candidate
            $high = $middle - 1
        } else {
            $low = $middle + 1
        }
    }

    return $best
}

function Assert-GifOutput {
    param(
        [Parameter(Mandatory)][string]$Ffprobe,
        [Parameter(Mandatory)][string]$Gifsicle,
        [Parameter(Mandatory)][string]$GifPath,
        [Parameter(Mandatory)][int]$ExpectedWidth,
        [Parameter(Mandatory)][int]$ExpectedHeight,
        [Parameter(Mandatory)][int]$MaximumBytes
    )

    $bytes = (Get-Item -LiteralPath $GifPath).Length
    if ($bytes -gt $MaximumBytes) {
        throw "Output is $(Format-ByteCount $bytes) bytes, which exceeds the $MaximumBytes-byte limit."
    }

    $probeOutput = & $Ffprobe `
        -v error `
        -count_frames `
        -select_streams 'v:0' `
        -show_entries 'stream=width,height,r_frame_rate,nb_read_frames,duration' `
        -of json `
        $GifPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to verify the output GIF.`n$($probeOutput -join [Environment]::NewLine)"
    }

    $probe = ($probeOutput -join [Environment]::NewLine) | ConvertFrom-Json
    $stream = $probe.streams[0]
    if ($stream.width -ne $ExpectedWidth -or $stream.height -ne $ExpectedHeight) {
        throw "Unexpected GIF size: $($stream.width)x$($stream.height)."
    }

    $gifInfo = & $Gifsicle --info $GifPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Gifsicle could not read the output GIF.`n$($gifInfo -join [Environment]::NewLine)"
    }
    if (($gifInfo -join "`n") -notmatch 'loop forever') {
        throw 'The output GIF is not configured to loop forever.'
    }

    return [pscustomobject]@{
        Bytes = $bytes
        Frames = [int]$stream.nb_read_frames
        Duration = [double]::Parse([string]$stream.duration, $invariantCulture)
        FrameRate = [string]$stream.r_frame_rate
    }
}

if ([string]::IsNullOrWhiteSpace($Source)) {
    $documents = [Environment]::GetFolderPath('MyDocuments')
    $Source = Join-Path $documents 'resolve\Timeline 1.mp4'
}

if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
    throw "Source video was not found: $Source"
}
$Source = (Resolve-Path -LiteralPath $Source).Path

if ([string]::IsNullOrWhiteSpace($Output)) {
    $sourceDirectory = Split-Path -Parent $Source
    $sourceName = [IO.Path]::GetFileNameWithoutExtension($Source)
    $Output = Join-Path $sourceDirectory ($sourceName + '_optimized_under_2MB.gif')
} else {
    $Output = [IO.Path]::GetFullPath($Output)
}

if ([IO.Path]::GetExtension($Output) -ne '.gif') {
    throw "Output must have a .gif extension: $Output"
}
if ($Output -eq $Source) {
    throw 'Source and Output must be different files.'
}
if ((Test-Path -LiteralPath $Output) -and -not $Force) {
    throw "Output already exists: $Output`nPass -Force to replace it."
}

$outputDirectory = Split-Path -Parent $Output
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}

if ([string]::IsNullOrWhiteSpace($DependencyCache)) {
    $DependencyCache = Join-Path $env:LOCALAPPDATA 'BalloonLift\GifOptimizer'
}
$DependencyCache = [IO.Path]::GetFullPath($DependencyCache)
New-Item -ItemType Directory -Force -Path $DependencyCache | Out-Null

$targetBytes = $MaxBytes - $SafetyBytes
if ($targetBytes -le 0) {
    throw 'SafetyBytes must be smaller than MaxBytes.'
}

$tools = Get-FfmpegTools -CacheRoot $DependencyCache
$gifsicle = Get-GifsicleTool -CacheRoot $DependencyCache

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) 'BalloonLiftGifOptimizer'
New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null
$workDirectory = Join-Path $temporaryRoot ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workDirectory | Out-Null

try {
    $duration = Get-VideoDuration -Ffprobe $tools.Ffprobe -InputPath $Source
    Write-Host "Source: $Source"
    Write-Host "Duration: $(Format-InvariantNumber $duration)s"
    Write-Host "Target: ${Width}x${Height}, $FrameRate fps, $SceneCount scene palettes, <= $(Format-ByteCount $MaxBytes) bytes"

    $framesDirectory = Join-Path $workDirectory 'frames'
    New-Item -ItemType Directory -Path $framesDirectory | Out-Null
    $framePattern = Join-Path $framesDirectory 'frame_%06d.png'

    if ($DisableEdgeReduction -or $EdgeBlurSigma -eq 0) {
        $frameFilter = "fps=$FrameRate,scale=${Width}:${Height}:flags=lanczos"
    } else {
        $sigma = Format-InvariantNumber $EdgeBlurSigma
        $sharpRadius = Format-InvariantNumber $EdgeSharpRadius
        $blendWidth = Format-InvariantNumber $EdgeBlendWidth
        # Keep the generated mask exactly as long as the input. A longer mask
        # makes framesync repeat the final video frame before the GIF loops.
        $maskDuration = Format-InvariantNumber $duration
        $maskExpression = "255*clip((hypot((X-W/2)/(W/2),(Y-H/2)/(H/2))-$sharpRadius)/$blendWidth,0,1)"
        $frameFilter = (
            "fps=$FrameRate,scale=${Width}:${Height}:flags=lanczos,format=yuv444p,split[sharp][toBlur];" +
            "[toBlur]gblur=sigma=$sigma[blurred];" +
            "nullsrc=s=${Width}x${Height}:r=${FrameRate}:d=$maskDuration,format=yuv444p," +
            "geq=lum='$maskExpression':cb='$maskExpression':cr='$maskExpression'[mask];" +
            '[sharp][blurred][mask]maskedmerge'
        )
    }

    Write-Host 'Rendering GIF frames...'
    Invoke-NativeTool `
        -FilePath $tools.Ffmpeg `
        -Arguments @(
            '-hide_banner', '-loglevel', 'error', '-y',
            '-i', $Source,
            '-filter_complex', $frameFilter,
            '-fps_mode', 'passthrough',
            $framePattern
        ) `
        -Description 'Frame rendering'

    $frameCount = @(Get-ChildItem -LiteralPath $framesDirectory -Filter 'frame_*.png').Count
    if ($frameCount -lt 1) {
        throw 'FFmpeg did not render any frames.'
    }
    Write-Host "Rendered frames: $frameCount"

    $boundaries = Get-SceneBoundaries `
        -Ffmpeg $tools.Ffmpeg `
        -FramePattern $framePattern `
        -FramesPerSecond $FrameRate `
        -FrameCount $frameCount `
        -NumberOfScenes $SceneCount `
        -MinimumSeconds $MinimumSceneSeconds

    if ($boundaries.Count -gt 0) {
        $boundarySummary = $boundaries | ForEach-Object {
            "frame $_ ($(Format-InvariantNumber ($_ / $FrameRate))s)"
        }
        Write-Host "Scene starts: $($boundarySummary -join ', ')"
    }

    $sceneStarts = @(0) + @($boundaries)
    $sceneEnds = @($boundaries) + @($frameCount)
    $sceneFiles = @()
    $paletteUse = if ($Dither -eq 'bayer') {
        "paletteuse=dither=bayer:bayer_scale=$BayerScale`:diff_mode=rectangle"
    } else {
        "paletteuse=dither=$Dither`:diff_mode=rectangle"
    }

    Write-Host 'Encoding and optimizing scene palettes...'
    for ($sceneIndex = 0; $sceneIndex -lt $sceneStarts.Count; $sceneIndex++) {
        $sceneNumber = $sceneIndex + 1
        $startFrame = [int]$sceneStarts[$sceneIndex]
        $sceneFrameCount = [int]$sceneEnds[$sceneIndex] - $startFrame
        if ($sceneFrameCount -le 0) {
            throw "Scene $sceneNumber has no frames."
        }

        $fileStartNumber = $startFrame + 1
        $rawScene = Join-Path $workDirectory ("scene-$sceneNumber-raw.gif")
        $optimizedScene = Join-Path $workDirectory ("scene-$sceneNumber-O3.gif")
        $sceneFilter = (
            "[0:v]trim=end_frame=$sceneFrameCount,setpts=N/(${FrameRate}*TB),split[s0][s1];" +
            "[s0]palettegen=max_colors=${ColorsPerScene}:stats_mode=diff[p];" +
            "[s1][p]$paletteUse"
        )

        Invoke-NativeTool `
            -FilePath $tools.Ffmpeg `
            -Arguments @(
                '-hide_banner', '-loglevel', 'error', '-y',
                '-framerate', [string]$FrameRate,
                '-start_number', [string]$fileStartNumber,
                '-i', $framePattern,
                '-frames:v', [string]$sceneFrameCount,
                '-filter_complex', $sceneFilter,
                '-loop', '0',
                $rawScene
            ) `
            -Description "Scene $sceneNumber encoding"

        Invoke-NativeToolQuietly `
            -FilePath $gifsicle `
            -Arguments @('-O3', $rawScene, '-o', $optimizedScene) `
            -Description "Scene $sceneNumber lossless optimization" | Out-Null

        $sceneFiles += $optimizedScene
        $sceneBytes = (Get-Item -LiteralPath $optimizedScene).Length
        Write-Host "  scene $sceneNumber`: $sceneFrameCount frames, $(Format-ByteCount $sceneBytes) bytes before final fitting"
    }

    $joinedGif = Join-Path $workDirectory 'joined-O3.gif'
    $joinArguments = @('-O3', '--loopcount=forever') + $sceneFiles + @('-o', $joinedGif)
    Invoke-NativeToolQuietly `
        -FilePath $gifsicle `
        -Arguments $joinArguments `
        -Description 'Scene concatenation' | Out-Null

    Write-Host "Joined GIF before fitting: $(Format-ByteCount (Get-Item -LiteralPath $joinedGif).Length) bytes"
    $best = Get-OptimizedGif `
        -Gifsicle $gifsicle `
        -InputGif $joinedGif `
        -WorkDirectory $workDirectory `
        -TargetBytes $targetBytes `
        -MaximumAllowedLossiness $MaximumLossiness

    $verified = Assert-GifOutput `
        -Ffprobe $tools.Ffprobe `
        -Gifsicle $gifsicle `
        -GifPath $best.Path `
        -ExpectedWidth $Width `
        -ExpectedHeight $Height `
        -MaximumBytes $MaxBytes

    Copy-Item -LiteralPath $best.Path -Destination $Output -Force:$Force

    Write-Host ''
    Write-Host "Created: $Output"
    Write-Host "GIF: ${Width}x${Height}, $($verified.Frames) frames, $($verified.Duration.ToString('0.###', $invariantCulture))s"
    Write-Host "Size: $(Format-ByteCount $verified.Bytes) bytes"
    Write-Host "Gifsicle: -O3 --lossy=$($best.Lossiness)"
} finally {
    if ($KeepWorkFiles) {
        Write-Host "Work files kept at: $workDirectory"
    } elseif (Test-Path -LiteralPath $workDirectory) {
        $resolvedRoot = (Resolve-Path -LiteralPath $temporaryRoot).Path.TrimEnd('\')
        $resolvedWork = (Resolve-Path -LiteralPath $workDirectory).Path
        $safePrefix = $resolvedRoot + [IO.Path]::DirectorySeparatorChar
        if (-not $resolvedWork.StartsWith($safePrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove unexpected work directory: $resolvedWork"
        }
        Remove-Item -LiteralPath $resolvedWork -Recurse -Force
    }
}
