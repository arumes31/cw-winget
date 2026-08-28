BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $workflowDirectories = @("update-all", "update-single-app")
    $scripts = foreach ($directory in $workflowDirectories) {
        Get-ChildItem (Join-Path $repositoryRoot $directory) -Filter *.ps1
    }
}

Describe "PowerShell source integrity" {
    It "parses every production script" {
        $parseErrors = @()
        foreach ($script in $scripts) {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $script.FullName,
                [ref]$tokens,
                [ref]$errors
            ) | Out-Null
            $parseErrors += $errors
        }
        $parseErrors | Should -BeNullOrEmpty
    }

    It "does not use non-cryptographic Get-Random" {
        ($scripts | Get-Content -Raw) | Should -Not -Match "\bGet-Random\b"
    }

    It "does not serialize a password into workflow state or output" {
        $source = $scripts | Get-Content -Raw
        $source | Should -Not -Match "Step\|Username\|Password"
        $source | Should -Not -Match "Write-(Output|Host)[^\r\n]*(Password|AdminPass)"
        $source | Should -Not -Match "\$\{Password\}\|"
        $source | Should -Not -Match "\$\{AdminPass\}\|"
    }

    It "does not put a password on a child-process command line" {
        ($scripts | Get-Content -Raw) | Should -Not -Match "Start-Process[^\r\n]*(Password|AdminPass)"
    }
}

Describe "Temporary administrator lifecycle" {
    It "uses the operating system cryptographic random-number generator" {
        foreach ($directory in $workflowDirectories) {
            $createScript = Get-Content (Join-Path $repositoryRoot "$directory/1_CreateTempAdmin.ps1") -Raw
            $createScript | Should -Match "RandomNumberGenerator\]::Create\(\)"
            $createScript | Should -Match "Disable-LocalUser"
            $createScript | Should -Match "New-LocalUser[^\r\n]*-Disabled"
        }
    }

    It "generates a single 32-character password with every required character class" {
        $createPath = Join-Path $repositoryRoot "update-all/1_CreateTempAdmin.ps1"
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $createPath,
            [ref]$tokens,
            [ref]$errors
        )
        $functions = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -in "Get-CryptographicIndex", "New-CryptographicPassword"
        }, $true)
        foreach ($function in $functions) {
            . ([scriptblock]::Create($function.Extent.Text))
        }

        $PasswordLength = 32
        $CharacterSets = @(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            "abcdefghijklmnopqrstuvwxyz"
            "0123456789"
            "!@#$%^&*_-+="
        )
        $password = New-CryptographicPassword
        $password | Should -BeOfType string
        $password.Length | Should -Be 32
        $password | Should -Match '[A-Z]'
        $password | Should -Match '[a-z]'
        $password | Should -Match '[0-9]'
        $password | Should -Match '[!@#$%^&*_{+=}-]'
    }

    It "keeps compatibility step 4 disabled" {
        foreach ($directory in $workflowDirectories) {
            $step = Get-Content (Join-Path $repositoryRoot "$directory/4_EnableAccount.ps1") -Raw
            $step | Should -Match "Disable-LocalUser"
            $step | Should -Not -Match "(?m)^\s*Enable-LocalUser"
        }
    }

    It "disables and rotates the account in step 5 finally cleanup" {
        foreach ($directory in $workflowDirectories) {
            $step = Get-Content (Join-Path $repositoryRoot "$directory/5_RunWingetUpdate.ps1") -Raw
            $finallyIndex = $step.LastIndexOf("finally {")
            $finallyIndex | Should -BeGreaterThan 0
            $cleanup = $step.Substring($finallyIndex)
            $cleanup | Should -Match 'Set-TemporaryAccountEnabled -Enabled \$false'
            $cleanup | Should -Match "Set-TemporaryAccountPassword"
            $cleanup | Should -Match "Unregister-ScheduledTask"
        }
    }

    It "has an independent outer cleanup guard" {
        foreach ($directory in $workflowDirectories) {
            $runner = Get-Content (Join-Path $repositoryRoot "$directory/Run-WingetAutomated.ps1") -Raw
            $runner | Should -Match "finally\s*\{[\s\S]*EmergencyCleanup"
            $runner | Should -Match 'Invoke-ScriptWithState -ScriptFile "6_DisableTempAdmin.ps1"'
        }
    }
}
