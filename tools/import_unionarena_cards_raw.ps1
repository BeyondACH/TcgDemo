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
  if ($null -eq $html) { return "" }
  $text = $html -replace "(?is)<br\s*/?>", "`n"
  $text = $text -replace "(?is)<[^>]+>", ""
  $text = HtmlDecode $text
  $text = $text -replace "`r", ""
  $text = $text -replace "[ \t]+", " "
  $text = ($text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }) -join "`n"
  return $text.Trim()
}

function Get-SingleMatch([string]$html, [string]$pattern) {
  $m = [regex]::Match($html, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if ($m.Success) { return HtmlDecode($m.Groups[1].Value.Trim()) }
  return ""
}

function Get-BlockHtml([string]$html, [string]$className) {
  $pattern = '<dl class="cardDataCol ' + [regex]::Escape($className) + '">.*?<dd class="cardDataContents">(.*?)</dd>'
  return Get-SingleMatch $html $pattern
}

function Parse-EnergyMap([string]$blockHtml) {
  $map = [ordered]@{}
  if ([string]::IsNullOrWhiteSpace($blockHtml)) { return $map }

  $altMatches = [regex]::Matches($blockHtml, 'alt="([^"]+)"')
  foreach ($altMatch in $altMatches) {
    $alt = HtmlDecode($altMatch.Groups[1].Value)
    $energyMatch = [regex]::Match($alt, '^(' + [regex]::Escape($JP_RED) + '|' + [regex]::Escape($JP_BLUE) + '|' + [regex]::Escape($JP_GREEN) + '|' + [regex]::Escape($JP_PURPLE) + '|' + [regex]::Escape($JP_YELLOW) + '|' + [regex]::Escape($JP_WHITE) + ')(\d+)?$')
    if (-not $energyMatch.Success) { continue }

    $color = switch ($energyMatch.Groups[1].Value) {
      $JP_RED { "RED" }
      $JP_BLUE { "BLUE" }
      $JP_GREEN { "GREEN" }
      $JP_PURPLE { "PURPLE" }
      $JP_YELLOW { "YELLOW" }
      $JP_WHITE { "WHITE" }
      default { "" }
    }
    if ($color -eq "") { continue }

    $value = if ($energyMatch.Groups[2].Success) { [int]$energyMatch.Groups[2].Value } else { 1 }
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

  $normalized = $blockHtml -replace "(?is)<br\s*/?>", "`n"
  $lines = $normalized -split "`n"
  foreach ($line in $lines) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "" -or $trimmed -eq "-") { continue }

    $labelMatches = [regex]::Matches($trimmed, 'alt="([^"]+)"')
    $labels = @()
    foreach ($labelMatch in $labelMatches) {
      $decodedLabel = HtmlDecode $labelMatch.Groups[1].Value
      if ($decodedLabel -match "^(赤|青|緑|紫|黄|白)(×|x|X)?\\d+$") { continue }
      $labels += $decodedLabel
    }

    $items += [ordered]@{
      labels = $labels
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

  $id = ($number -replace "/", "_" -replace "-", "_")
  $keywords = [System.Collections.ArrayList]::new()
  $effects = [System.Collections.ArrayList]::new()
  $triggerEffects = [System.Collections.ArrayList]::new()
  $specialPlayRule = $null

  $hasRaidEffectLine = (Parse-LabeledLines $effectHtml | Where-Object { $ErrorActionPreference = "Stop"

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
  if ($null -eq $html) { return "" }
  $text = $html -replace "(?is)<br\s*/?>", "`n"
  $text = $text -replace "(?is)<[^>]+>", ""
  $text = HtmlDecode $text
  $text = $text -replace "`r", ""
  $text = $text -replace "[ \t]+", " "
  $text = ($text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }) -join "`n"
  return $text.Trim()
}

function Get-SingleMatch([string]$html, [string]$pattern) {
  $m = [regex]::Match($html, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if ($m.Success) { return HtmlDecode($m.Groups[1].Value.Trim()) }
  return ""
}

function Get-BlockHtml([string]$html, [string]$className) {
  $pattern = '<dl class="cardDataCol ' + [regex]::Escape($className) + '">.*?<dd class="cardDataContents">(.*?)</dd>'
  return Get-SingleMatch $html $pattern
}

function Parse-EnergyMap([string]$blockHtml) {
  $map = [ordered]@{}
  if ([string]::IsNullOrWhiteSpace($blockHtml)) { return $map }

  $altMatches = [regex]::Matches($blockHtml, 'alt="([^"]+)"')
  foreach ($altMatch in $altMatches) {
    $alt = HtmlDecode($altMatch.Groups[1].Value)
    $energyMatch = [regex]::Match($alt, '^(' + [regex]::Escape($JP_RED) + '|' + [regex]::Escape($JP_BLUE) + '|' + [regex]::Escape($JP_GREEN) + '|' + [regex]::Escape($JP_PURPLE) + '|' + [regex]::Escape($JP_YELLOW) + '|' + [regex]::Escape($JP_WHITE) + ')(\d+)?$')
    if (-not $energyMatch.Success) { continue }

    $color = switch ($energyMatch.Groups[1].Value) {
      $JP_RED { "RED" }
      $JP_BLUE { "BLUE" }
      $JP_GREEN { "GREEN" }
      $JP_PURPLE { "PURPLE" }
      $JP_YELLOW { "YELLOW" }
      $JP_WHITE { "WHITE" }
      default { "" }
    }
    if ($color -eq "") { continue }

    $value = if ($energyMatch.Groups[2].Success) { [int]$energyMatch.Groups[2].Value } else { 1 }
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

  $normalized = $blockHtml -replace "(?is)<br\s*/?>", "`n"
  $lines = $normalized -split "`n"
  foreach ($line in $lines) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "" -or $trimmed -eq "-") { continue }

    $labelMatches = [regex]::Matches($trimmed, 'alt="([^"]+)"')
    $labels = @()
    foreach ($labelMatch in $labelMatches) {
      $decodedLabel = HtmlDecode $labelMatch.Groups[1].Value
      if ($decodedLabel -match "^(赤|青|緑|紫|黄|白)(×|x|X)?\\d+$") { continue }
      $labels += $decodedLabel
    }

    $items += [ordered]@{
      labels = $labels
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

  $id = ($number -replace "/", "_" -replace "-", "_")
  $keywords = [System.Collections.ArrayList]::new()
  $effects = [System.Collections.ArrayList]::new()
  $triggerEffects = [System.Collections.ArrayList]::new()
  $specialPlayRule = $null

  $hasRaidEffectLine = (Parse-LabeledLines $effectHtml | Where-Object { $_.labels.Count -gt 0 -and $_.labels[0] -eq $JP_RAID }).Count -gt 0
  $seenRaidEffectLine = $false

  foreach ($item in (Parse-LabeledLines $effectHtml)) {
    $label = if ($item.labels.Count -gt 0) { $item.labels[0] } else { "" }
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

    $entry = [ordered]@{ text = $item.text }
    if ($label -ne "") {
      $entry.source_label = $label
    }
    $entry.effect_box = $currentEffectBox
    [void]$effects.Add($entry)
  }

  foreach ($item in (Parse-LabeledLines $triggerHtml)) {
    $label = if ($item.labels.Count -gt 0) { $item.labels[0] } else { "" }
    $allLabels = @($item.inline_labels)

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

function Get-CardCandidates([string]$fileBaseName) {
  if ($fileBaseName -match '^(UA\d+(?:BT|ST))-([A-Z0-9]+)-(.+)$') {
    $setCode = $matches[1]
    $titleCode = $matches[2]
    $suffix = $matches[3]
    $candidates = @("$setCode/$titleCode-$suffix")
    if ($suffix -match '^\d{3}$') {
      $candidates += "$setCode/$titleCode-1-$suffix"
    }
    return $candidates
  }

  return @($fileBaseName)
}

$picDir = Join-Path $PSScriptRoot "..\\pic"
$outPath = Join-Path $PSScriptRoot "..\\data\\cards\\cards_raw.json"
$files = Get-ChildItem -Path $picDir -Filter "*.png" | Sort-Object Name
$result = [System.Collections.ArrayList]::new()
$failures = [System.Collections.ArrayList]::new()

foreach ($file in $files) {
  $content = $null
  foreach ($candidate in (Get-CardCandidates $file.BaseName)) {
    $encoded = [uri]::EscapeDataString($candidate)
    $url = "https://www.unionarena-tcg.com/jp/cardlist/detail_iframe.php?card_no=$encoded"
    try {
      $response = Invoke-WebRequest -UseBasicParsing $url
      if ($response.Content -match "cardNumData") {
        $content = $response.Content
        break
      }
    } catch {
    }
  }

  if ($null -eq $content) {
    [void]$failures.Add($file.Name)
    continue
  }

  $card = Parse-CardPage -html $content -sourceImage $file.Name
  [void]$result.Add($card)
}

$json = $result | ConvertTo-Json -Depth 20
Set-Content -Path $outPath -Value $json -Encoding utf8

Write-Output ("written=" + $result.Count)
Write-Output ("failed=" + $failures.Count)
if ($failures.Count -gt 0) {
  Write-Output ("failed_files=" + (($failures | ForEach-Object { $_ }) -join ","))
}



.labels.Count -gt 0 -and $ErrorActionPreference = "Stop"

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
  if ($null -eq $html) { return "" }
  $text = $html -replace "(?is)<br\s*/?>", "`n"
  $text = $text -replace "(?is)<[^>]+>", ""
  $text = HtmlDecode $text
  $text = $text -replace "`r", ""
  $text = $text -replace "[ \t]+", " "
  $text = ($text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }) -join "`n"
  return $text.Trim()
}

function Get-SingleMatch([string]$html, [string]$pattern) {
  $m = [regex]::Match($html, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if ($m.Success) { return HtmlDecode($m.Groups[1].Value.Trim()) }
  return ""
}

function Get-BlockHtml([string]$html, [string]$className) {
  $pattern = '<dl class="cardDataCol ' + [regex]::Escape($className) + '">.*?<dd class="cardDataContents">(.*?)</dd>'
  return Get-SingleMatch $html $pattern
}

function Parse-EnergyMap([string]$blockHtml) {
  $map = [ordered]@{}
  if ([string]::IsNullOrWhiteSpace($blockHtml)) { return $map }

  $altMatches = [regex]::Matches($blockHtml, 'alt="([^"]+)"')
  foreach ($altMatch in $altMatches) {
    $alt = HtmlDecode($altMatch.Groups[1].Value)
    $energyMatch = [regex]::Match($alt, '^(' + [regex]::Escape($JP_RED) + '|' + [regex]::Escape($JP_BLUE) + '|' + [regex]::Escape($JP_GREEN) + '|' + [regex]::Escape($JP_PURPLE) + '|' + [regex]::Escape($JP_YELLOW) + '|' + [regex]::Escape($JP_WHITE) + ')(\d+)?$')
    if (-not $energyMatch.Success) { continue }

    $color = switch ($energyMatch.Groups[1].Value) {
      $JP_RED { "RED" }
      $JP_BLUE { "BLUE" }
      $JP_GREEN { "GREEN" }
      $JP_PURPLE { "PURPLE" }
      $JP_YELLOW { "YELLOW" }
      $JP_WHITE { "WHITE" }
      default { "" }
    }
    if ($color -eq "") { continue }

    $value = if ($energyMatch.Groups[2].Success) { [int]$energyMatch.Groups[2].Value } else { 1 }
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

  $normalized = $blockHtml -replace "(?is)<br\s*/?>", "`n"
  $lines = $normalized -split "`n"
  foreach ($line in $lines) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "" -or $trimmed -eq "-") { continue }

    $labelMatches = [regex]::Matches($trimmed, 'alt="([^"]+)"')
    $labels = @()
    foreach ($labelMatch in $labelMatches) {
      $decodedLabel = HtmlDecode $labelMatch.Groups[1].Value
      if ($decodedLabel -match "^(赤|青|緑|紫|黄|白)(×|x|X)?\\d+$") { continue }
      $labels += $decodedLabel
    }

    $items += [ordered]@{
      labels = $labels
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

  $id = ($number -replace "/", "_" -replace "-", "_")
  $keywords = [System.Collections.ArrayList]::new()
  $effects = [System.Collections.ArrayList]::new()
  $triggerEffects = [System.Collections.ArrayList]::new()
  $specialPlayRule = $null

  $hasRaidEffectLine = (Parse-LabeledLines $effectHtml | Where-Object { $_.labels.Count -gt 0 -and $_.labels[0] -eq $JP_RAID }).Count -gt 0
  $seenRaidEffectLine = $false

  foreach ($item in (Parse-LabeledLines $effectHtml)) {
    $label = if ($item.labels.Count -gt 0) { $item.labels[0] } else { "" }
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

    $entry = [ordered]@{ text = $item.text }
    if ($label -ne "") {
      $entry.source_label = $label
    }
    $entry.effect_box = $currentEffectBox
    [void]$effects.Add($entry)
  }

  foreach ($item in (Parse-LabeledLines $triggerHtml)) {
    $label = if ($item.labels.Count -gt 0) { $item.labels[0] } else { "" }
    $allLabels = @($item.inline_labels)

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

function Get-CardCandidates([string]$fileBaseName) {
  if ($fileBaseName -match '^(UA\d+(?:BT|ST))-([A-Z0-9]+)-(.+)$') {
    $setCode = $matches[1]
    $titleCode = $matches[2]
    $suffix = $matches[3]
    $candidates = @("$setCode/$titleCode-$suffix")
    if ($suffix -match '^\d{3}$') {
      $candidates += "$setCode/$titleCode-1-$suffix"
    }
    return $candidates
  }

  return @($fileBaseName)
}

$picDir = Join-Path $PSScriptRoot "..\\pic"
$outPath = Join-Path $PSScriptRoot "..\\data\\cards\\cards_raw.json"
$files = Get-ChildItem -Path $picDir -Filter "*.png" | Sort-Object Name
$result = [System.Collections.ArrayList]::new()
$failures = [System.Collections.ArrayList]::new()

foreach ($file in $files) {
  $content = $null
  foreach ($candidate in (Get-CardCandidates $file.BaseName)) {
    $encoded = [uri]::EscapeDataString($candidate)
    $url = "https://www.unionarena-tcg.com/jp/cardlist/detail_iframe.php?card_no=$encoded"
    try {
      $response = Invoke-WebRequest -UseBasicParsing $url
      if ($response.Content -match "cardNumData") {
        $content = $response.Content
        break
      }
    } catch {
    }
  }

  if ($null -eq $content) {
    [void]$failures.Add($file.Name)
    continue
  }

  $card = Parse-CardPage -html $content -sourceImage $file.Name
  [void]$result.Add($card)
}

$json = $result | ConvertTo-Json -Depth 20
Set-Content -Path $outPath -Value $json -Encoding utf8

Write-Output ("written=" + $result.Count)
Write-Output ("failed=" + $failures.Count)
if ($failures.Count -gt 0) {
  Write-Output ("failed_files=" + (($failures | ForEach-Object { $_ }) -join ","))
}



.labels[0] -eq $JP_RAID }).Count -gt 0
  $seenRaidEffectLine = $false

  foreach ($item in (Parse-LabeledLines $effectHtml)) {
    $label = if ($item.labels.Count -gt 0) { $item.labels[0] } else { "" }
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

    $entry = [ordered]@{ text = $item.text }
    if ($label -ne "") {
      $entry.source_label = $label
    }
    $entry.effect_box = $currentEffectBox
    [void]$effects.Add($entry)
  }

  foreach ($item in (Parse-LabeledLines $triggerHtml)) {
    $label = if ($item.labels.Count -gt 0) { $item.labels[0] } else { "" }
    $allLabels = @($item.inline_labels)

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

function Get-CardCandidates([string]$fileBaseName) {
  if ($fileBaseName -match '^(UA\d+(?:BT|ST))-([A-Z0-9]+)-(.+)$') {
    $setCode = $matches[1]
    $titleCode = $matches[2]
    $suffix = $matches[3]
    $candidates = @("$setCode/$titleCode-$suffix")
    if ($suffix -match '^\d{3}$') {
      $candidates += "$setCode/$titleCode-1-$suffix"
    }
    return $candidates
  }

  return @($fileBaseName)
}

$picDir = Join-Path $PSScriptRoot "..\\pic"
$outPath = Join-Path $PSScriptRoot "..\\data\\cards\\cards_raw.json"
$files = Get-ChildItem -Path $picDir -Filter "*.png" | Sort-Object Name
$result = [System.Collections.ArrayList]::new()
$failures = [System.Collections.ArrayList]::new()

foreach ($file in $files) {
  $content = $null
  foreach ($candidate in (Get-CardCandidates $file.BaseName)) {
    $encoded = [uri]::EscapeDataString($candidate)
    $url = "https://www.unionarena-tcg.com/jp/cardlist/detail_iframe.php?card_no=$encoded"
    try {
      $response = Invoke-WebRequest -UseBasicParsing $url
      if ($response.Content -match "cardNumData") {
        $content = $response.Content
        break
      }
    } catch {
    }
  }

  if ($null -eq $content) {
    [void]$failures.Add($file.Name)
    continue
  }

  $card = Parse-CardPage -html $content -sourceImage $file.Name
  [void]$result.Add($card)
}

$json = $result | ConvertTo-Json -Depth 20
Set-Content -Path $outPath -Value $json -Encoding utf8

Write-Output ("written=" + $result.Count)
Write-Output ("failed=" + $failures.Count)
if ($failures.Count -gt 0) {
  Write-Output ("failed_files=" + (($failures | ForEach-Object { $_ }) -join ","))
}




