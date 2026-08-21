Describe 'Developer-only visual profile exporter' {
	BeforeAll {
		$RepositoryRoot = Split-Path -Parent $PSScriptRoot
		$Exporter = Join-Path $RepositoryRoot 'tools\Export-LausudoVisualProfile.ps1'
	}

	It 'exports only allowlisted visual fields and substitutes restricted media' {
		$input = Join-Path $TestDrive 'visual-input.lua'
		$output = Join-Path $TestDrive 'visual-output.json'
		@'
ElvDB = {
  ["profiles"] = {
    ["Synthetic Visual"] = {
      ["general"] = {
        ["font"] = "Gotham Narrow Ultra",
        ["fontSize"] = 12,
        ["minimap"] = { ["size"] = 200, ["locationText"] = "SHOW" },
        ["stickyFrames"] = true,
      },
      ["chat"] = { ["font"] = "Melli", ["panelWidth"] = 410 },
      ["actionbar"] = {
        ["macrotext"] = false,
        ["bar1"] = { ["enabled"] = true, ["buttons"] = 12, ["buttonsize"] = 34 },
      },
      ["movers"] = { ["ElvUF_PlayerMover"] = "BOTTOM,ElvUIParent,BOTTOM,-285,205" },
    },
  },
}
'@ | Set-Content -LiteralPath $input -Encoding UTF8

		& $Exporter -InputPath $input -ProfileName 'Synthetic Visual' -OutputPath $output
		$LASTEXITCODE | Should -Be 0
		$result = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
		$result.sourceType | Should -Be 'sanitized-elvui-visual-profile'
		$result.visual.general.font | Should -Be 'PT Sans Narrow Bold'
		$result.visual.chat.font | Should -Be 'PT Sans Narrow Bold'
		$result.visual.general.PSObject.Properties.Name | Should -Not -Contain 'stickyFrames'
		$result.PSObject.Properties.Name | Should -Not -Contain 'profileName'
	}

	It 'fails closed on a banned identity key without creating output' {
		$input = Join-Path $TestDrive 'banned-input.lua'
		$output = Join-Path $TestDrive 'banned-output.json'
		$bannedKey = 'realm' + 'Profiles'
		@"
ElvDB = {
  ["profiles"] = {
    ["Synthetic Visual"] = {
      ["general"] = { ["font"] = "Arial Narrow" },
      ["$bannedKey"] = { ["Synthetic"] = "Synthetic Visual" },
    },
  },
}
"@ | Set-Content -LiteralPath $input -Encoding UTF8

		{ & $Exporter -InputPath $input -ProfileName 'Synthetic Visual' -OutputPath $output } | Should -Throw
		Test-Path -LiteralPath $output | Should -BeFalse
	}

	It 'fails closed on an unknown key inside a selected nested visual object' {
		$input = Join-Path $TestDrive 'unknown-input.lua'
		$output = Join-Path $TestDrive 'unknown-output.json'
		@'
ElvDB = {
  ["profiles"] = {
    ["Synthetic Visual"] = {
      ["actionbar"] = {
        ["bar1"] = { ["enabled"] = true, ["unknownSetting"] = 1 },
      },
    },
  },
}
'@ | Set-Content -LiteralPath $input -Encoding UTF8

		{ & $Exporter -InputPath $input -ProfileName 'Synthetic Visual' -OutputPath $output } | Should -Throw
		Test-Path -LiteralPath $output | Should -BeFalse
	}

	It 'fails closed on duplicate Lua table keys' {
		$input = Join-Path $TestDrive 'duplicate-key-input.lua'
		$output = Join-Path $TestDrive 'duplicate-key-output.json'
		@'
ElvDB = {
  ["profiles"] = {
    ["Synthetic Visual"] = {
      ["general"] = { ["font"] = "Arial Narrow", ["font"] = "PT Sans Narrow Bold" },
    },
  },
}
'@ | Set-Content -LiteralPath $input -Encoding UTF8

		{ & $Exporter -InputPath $input -ProfileName 'Synthetic Visual' -OutputPath $output } | Should -Throw
		Test-Path -LiteralPath $output | Should -BeFalse
	}

	It 'refuses to write into the public repository tree' {
		$input = Join-Path $TestDrive 'public-tree-input.lua'
		$output = Join-Path $RepositoryRoot 'export-should-not-exist.json'
		@'
ElvDB = { ["profiles"] = { ["Synthetic Visual"] = { ["general"] = { ["font"] = "Arial Narrow" } } } }
'@ | Set-Content -LiteralPath $input -Encoding UTF8

		{ & $Exporter -InputPath $input -ProfileName 'Synthetic Visual' -OutputPath $output } | Should -Throw
		Test-Path -LiteralPath $output | Should -BeFalse
	}
}
