@{
    # SolStream PSScriptAnalyzer config.
    #
    # We deliberately use Write-Host throughout the installer scripts -
    # those are colored UX output for a human runner, not data that should
    # flow through the PowerShell pipeline. PSAvoidUsingWriteHost would be
    # right for library code; it's wrong for installer scripts.
    #
    # NOTE: PSUseBOMForUnicodeEncodedFile is deliberately NOT excluded.
    # We learned the hard way that Windows PowerShell 5.1 (the default
    # shell on Windows) reads BOM-less UTF-8 files as Windows-1252, which
    # turns any non-ASCII character into mojibake and breaks parsing. Our
    # policy is therefore: Windows scripts must be pure ASCII (see the
    # ascii-only CI check). If a script ever does need a non-ASCII char,
    # this rule will flag it unless the file is saved with a BOM.

    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
    )

    # Only fail CI on Errors. Warnings are advisory.
    Severity = @('Error')
}
