@{
    # SolStream PSScriptAnalyzer config.
    #
    # We deliberately use Write-Host throughout the installer scripts —
    # those are colored UX output for a human runner, not data that should
    # flow through the PowerShell pipeline. PSAvoidUsingWriteHost would be
    # right for library code; it's wrong for installer scripts.
    #
    # PSUseBOMForUnicodeEncodedFile recommends a UTF-8 BOM on files with
    # non-ASCII characters. PowerShell 7+ reads UTF-8 without a BOM fine,
    # and many editors/git/CI tools fight BOMs. Skip.

    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseBOMForUnicodeEncodedFile'
    )

    # Only fail CI on Errors. Warnings are advisory.
    Severity = @('Error')
}
