param(
  [switch]$RefreshExisting
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Web

function U([string]$value) {
  return [regex]::Unescape($value)
}

$JP_RED = U('\u8d64')
$JP_BLUE = U('\u9752')
$JP_GREEN = U('\u7dd1')
$JP_PURPLE = U('\u7d2b')
$JP_YELLOW = U('\u9ec4')
$JP_WHITE = U('\u767d')
$JP_CHARACTER = U('\u30ad\u30e3\u30e9\u30af\u30bf\u30fc')
$JP_EVENT = U('\u30a4\u30d9\u30f3\u30c8')
$JP_FIELD = U('\u30d5\u30a3\u30fc\u30eb\u30c9')
$JP_ON_ENTER = U('\u767b\u5834\u6642')
$JP_ON_ATTACK = U('\u30a2\u30bf\u30c3\u30af\u6642')
$JP_ON_BLOCK = U('\u30d6\u30ed\u30c3\u30af\u6642')
$JP_ON_LEAVE = U('\u9000\u5834\u6642')
$JP_MAIN = U('\u30e1\u30a4\u30f3')
$JP_MAIN_ACTIVATE = U('\u8d77\u52d5\u30e1\u30a4\u30f3')
$JP_RAID = U('\u30ec\u30a4\u30c9')
$JP_DOUBLE_ATTACK = U('\u0032\u56de\u653b\u6483')
$JP_DOUBLE_BLOCK = U('\u0032\u56de\u30d6\u30ed\u30c3\u30af')
$JP_SNIPER = U('\u72d9\u3044\u6483\u3061')
$JP_DAMAGE_2 = U('\u30c0\u30e1\u30fc\u30b82')
$JP_IMPACT = U('\u30a4\u30f3\u30d1\u30af\u30c8')
$JP_IMPACT_PLUS_1 = U('\u30a4\u30f3\u30d1\u30af\u30c8\u002b1')
$JP_NEGATE_IMPACT = U('\u30a4\u30f3\u30d1\u30af\u30c8\u7121\u52b9')
$JP_FULLWIDTH_SLASH = U('\uff0f')
$JP_LEFT_ANGLE = U('\u3008')
$JP_RIGHT_ANGLE = U('\u3009')

function HtmlDecode([string]$text) {
  if ($null -eq $text) { return "" }
  return [System.Web.HttpUtility]::HtmlDecode($text)
}

function Normalize-Space([string]$text) {
  if ($null -eq $text) { return "" }
  $value = $text -replace "`r", "" -replace "`n", " "
  $value = $value -replace "\s+", " "
  return $value.Trim()
}

function Strip-Tags([string]$html) {
  if ([string]::IsNullOrWhiteSpace($html)) { return "" }
  $text = $html -replace "(?is)<br\s*/?>", "`n"
  $text = $text -replace "(?is)<[^>]+>", ""
  $text = HtmlDecode $text
  $text = $text -replace "`r", ""
  $text = $text -replace "[ \t]+", " "
  $text = ($text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }) -join "`n"
  return $text.Trim()
}

function Get-SingleMatch([string]$html, [string]$pattern) {
  $match = [regex]::Match($html, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if ($match.Success) {
    return HtmlDecode($match.Groups[1].Value.Trim())
  }
  return ""
}

function Get-BlockHtml([string]$html, [string]$className) {
  $pattern = '<dl class="cardDataCol ' + [regex]::Escape($className) + '">.*?<dd class="cardDataContents">(.*?)</dd>'
  return Get-SingleMatch $html $pattern
}

function Parse-EnergyMap([string]$blockHtml) {
  $map = [ordered]@{}
  if ([string]::IsNullOrWhiteSpace($blockHtml)) { return $map }

  $colorMap = [ordered]@{
    $JP_RED = "RED"
    $JP_BLUE = "BLUE"
    $JP_GREEN = "GREEN"
    $JP_PURPLE = "PURPLE"
    $JP_YELLOW = "YELLOW"
    $JP_WHITE = "WHITE"
  }

  $altMatches = [regex]::Matches($blockHtml, 'alt="([^"]+)"')
  foreach ($altMatch in $altMatches) {
    $alt = HtmlDecode($altMatch.Groups[1].Value)
    $color = ""
    $value = 0

    foreach ($jpColor in $colorMap.Keys) {
      $digitPattern = '^' + [regex]::Escape($jpColor) + '(\d+|\+)?$'
      $digitMatch = [regex]::Match($alt, $digitPattern)
      if ($digitMatch.Success) {
        $color = $colorMap[$jpColor]
        if ($digitMatch.Groups[1].Success) {
          $value = if ($digitMatch.Groups[1].Value -eq "+") { 1 } else { [int]$digitMatch.Groups[1].Value }
        } else {
          $value = 1
        }
        break
      }

      $repeatPattern = '^(?:' + [regex]::Escape($jpColor) + ')+$'
      if ($alt -match $repeatPattern) {
        $count = ([regex]::Matches($alt, [regex]::Escape($jpColor))).Count
        if ($count -gt 0) {
          $color = $colorMap[$jpColor]
          $value = $count
          break
        }
      }
    }
    if ($color -eq "" -or $value -le 0) { continue }

    if ($map.Contains($color)) {
      $map[$color] += $value
    } else {
      $map[$color] = $value
    }
  }

  return $map
}

function Split-Traits([string]$traitsText) {
  if ([string]::IsNullOrWhiteSpace($traitsText)) { return @() }
  $parts = $traitsText -split ("[" + [regex]::Escape($JP_FULLWIDTH_SLASH) + "/]")
  $result = @()
  foreach ($part in $parts) {
    $value = Normalize-Space $part
    if ($value -eq "" -or $value -eq "-") { continue }
    $result += $value
  }
  return $result
}

function Parse-LabeledLines([string]$blockHtml) {
  $items = @()
  if ([string]::IsNullOrWhiteSpace($blockHtml)) { return $items }

  $energyLabelPattern = '^(' + [regex]::Escape($JP_RED) + '|' + [regex]::Escape($JP_BLUE) + '|' + [regex]::Escape($JP_GREEN) + '|' + [regex]::Escape($JP_PURPLE) + '|' + [regex]::Escape($JP_YELLOW) + '|' + [regex]::Escape($JP_WHITE) + ')(×|x|X)?\d+$'

  $normalized = $blockHtml -replace "(?is)<br\s*/?>", "`n"
  $lines = $normalized -split "`n"
  foreach ($line in $lines) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "" -or $trimmed -eq "-") { continue }

    $labelMatches = [regex]::Matches($trimmed, 'alt="([^"]+)"')
    $labels = @()
    foreach ($labelMatch in $labelMatches) {
      $decodedLabel = HtmlDecode $labelMatch.Groups[1].Value
      if ($decodedLabel -match $energyLabelPattern) { continue }
      $labels += $decodedLabel
    }

    $items += [ordered]@{
      labels = @($labels)
      inline_labels = @($labels)
      text = Strip-Tags $trimmed
    }
  }

  return $items
}

function Get-TriggerName([string]$label) {
  switch ($label) {
    $JP_ON_ENTER { return "ON_ENTER" }
    $JP_ON_ATTACK { return "ON_ATTACK" }
    $JP_ON_BLOCK { return "ON_BLOCK" }
    $JP_ON_LEAVE { return "ON_LEAVE" }
    $JP_MAIN { return "MAIN_ACTIVATE" }
    $JP_MAIN_ACTIVATE { return "MAIN_ACTIVATE" }
    default { return "" }
  }
}

function Add-Keyword([System.Collections.ArrayList]$keywords, [string]$keyword) {
  if ([string]::IsNullOrWhiteSpace($keyword)) { return }
  if (-not $keywords.Contains($keyword)) {
    [void]$keywords.Add($keyword)
  }
}

function Convert-NumberToId([string]$number) {
  return ($number -replace "/", "_" -replace "-", "_")
}

function Get-CardCandidates([string]$fileBaseName) {
  if ($fileBaseName -match '^(UA\d+(?:BT|ST))-([A-Z0-9]+)-(.+)$') {
    $setCode = $matches[1]
    $titleCode = $matches[2]
    $suffix = $matches[3]
    $candidates = [System.Collections.ArrayList]::new()
    [void]$candidates.Add("$setCode/$titleCode-$suffix")
    if ($suffix -match '^\d{3}$') {
      [void]$candidates.Add("$setCode/$titleCode-1-$suffix")
    }
    return @($candidates.ToArray())
  }

  return @($fileBaseName)
}

function Test-RequiredCardFields($card) {
  $required = @("id", "name", "card_type", "title_code", "number", "rarity", "series_title", "source_image", "source_url")
  foreach ($field in $required) {
    if ([string]::IsNullOrWhiteSpace([string]$card.$field)) {
      return $false
    }
  }
  return $true
}

function Parse-CardPage([string]$html, [string]$sourceImage) {
  $name = Get-SingleMatch $html '<h2 class="cardNameCol">\s*(.*?)\s*<span class="rubyData">'
  $ruby = Get-SingleMatch $html '<span class="rubyData">(.*?)</span>'
  $number = Get-SingleMatch $html '<span class="cardNumData">(.*?)</span>'
  $rarity = Get-SingleMatch $html '<span class="rareData">(.*?)</span>'
  $seriesTitle = Get-SingleMatch $html '<dd class="cardDataTitleCol[^>]*><img[^>]+alt="([^"]+)"'
  $needEnergyHtml = Get-BlockHtml $html "needEnergyData"
  $apText = Get-BlockHtml $html "apData"
  $categoryText = Get-BlockHtml $html "categoryData"
  $bpText = Get-BlockHtml $html "bpData"
  $traitsText = Get-BlockHtml $html "attributeData"
  $generatedEnergyHtml = Get-BlockHtml $html "generatedEnergyData"
  $effectHtml = Get-BlockHtml $html "effectData"
  $triggerHtml = Get-BlockHtml $html "triggerData"

  $cardType = switch ((Strip-Tags $categoryText)) {
    $JP_CHARACTER { "CHARACTER" }
    $JP_EVENT { "EVENT" }
    $JP_FIELD { "FIELD" }
    default { "CHARACTER" }
  }

  $titleCode = ""
  if ($number -match '^UA\d+(?:BT|ST)/([A-Z0-9]+)-') {
    $titleCode = $matches[1]
  }

  $id = Convert-NumberToId $number
  $keywords = [System.Collections.ArrayList]::new()
  $effects = [System.Collections.ArrayList]::new()
  $triggerEffects = [System.Collections.ArrayList]::new()
  $specialPlayRule = $null

  $effectLines = Parse-LabeledLines $effectHtml
  $triggerLines = Parse-LabeledLines $triggerHtml
  $hasRaidEffectLine = ($effectLines | Where-Object { $_.labels.Count -gt 0 -and $_.labels[0] -eq $JP_RAID }).Count -gt 0
  $seenRaidEffectLine = $false

  foreach ($item in $effectLines) {
    $label = if ($item.labels.Count -gt 0) { [string]$item.labels[0] } else { "" }
    $allLabels = @($item.inline_labels)
    $currentEffectBox = if ($hasRaidEffectLine -and $seenRaidEffectLine) { "RAID_INNER" } else { "OUTER" }

    if ($label -eq $JP_RAID) {
      $currentEffectBox = "RAID_INNER"
      Add-Keyword $keywords "RAID"
      $raidPattern = '^' + [regex]::Escape($JP_LEFT_ANGLE) + '(.+?)' + [regex]::Escape($JP_RIGHT_ANGLE)
      if ($item.text -match $raidPattern) {
        $specialPlayRule = [ordered]@{
          type = "RAID"
          raid_target_name = $matches[1]
          allow_from_hand = $true
          require_full_energy = $true
        }
      }
      [void]$effects.Add([ordered]@{
        source_label = $label
        effect_box = $currentEffectBox
        text = $item.text
      })
      $seenRaidEffectLine = $true
      continue
    }

    $triggerName = Get-TriggerName $label
    if ($triggerName -ne "") {
      [void]$triggerEffects.Add([ordered]@{
        trigger = $triggerName
        source_label = $label
        effect_box = $currentEffectBox
        text = $item.text
      })
      continue
    }

    if ($allLabels -contains $JP_DOUBLE_ATTACK -or $item.text -match [regex]::Escape($JP_DOUBLE_ATTACK)) { Add-Keyword $keywords "DOUBLE_ATTACK" }
    if ($allLabels -contains $JP_DOUBLE_BLOCK -or $item.text -match [regex]::Escape($JP_DOUBLE_BLOCK)) { Add-Keyword $keywords "DOUBLE_BLOCK" }
    if ($allLabels -contains $JP_SNIPER -or $item.text -match [regex]::Escape($JP_SNIPER)) { Add-Keyword $keywords "SNIPER" }
    if ($allLabels -contains "Step" -or $allLabels -contains "STEP" -or $item.text -match "Step|STEP") { Add-Keyword $keywords "STEP" }
    if ($allLabels -contains $JP_DAMAGE_2 -or $item.text -match [regex]::Escape($JP_DAMAGE_2)) { Add-Keyword $keywords "DAMAGE_2" }
    if ($allLabels -contains $JP_IMPACT_PLUS_1 -or $item.text -match [regex]::Escape($JP_IMPACT_PLUS_1)) { Add-Keyword $keywords "IMPACT_PLUS_1" }
    if ($allLabels -contains $JP_NEGATE_IMPACT -or $item.text -match [regex]::Escape($JP_NEGATE_IMPACT)) { Add-Keyword $keywords "NEGATE_IMPACT" }
    if ($allLabels -contains $JP_IMPACT -or $item.text -match [regex]::Escape($JP_IMPACT)) { Add-Keyword $keywords "IMPACT" }

    $entry = [ordered]@{
      text = $item.text
      effect_box = $currentEffectBox
    }
    if ($label -ne "") {
      $entry.source_label = $label
    }
    [void]$effects.Add($entry)
  }

  foreach ($item in $triggerLines) {
    $label = if ($item.labels.Count -gt 0) { [string]$item.labels[0] } else { "" }
    if ($label -eq $JP_RAID) {
      Add-Keyword $keywords "RAID"
      [void]$triggerEffects.Add([ordered]@{
        trigger = "RAID_RULE"
        source_label = $label
        effect_box = "RAID_INNER"
        text = $item.text
      })
      continue
    }

    [void]$triggerEffects.Add([ordered]@{
      trigger = "ON_LIFE_TRIGGER"
      source_label = if ($label -ne "") { $label } else { "TRIGGER" }
      effect_box = "OUTER"
      text = $item.text
    })
  }

  $card = [ordered]@{
    id = $id
    name = $name
    card_type = $cardType
    title_code = $titleCode
    number = $number
    traits = @(Split-Traits (Strip-Tags $traitsText))
    cost_energy = Parse-EnergyMap $needEnergyHtml
    cost_ap = if ((Strip-Tags $apText) -match '^\d+$') { [int](Strip-Tags $apText) } else { 0 }
    energy_provided = Parse-EnergyMap $generatedEnergyHtml
    bp = if ((Strip-Tags $bpText) -match '^\d+$') { [int](Strip-Tags $bpText) } else { 0 }
    keywords = @($keywords.ToArray())
    effects = @($effects.ToArray())
    trigger_effects = @($triggerEffects.ToArray())
    rarity = $rarity
    series_title = $seriesTitle
    source_image = $sourceImage
    source_url = "https://www.unionarena-tcg.com/jp/cardlist/detail.php?card_no=$number"
    raw_effect_text = Strip-Tags $effectHtml
    raw_trigger_text = Strip-Tags $triggerHtml
    ruby = $ruby
  }

  if ($null -ne $specialPlayRule) {
    $card.special_play_rule = $specialPlayRule
  }

  return $card
}

function Read-JsonArray([string]$path) {
  if (-not (Test-Path $path)) { return @() }
  $text = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false)).Trim()
  if ($text -eq "") { return @() }
  return @($text | ConvertFrom-Json)
}

function Write-Utf8Json([string]$path, $data) {
  $json = $data | ConvertTo-Json -Depth 20
  [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Get-SortKey([string]$number) {
  return $number.Replace("/", "-")
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$picDir = Join-Path $repoRoot "pic"
$rawPath = Join-Path $repoRoot "data\\cards\\cards_raw.json"

$cards = [System.Collections.ArrayList]::new()
foreach ($card in (Read-JsonArray $rawPath)) {
  [void]$cards.Add($card)
}

$existingNumbers = New-Object 'System.Collections.Generic.HashSet[string]'
$existingIds = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($card in $cards) {
  $null = $existingNumbers.Add([string]$card.number)
  $null = $existingIds.Add([string]$card.id)
}

$files = Get-ChildItem -Path $picDir -File | Where-Object { $_.Extension.ToLowerInvariant() -in @(".png", ".jpg", ".jpeg", ".webp") } | Sort-Object Name
$added = [System.Collections.ArrayList]::new()
$failures = [System.Collections.ArrayList]::new()
$skippedExisting = [System.Collections.ArrayList]::new()

foreach ($file in $files) {
  $candidates = @(Get-CardCandidates $file.BaseName)
  $candidateIds = @($candidates | ForEach-Object { Convert-NumberToId $_ })
  $alreadyExists = $false
  if (-not $RefreshExisting) {
    foreach ($candidate in $candidates) {
      if ($existingNumbers.Contains($candidate)) {
        $alreadyExists = $true
        break
      }
    }
    if (-not $alreadyExists) {
      foreach ($candidateId in $candidateIds) {
        if ($existingIds.Contains($candidateId)) {
          $alreadyExists = $true
          break
        }
      }
    }
    if ($alreadyExists) {
      [void]$skippedExisting.Add($file.Name)
      continue
    }
  }

  $content = $null
  $matchedCandidate = ""
  foreach ($candidate in $candidates) {
    $encoded = [uri]::EscapeDataString($candidate)
    $url = "https://www.unionarena-tcg.com/jp/cardlist/detail_iframe.php?card_no=$encoded"
    try {
      $response = Invoke-WebRequest -UseBasicParsing $url
      if ($response.Content -notmatch "cardNumData") { continue }
      $parsedNumber = Get-SingleMatch $response.Content '<span class="cardNumData">(.*?)</span>'
      if ($parsedNumber -ne $candidate) { continue }
      $content = $response.Content
      $matchedCandidate = $candidate
      break
    } catch {
      continue
    }
  }

  if ($null -eq $content) {
    [void]$failures.Add([ordered]@{
      file = $file.Name
      reason = "official_page_not_found"
    })
    continue
  }

  $card = Parse-CardPage -html $content -sourceImage $file.Name
  if ($card.number -ne $matchedCandidate -or -not (Test-RequiredCardFields $card)) {
    [void]$failures.Add([ordered]@{
      file = $file.Name
      reason = "missing_required_fields"
      number = $card.number
    })
    continue
  }

  if (-not $RefreshExisting -and ($existingNumbers.Contains([string]$card.number) -or $existingIds.Contains([string]$card.id))) {
    [void]$skippedExisting.Add($file.Name)
    continue
  }

  if ($RefreshExisting) {
    for ($index = $cards.Count - 1; $index -ge 0; $index--) {
      $existingCard = $cards[$index]
      if ([string]$existingCard.number -eq [string]$card.number -or [string]$existingCard.id -eq [string]$card.id) {
        $cards.RemoveAt($index)
      }
    }
  }

  [void]$cards.Add($card)
  [void]$added.Add($card.number)
  $null = $existingNumbers.Add([string]$card.number)
  $null = $existingIds.Add([string]$card.id)
}

$sortedCards = @($cards | Sort-Object @{ Expression = { Get-SortKey ([string]$_.number) } })
Write-Utf8Json -path $rawPath -data $sortedCards

Write-Output ("scanned=" + $files.Count)
Write-Output ("skipped_existing=" + $skippedExisting.Count)
Write-Output ("added=" + $added.Count)
Write-Output ("failed=" + $failures.Count)
if ($added.Count -gt 0) {
  Write-Output ("added_numbers=" + (($added | ForEach-Object { $_ }) -join ","))
}
if ($failures.Count -gt 0) {
  Write-Output "failed_cards="
  foreach ($failure in $failures) {
    Write-Output ("- " + $failure.file + ": " + $failure.reason + ($(if ($failure.number) { " (" + $failure.number + ")" } else { "" })))
  }
}
