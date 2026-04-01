function Assert-ConfigFields {
    <#
    .SYNOPSIS
        Validates that an object has all required fields and none are empty.
        Throws a descriptive error if any field is missing or blank.

    .DESCRIPTION
        Used by consumer repos to validate JSON config entries without
        duplicating the PS 5.1-compatible Get-Member + IsNullOrWhiteSpace
        loop.

    .PARAMETER Object
        The PSCustomObject to validate (e.g. a single VM entry).

    .PARAMETER Fields
        Array of field names that must be present and non-empty.

    .PARAMETER Context
        String used in error messages (e.g. "VM 'ubuntu-01-ci'").

    .EXAMPLE
        Assert-ConfigFields -Object $vm -Fields @('vmName','ipAddress') `
            -Context "VM '$($vm.vmName)'"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Object,

        [Parameter(Mandatory)]
        [string[]] $Fields,

        [Parameter(Mandatory)]
        [string] $Context
    )

    # Get-Member -MemberType NoteProperty is the reliable way to enumerate
    # properties created by ConvertFrom-Json in PS 5.1 and PS 7.
    $members = (Get-Member -InputObject $Object -MemberType NoteProperty).Name

    foreach ($field in $Fields) {
        if ($members -notcontains $field) {
            throw "$Context is missing required field '$field'."
        }

        # Cast to [string] before IsNullOrWhiteSpace: numeric fields
        # (e.g. cpuCount) are [int] in PS 5.1 and the method requires [string].
        if ([string]::IsNullOrWhiteSpace([string]($Object.$field))) {
            throw "$Context has empty required field '$field'."
        }
    }
}
